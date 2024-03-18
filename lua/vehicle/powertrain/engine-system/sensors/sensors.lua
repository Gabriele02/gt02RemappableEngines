local M = {}

local knockSensor = require("vehicle.powertrain.engine-system.sensors.knock-sensor")
local MAPSensor = require("vehicle.powertrain.engine-system.sensors.map-sensor")
local lambdaSensor = require("vehicle.powertrain.engine-system.sensors.lambda-sensor")

local sensors = {
    knock = knockSensor,
    MAP = MAPSensor,
    lambda = lambdaSensor
}
local readings = {}
local function init(data, state)
    for sensorName, sensor in pairs(sensors) do
        readings[sensorName] = {}
        state = sensor.init(data, state, readings[sensorName])
    end
    return state
end

local function update(state, dt)
    for sensorName, sensor in pairs(sensors) do
        sensor.update(state, readings[sensorName], dt)
    end
end

M.init = init
M.update = update
M.getSensorValue = function(sensorName)
    if readings[sensorName] == nil then
        return nil
    end
    return readings[sensorName].value
end
M.getSensorValues = function()
    return readings
end
return M