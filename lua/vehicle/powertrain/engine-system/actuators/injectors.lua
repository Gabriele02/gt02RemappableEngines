local M = {}

local injector_max_mg_s = 0

function init(data, state)
    injector_max_mg_s = data.fuelSystemMeasurements.injectors.injector_max_mg_s
    return state
end

function update(state, dt) -- -> modifyed state

    --TODO: move to engine-system/fuelSystem/fuelPressureRegulator.lua
    -- scale injector max mg/s based on fuel pressure
    local fuel_pressure = 3 --[[bar]] --TODO: state.fuelSystem.pressure
    if not state.torqueCurveCreation then
        fuel_pressure = fuel_pressure + (math.random(-1, 1) * 0.05)
    end
    local mult_factor = math.sqrt(fuel_pressure / 3)

    local actual_injector_max_mg_s = injector_max_mg_s * mult_factor
    --TODO: smooth

    state.manifold.runners.injectors.fuel_mg_per_combustion =
        actual_injector_max_mg_s * state.manifold.runners.injectors.on_time_s
    if not state.torqueCurveCreation then
        state.manifold.runners.injectors.fuel_mg_per_combustion =
            math.max(state.manifold.runners.injectors.fuel_mg_per_combustion + (math.random(-1, 1) * 0.01), 0)
    end
end

M.init = init
M.update = update
return M