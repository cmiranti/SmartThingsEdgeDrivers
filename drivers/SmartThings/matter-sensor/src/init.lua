-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"

--TODO remove once device:refresh() exists for subscribed attributes
local cluster_subscribe_list = {
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.IlluminanceMeasurement.attributes.MeasuredValue,
  clusters.BooleanState.attributes.StateValue,
  clusters.OccupancySensing.attributes.Occupancy,
  clusters.PowerSource.attributes.BatPercentRemaining,
}

local function device_init(driver, device)
  log.info("device init")
  device:subscribe()
end

local function do_refresh(driver, device, cmd)
  local refresh_request = nil
  for _, cluster in ipairs(cluster_subscribe_list) do
    if device:supports_server_cluster(cluster._cluster.ID) then
      local req = cluster:read(device)
      if refresh_request == nil then
        refresh_request = req
      else
        refresh_request:merge(req)
      end
    end
  end
  device:send(refresh_request)
end

local function illuminance_attr_handler(driver, device, ib, response)
  local lux = math.floor(math.pow(10, (ib.data.value - 1) / 10000))
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
end

local function temperature_attr_handler(driver, device, ib, response)
  local temp = ib.data.value / 100.0
  local unit = "C"
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
end

local function humidity_attr_handler(driver, device, ib, response)

  local humidity = utils.round(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local function boolean_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.closed())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.open())
  end
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local function occupancy_attr_handler(driver, device, ib, response)
    device:emit_event(ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init
  },
  matter_handlers = {
    attr = {
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_attr_handler
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = illuminance_attr_handler
      },
      [clusters.BooleanState.ID] = {
        [clusters.BooleanState.attributes.StateValue.ID] = boolean_attr_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID]   = battery_percent_remaining_attr_handler,
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler,
      },
    }
  },
  -- TODO Once capabilities all have default handlers move this info there, and
  -- use `supported_capabilities`
  subscribed_attributes = {
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.illuminanceMeasurement.ID] = {
      clusters.IlluminanceMeasurement.attributes.MeasuredValue
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    },
    [capabilities.contactSensor.ID] = {
      clusters.BooleanState.attributes.StateValue
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
  }
}

local matter_driver = MatterDriver("matter-sensor", matter_driver_template)
matter_driver:run()
