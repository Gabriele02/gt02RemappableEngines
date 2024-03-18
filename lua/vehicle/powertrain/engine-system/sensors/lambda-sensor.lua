local M = {}

local type = "wb" -- wb: wideband, nb: narrowband
local range = {0.68, 1.5} -- {0.68, 1.5} for nb where 1.5 is lean and 0.68 is rich
local randomness = 0.10
local smoothing = nil
local function init(data, state, readings)
    randomness = clamp(1 - data.sensors.lambdaSensor.quality, 0, 1)
    type = data.sensors.lambdaSensor.type --or "wb"
    range = data.sensors.lambdaSensor.range
    smoothing = newExponentialSmoothing(data.sensors.lambdaSensor.responseTime * 2000, (range[2] + range[1]) / 2)
    readings.value = 0
    return state
end

local function update(state, readings, dt)
    local lambda = state.lambda
    local reading = 0
    if type == "wb" then
        reading = lambda * math.random(1 - randomness, 1 + randomness)
    elseif type == "nb" then
        reading = 1
        if lambda < 1 * math.random(1 - randomness, 1 + randomness) then -- rich
            reading = range[1]
        elseif lambda > 1 * math.random(1 - randomness, 1 + randomness) then -- lean
            reading = range[2]
        end
    end
    reading = math.min(math.max(reading, range[1]), range[2]) -- always clamp the lambda value
    readings.value = smoothing:get(reading)
end

M.init = init
M.update = update
return M