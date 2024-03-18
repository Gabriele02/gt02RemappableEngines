local M = {}

local smoother = nil -- simulate map sensor response time
local range = {0, 103}
local randomness = 0
local function init(data, state, readings)
    randomness = clamp(1 - data.sensors.MAPSensor.quality, 0, 1)
    smoother = newExponentialSmoothing(data.sensors.MAPSensor.responseTime * 2000, 100) --newExponentialSmoothing(, 100)
    range = data.sensors.MAPSensor.range
    readings.value = 0
    return state
end

local function update(state, readings, dt)
    local actualMAP = state.manifold.MAP-- * math.random(1 - randomness, 1 + randomness)
    local MAP = smoother:get(actualMAP)
    MAP = math.min(math.max(MAP, range[1]), range[2])
    readings.value = MAP
end

M.init = init
M.update = update
return M