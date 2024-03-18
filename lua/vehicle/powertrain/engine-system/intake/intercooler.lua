local M = {}

local intakeMeasurements = nil
local combustionEngine = nil

local airSpecHeat = 1005 --[[J/(kg*K)]]
local intercoolerCoef = nil
local intercoolerEffectiveness = 0.5
local intercoolerArea = 0--0.18 * 0.12--0.6 * 0.3 --[[m^2]]
local function init(data, state)
    intakeMeasurements = data.intakeMeasurements
    combustionEngine = data.combustionEngine

    local width = intakeMeasurements.intercooler.width or 0.18 --[[m]]
    local height = intakeMeasurements.intercooler.height or 0.18 --[[m]]
    local length = intakeMeasurements.intercooler.length or 0.06 --[[m]]
    local airPassageSizeW = intakeMeasurements.intercooler.airPassageSizeW or 0.002 --[[m]] -- assumed to be rect for simplicity
    local airPassageSizeH = intakeMeasurements.intercooler.airPassageSizeH or 0.002 --[[m]] -- assumed to be rect for simplicity
    intercoolerArea = 2 * length * (airPassageSizeW --[[+ airPassageSizeH]]) * (width / airPassageSizeW) * (0.5 * height / airPassageSizeH) --[[m^2]]

    intercoolerCoef = intercoolerEffectiveness * intercoolerArea * 0.5

    return state
end

local function update(state, dt) -- -> modifyed state
    -- intake air temperature
    local ambient_temp = obj:getEnvTemperature() --[[ºK]]
    local ambient_temp_c = ambient_temp - 273.15 --[[ºK to ºC]]
    -- use same values as radiator
    --local airSpeed = (combustionEngine.thermals.debugData.engineThermalData.radiatorAirSpeed or 0)`
    if combustionEngine.thermals == nil or state.torqueCurveCreation then
        return
    end
    local airSpeed = (combustionEngine.thermals.debugData.engineThermalData.radiatorAirSpeed or 0)
    local airSpeedCoef = math.max(airSpeed / (15 + airSpeed), 0.1)
    
    local IAT_c = intakeMeasurements.IAT - 273.15 --[[ºK to ºC]]
    --print("IAT_c before: " .. IAT_c)

    -- todo: heat soak intercooler
    local energyChargeToAir = (IAT_c - ambient_temp_c) * intercoolerCoef * airSpeedCoef
    IAT_c = math.min(
        math.max(
            IAT_c
                + (
                    - energyChargeToAir
                ) * airSpecHeat * dt,
            ambient_temp_c
        ),
        500
    )
    intakeMeasurements.IAT = IAT_c + 273.15

    intakeMeasurements.IAP = intakeMeasurements.IAP * 0.95
    --intakeMeasurements.IAT


end

M.init = init
M.update = update
return M