local M = {}

--TODO: add intake tract and air filtering system
local manifold = require("lua.vehicle.powertrain.engine-system.intake.manifold")
local intakeMeasurements = nil

function init(data, state)
    intakeMeasurements = data.intakeMeasurements
    state = manifold.init(data, state)
    return state
end

function update(state, dt) -- -> modifyed state
    -- intake air temperature
    local ambient_temp = obj:getEnvTemperature() --[[ºK]]
    intakeMeasurements.IAT = ambient_temp
    if state.torqueCurveCreation then
        intakeMeasurements.IAP = 101.325 + ((state.tccTurboBoost or 0) / 14.7) * 101.325 --[[kPa]]
    else
        intakeMeasurements.IAP = 101.325 + ((electrics.values.turboBoost or 0) / 14.7) * 101.325 --[[kPa]]
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