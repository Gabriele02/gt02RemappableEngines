local M = {}

local sensitivity = 0
local knockThresholdFromSensitivity = nil
local randomness = 0.10 
local simEngine = nil
local function init(data, state, readings)
    state.knockSensor = false
    knockThresholdFromSensitivity = createCurve(data.sensors.knockSensor.knockThresholdFromSensitivity, true)
    randomness = clamp(1 - data.sensors.knockSensor.quality, 0, 1)
    readings.value = 0
    simEngine = data.engine
    return state
end

local function update(state, readings, dt)
    --TODO: load from map
    sensitivity = clamp(simEngine.getOptionValue('knock-sensitivity') * 0.01, 0, 1)

    if sensitivity == 0 then
        return
    end

    local knockThreshold = knockThresholdFromSensitivity[math.ceil(sensitivity * 100)] * math.random(1 - randomness, 1 + randomness)
    if state.max_pressure_point_dATDC <= knockThreshold then
        state.knockSensor = true
    else
        state.knockSensor = false
    end
    local knockIntensity = 0
    if knockThreshold > 0 then
        knockIntensity = 1 - state.max_pressure_point_dATDC / knockThreshold
    else
        knockIntensity = -state.max_pressure_point_dATDC / -knockThreshold
    end
    readings.value = clamp(knockIntensity, 0, 1)
end

M.init = init
M.update = update
return M