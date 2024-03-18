local M = {}

local delayLine = require("delayLine")

local targetFuelPresure_bar = 0 --[[bar]]
local fprDeplayLine = nil

local function init(data, state)
    targetFuelPresure_bar = data.fuelSystemMeasurements.fuel_pressure_regulator.pressure_bar
    if not state.fuelSystem then
        state.fuelSystem = {}
    end
    fprDeplayLine = delayLine.new(0.1)
    return state
end

local function update(state, dt) -- -> modifyed state
    local fuel_pressure = targetFuelPresure_bar + (state.manifold.MAP / 100 - 1) --[[kPa to bar]]
    fuel_pressure = math.min(fuel_pressure, state.fuelSystem.fuel_lines_pressure_bar)
    local return_pressure = math.max(state.fuelSystem.fuel_lines_pressure_bar - fuel_pressure, 0)
    -- add delay line
    --fprDeplayLine:push(fuel_pressure)
    --fuel_pressure = fprDeplayLine:popSum(dt)

    if not state.torqueCurveCreation then
        fuel_pressure = fuel_pressure + (math.random(-1, 1) * 0.05)
    end
    state.fuelSystem.pressure_bar = fuel_pressure
end

M.init = init
M.update = update
return M