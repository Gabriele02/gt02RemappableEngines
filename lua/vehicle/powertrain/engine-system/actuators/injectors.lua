local M = {}

local injector_max_mg_s = 0
local engineMeasurements = nil

local function init(data, state)
    engineMeasurements = data.engineMeasurements
    injector_max_mg_s = data.fuelSystemMeasurements.injectors.injector_max_mg_s
    if state.fuelSystem == nil then
        state.fuelSystem = {}
    end
    state.fuelSystem.flow_l_h = 0
    state.fuelSystem.pressure_bar = 0
    return state
end

local function update(state, dt) -- -> modifyed state

    --TODO: move to engine-system/fuelSystem/fuelPressureRegulator.lua
    -- scale injector max mg/s based on fuel pressure
    -- get pressure differenial between fuel pressure and manifold pressure

    local fuel_pressure = state.fuelSystem.pressure_bar
    local manifold_pressure = state.manifold.MAP / 100 --[[kPa to bar]]

    local pressure_diff = fuel_pressure - (manifold_pressure - 1) --[[bar]]

    local mult_factor = math.sqrt(pressure_diff / 3)

    local actual_injector_max_mg_s = injector_max_mg_s * mult_factor

    -- caluclate fuel flow
    local fuel_flow_mg_s = actual_injector_max_mg_s * state.manifold.runners.injectors.on_time_s  * engineMeasurements.num_cylinders * state.combustionsPerSecond
    -- convert in mg/h
    local fuel_flow_mg_h = fuel_flow_mg_s * 3600
    -- convert in kg/h
    local fuel_flow_kg_h = fuel_flow_mg_h / 1000000
    -- convert in l/h
    local fuel_flow_l_h = fuel_flow_kg_h / state.fuelSystem.fuel_density_kg_l

    state.fuelSystem.flow_l_h = fuel_flow_l_h
    --print("fuel_flow_l_h" .. state.fuelSystem.flow_l_h)
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