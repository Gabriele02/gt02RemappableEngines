local M = {}

--TODO: add intake tract and air filtering system
local manifold = require("lua.vehicle.powertrain.engine-system.intake.manifold")
local intercooler = require("lua.vehicle.powertrain.engine-system.intake.intercooler")

local intakeMeasurements = nil
local combustionEngine = nil

local intake_manifold_temp_c = 0
local intake_box_temp_c = 0

local heatToManifoldCoef = 0.5
local heatManifoldToEngineBayCoef = 0.0005
local heatFromIntakeAirToIntakeManifold = 1

local heatFromIntakeBoxToEngineBay = 0.005
local heatToIntakeBoxCoef = 0.005
local heatFromIntakeBoxToAir = 0.5

local function init(data, state)
    intakeMeasurements = data.intakeMeasurements
    combustionEngine = data.combustionEngine
    local ambient_temp = obj:getEnvTemperature() --[[ºK]]
    local ambient_temp_c = ambient_temp - 273.15 --[[ºK to ºC]]
    if combustionEngine.thermals ~= nil and combustionEngine.thermals.coolantTemperature > 50 then -- engine preheated?
        intake_manifold_temp_c = 60
        intake_box_temp_c = 35
    else
        intake_manifold_temp_c = ambient_temp_c
        intake_box_temp_c = ambient_temp_c
    end
    if intakeMeasurements.hasIntercooler then
        state = intercooler.init(data, state)
    end
    state = manifold.init(data, state)
    return state
end

local function update(state, dt) -- -> modifyed state
    -- intake air temperature
    local ambient_temp = obj:getEnvTemperature() --[[ºK]]
    local ambient_temp_c = ambient_temp - 273.15 --[[ºK to ºC]]
    --intakeMeasurements.IAT = ambient_temp
    if state.torqueCurveCreation then
        intakeMeasurements.IAP = 101.325 + ((state.tccTurboBoost or 0) / 14.7) * 101.325 --[[kPa]]
    else
        intakeMeasurements.IAP = 101.325 + ((electrics.values.turboBoost or 0) / 14.7) * 101.325 --[[kPa]]

        -- Note that it is assumed that the air at the intake is at ambient temperature
        intake_box_temp_c =
            intake_box_temp_c
            + (combustionEngine.thermals.coolantTemperature - intake_box_temp_c) * heatToIntakeBoxCoef * dt -- heat from engine bay
            + (ambient_temp_c - intake_box_temp_c) * heatManifoldToEngineBayCoef * (combustionEngine.thermals.debugData.engineThermalData.radiatorAirSpeed or 0) * dt -- heat to engine bay
            + (ambient_temp_c - intake_box_temp_c) * heatFromIntakeBoxToEngineBay * dt -- heat from intake air to pipe

        local IAT_c = intakeMeasurements.IAT - 273.15 --[[ºK to ºC]]
        -- print("intake_box_temp_c: " .. intake_box_temp_c)
        IAT_c = ambient_temp_c + (
            (intake_box_temp_c - ambient_temp_c) * heatFromIntakeBoxToAir
        ) --* dt
        -- print("IAT_c after: " .. IAT_c)
        local boost_factor = 1 + math.max(((electrics.values.turboBoost or 0) / 14.7) * (2 - (electrics.values.turboEfficiency or 0)), 0)
        local air_temp_after_turbo_c = math.max(IAT_c * boost_factor, IAT_c)
        --print("air_temp_after_turbo_c: " .. air_temp_after_turbo_c)

        intakeMeasurements.IAT = air_temp_after_turbo_c + 273.15 --[[ºC to ºK]]

        if intakeMeasurements.hasIntercooler then
            -- after the air has been compressed by the turbo, it goes through the intercooler
            intercooler.update(state, dt)
        end
        IAT_c = intakeMeasurements.IAT - 273.15 --[[ºK to ºC]]
        --print("IAT_c after intercooler: " .. IAT_c)
        -- then it goes through the intake manifold which can exchange heat with the engine bay and heat soak
        intake_manifold_temp_c =
            intake_manifold_temp_c
            + (combustionEngine.thermals.coolantTemperature - intake_manifold_temp_c) * heatToManifoldCoef * dt -- heat from engine bay
            + (IAT_c - intake_manifold_temp_c) * heatManifoldToEngineBayCoef * (combustionEngine.thermals.debugData.engineThermalData.radiatorAirSpeed or 0) * dt -- heat to engine bay
            + (IAT_c - intake_manifold_temp_c) * heatFromIntakeAirToIntakeManifold * dt--(state.manifold.MAF / (1000 + state.manifold.MAF) * 0.1) * dt -- heat from intake air to pipe

        -- calculate heat excanged from the intake manifold to the intake air
        IAT_c = IAT_c + (intake_manifold_temp_c - IAT_c) * heatFromIntakeAirToIntakeManifold * dt

        --heatSoak = clamp(heatSoak, 0, combustionEngine.thermals.coolantTemperature * 2/3)

        --print("intakeB: " .. string.format("%.2f", intake_box_temp_c) .. ", afterTC: " .. string.format("%.2f", air_temp_after_turbo_c) .. ", afterIC: " .. string.format("%.2f", (intakeMeasurements.IAT - 273.15)) .. ", intake manifold: " .. string.format("%.2f", intake_manifold_temp_c) .. ", IAT: " .. string.format("%.2f", IAT_c))
        --local factor = boost_factor + (1 + (combustionEngine.thermals.coolantTemperature / 90))
        --heatSoak = heatSoak 
        
        intakeMeasurements.IAT = math.max(IAT_c, ambient_temp_c) + 273.15 --[[ºC to ºK]]
    end

    -- print("turboBoost: " .. (electrics.values.turboBoost or 0))
    -- print("IAP: " .. intakeMeasurements.IAP)
    --print("ambient_temp: " .. (ambient_temp - 273.15))

    -- 1 Air filter restriction
    --TODO: add air filter restriction
    -- this should set IAT, IAP and airDensity
    -- state = air_intake_system.update(state)   

    manifold.update(state, dt)
    --return state
end

M.init = init
M.update = update
return M