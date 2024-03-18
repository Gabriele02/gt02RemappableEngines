local M = {}

local throttle_actuator = require("vehicle.powertrain.engine-system.actuators.throttle")
local runners = require("vehicle.powertrain.engine-system.intake.runners")
local fpr = require("vehicle.powertrain.engine-system.actuators.fuelPressureRegulator")

local combustionEngine = nil
local engineMeasurements = nil
local intakeMeasurements = nil

local atmToKPa = 101.325
local specific_gravity_air = 1
local massAirflowOutIntake = 0

local function init(data, state)
    engineMeasurements = data.engineMeasurements
    intakeMeasurements = data.intakeMeasurements
    combustionEngine = data.combustionEngine
    -- init components
    state = fpr.init(data, state)

    state = throttle_actuator.init(data, state)
    state = runners.init(data, state)

    return state
end

local function calculateIntakePressureAndFlowInOutBalance(state, dt)
    -- Calculate air density
    intakeMeasurements.airDensity = (intakeMeasurements.IAP * 1000) --[[kPa to Pa]] / (287.0500676--[[J/(Kg*K)]] * intakeMeasurements.IAT)
    
    state.manifold.IAT = intakeMeasurements.IAT

    local mapAtm = state.manifold.MAP / atmToKPa --[[KPa to atm]]
    --https://it.mathworks.com/help/simulink/slref/modeling-engine-timing-using-triggered-subsystems.html
    -- Calculate MAP derivative
    --TODO: find temperature correction factor
    local MAP_derivative = 0.41328 * (state.manifold.throttle.massAirflowIntoIntake - massAirflowOutIntake)

    -- Mass airflow into engine from intake manifold
    massAirflowOutIntake = state.manifold.MAFTotal * 1000 --[[kg/s to g/s]]

    state.manifold.MAP = math.max(math.min(mapAtm + (MAP_derivative * dt), 0.99 * intakeMeasurements.IAP / atmToKPa), 0) * atmToKPa

    -- Calculate engine load
    state.instantEngineLoad = math.max(math.min(state.manifold.MAP / atmToKPa, 1), 0)
    state.engineLoad = combustionEngine.loadSmoother:get(state.instantEngineLoad, dt)

    -- MAF Integration
    local IMAP = state.RPM * state.manifold.MAP / intakeMeasurements.IAT / 2
    -- where simEngine.state.RPM is combustionEngine speed in revolutions per minute
    -- MAP (manifold absolute pressure) is measured in KPa
    -- IAT (intake air temperature) is measured in degrees Kelvin.

    --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
    local air_mass_flow = ((IMAP or 0) / 60) * (state.volumetric_efficiency or 0) *
        (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

    local air_mass_flow_mg_s = air_mass_flow * 1000 --[[kg/s to g/s]] * 1000 --[[g/s to mg/s]] / engineMeasurements.num_cylinders
    local mg_per_combustion = air_mass_flow_mg_s / state.combustionsPerSecond

    state.manifold.MAF = mg_per_combustion
    state.manifold.MAFTotal = air_mass_flow
    --return state
end

local function update(state, dt) -- -> modifyed state
    -- 1 Throttle position
    throttle_actuator.update(state, dt)

    -- 2 Intake manifold pressure
    calculateIntakePressureAndFlowInOutBalance(state, dt)

    -- 3 Fuel pressure regulator (Should be fuel system when implemented)
    fpr.update(state, dt)

    -- 4 Runners
    runners.update(state, dt)

end

M.init = init
M.update = update
return M