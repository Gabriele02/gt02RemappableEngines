local M = {}

local combustionEngine = nil

local engine = {
    ecu = require("lua.vehicle.powertrain.engine-system.ecu.ecu"),
    intake = require("lua.vehicle.powertrain.engine-system.intake.intake-system"),
    combustion = require("lua.vehicle.powertrain.engine-system.combustion.cylinders"),
    rotating_assembly = require("lua.vehicle.powertrain.engine-system.rotating-assembly.rotating-assembly"),
}


-- conversions
--TODO: switch to physicalQuantity
local conversions = {
cm_to_feet = 0.0328084,
cm_to_in = 0.393701,
cm2_to_in2 = 0.1550003,
cc_min_to_lb_h = 0.132277357,
bar_to_psi = 14.7,
inf = 1 / 0
}

local engineMeasurements = {
compression_ratio = 0,
stroke_cm = 0,
bore_cm = 0,
displacement_cc = 0,
num_cylinders = 0,

thermal_efficiency = 0,
volumetric_efficiency = 0,

}

--TODO: load from jbeam
local intakeMeasurements = {
    throttle = {
        type = "drive-by-wire", --[[drive-by-wire, cable]]
        throttleSize_mm = 40 --[[mm]],
    },
    IAT = 293.15 --[[K]],
    IAP = 101.325--[[kPa]],
    airDensity = 1.2, --[[kg/m^3]]
    --TODO: load from jbeam, create a map to use for variable length intake runners
    runners = {
        type = "fixed", --[[fixed, variable]]
        variable = {
            min_length_cm = 10,
            max_length_cm = 30,
            -- actuator = {
            --   speed_m_s = 0.5,
            -- },
        },
        fixed = {
          length_cm = 40,
        },
        diameter_cm = 3,
        cross_section_area_cm2 = 0, -- calculated
    }
}  
local fuelSystemMeasurements = {
    injectors = {
        injector_cc_min = 0,
        injector_max_mg_s = 0,
        injector_base_pressure = 0,
        injector_quality = 0,
    },
    fuel_pump = {
        pressure = 0,
        flow = 0,
    },
    fuel_pressure_regulator = {
        pressure = 0,
    },
}
-- table to store instant engine state
local state = {
    RPM = 0,--[[1/s]]
    AV = 0,--[[rad/s]]
    lambda = 0,
    torqueCurveCreation = false,
    combustionsPerSecond = 0,
    injectionType = "port",
    ignitionCoef = 0,
    manifold = {
        IAT = 0, --[[K]]
        MAF = 0,--[[mg/c]]
        MAFTotal = 0, --[[kg/s]]
        MAP = 100,--01.325,--[[kPa]]
        throttle = {
            massAirflowIntoIntake = 0,
            TPS = 0,--[[0-1]]
        },
        runners = {
            air_fuel_ratio = 0,
            massAirflowIntoCylinder = 0,
            injectors = {
                on_time_s = 0,
                fuel_mg_per_combustion = 0,
            },
            variable = { -- used only wih variable length intake runners
                target_length_cm = 0,
            },
            length = 0,
        }
    },
    combustionTorque = 0,
    torque = 0,
    requestedThrottle = 0,
    volumetric_efficiency = 0,
    thermal_efficiency = 0,
    instantEngineLoad = 0,
    engineLoad = 0,
    targetBoostPressure = 0, --[[Pa]]
}

-- Same as state but updated at slower (More realistic) intervals
local sensors = {
    TPS = 0,--[[0-1]]
    MAF = 0,--[[mg/c]]
    MAFTotal = 0, --[[kg/s]]
    MAP = 100,--01.325,--[[kPa]]
    RPM = 0,--[[1/s]]
    AV = 0,--[[rad/s]]
    lambda = 0,
}

local debugValues = {
    max_pressure_point_dATDC = 0,
}

-- local air_density = 1 -- should be based on temperature
-- local fuel_density = 1.3 -- ^^

local rpmToAV = 0.104719755

-- Air
local volumetric_efficiency_curve = nil

-- Fuel
local afr_power_curve = nil -- Times 10 to have integer indices
local fuel_burn_speed_curve = nil -- Times 10 to have integer indices
local misfire_probability = 0
local misfire_cooldown = 0
local misfire_timer = 0

local prev_data = {}

-- function to print table content
function tprint (tbl, indent)
  if not indent then indent = 0 end
  local toprint = string.rep(" ", indent) .. "{\r\n"
  indent = indent + 2 
  for k, v in pairs(tbl) do
    toprint = toprint .. string.rep(" ", indent)
    if (type(k) == "number") then
      toprint = toprint .. "[" .. k .. "] = "
    elseif (type(k) == "string") then
      toprint = toprint  .. k ..  "= "   
    end
    if (type(v) == "number") then
      toprint = toprint .. v .. ",\r\n"
    elseif (type(v) == "string") then
      toprint = toprint .. "\"" .. v .. "\",\r\n"
    elseif (type(v) == "table") then
      toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
    else
      toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
    end
  end
  toprint = toprint .. string.rep(" ", indent-2) .. "}"
  return toprint
end

function printTable(tbl)
  print(tprint(tbl))
end


function init(data)
    --  data content
    --  simEngine = data.engine
    --  engineMeasurements = data.engineMeasurements
    --  combustionEngine = data.combustionEngine
    --  jbeamData = data.jbeamData

    combustionEngine = data.combustionEngine

    data.engineMeasurements = engineMeasurements
    data.intakeMeasurements = intakeMeasurements
    data.fuelSystemMeasurements = fuelSystemMeasurements
    data.intakeMeasurements.idle_throttle = data.jbeamData.idle_throttle or 0.1
    
    print(v.config.partConfigFilename)

    jbeamData = data.jbeamData
    --thisEngine = localEngine
    engineMeasurements.compression_ratio = jbeamData.compression_ratio
  
    engineMeasurements.stroke_cm = jbeamData.stroke_cm
    engineMeasurements.bore_cm = jbeamData.bore_cm
    engineMeasurements.num_cylinders = jbeamData.num_cylinders
    engineMeasurements.displacement_cc = math.pi * (engineMeasurements.bore_cm / 2) * (engineMeasurements.bore_cm / 2) *
    engineMeasurements.stroke_cm * engineMeasurements.num_cylinders
    print("displacement_cc: " .. engineMeasurements.displacement_cc)
  
    -- fuel system
    fuelSystemMeasurements.injectors.injector_cc_min = jbeamData.fuelSystemInjectors.injector_cc_min
    fuelSystemMeasurements.injectors.injector_max_mg_s = fuelSystemMeasurements.injectors.injector_cc_min / 1.38888889 --[[cc/min to g/min @ 720kg/m^3]] / 60 --[[g/min to g/s]] * 1000 --[[g/s to mg/s]]

    fuelSystemMeasurements.injectors.injector_base_pressure = jbeamData.fuelSystemInjectors.baseFuelPressure_bar
    fuelSystemMeasurements.injectors.injector_quality = jbeamData.fuelSystemInjectors.quality    
  
    -- intake
    -- engineMeasurements.throttle_body_diameter_cm = jbeamData.throttle_body_diameter_cm
    -- engineMeasurements.throttle_body_max_flow = jbeamData.throttle_body_max_flow
  
    --INTAKE
    intakeMeasurements.runners.diameter_cm = jbeamData.intakeRunners.diameter_cm or 3
    intakeMeasurements.runners.type = jbeamData.intakeRunners.type or "fixed"
    if intakeMeasurements.runners.type == "variable" then
      intakeMeasurements.runners.variable.min_length_cm = jbeamData.intakeRunners.min_length_cm or 10
      intakeMeasurements.runners.variable.max_length_cm = jbeamData.intakeRunners.max_length_cm or 40
      print("loaded intakeMeasurements.runners.type: " .. intakeMeasurements.runners.type .. " with min length: " .. intakeMeasurements.runners.variable.min_length_cm .. "cm and max length: " .. intakeMeasurements.runners.variable.max_length_cm .. "cm and diameter: " .. intakeMeasurements.runners.diameter_cm .. "cm")
    elseif intakeMeasurements.runners.type == "fixed" then
      intakeMeasurements.runners.fixed.length_cm = jbeamData.intakeRunners.length_cm or 30
      print("loaded intakeMeasurements.runners.type: " .. intakeMeasurements.runners.type .. " with length: " .. intakeMeasurements.runners.fixed.length_cm .. "cm and diameter: " .. intakeMeasurements.runners.diameter_cm .. "cm")
    end

    intakeMeasurements.throttle.throttleSize_mm = jbeamData.intakeThrottle.diameter_mm or 40
    intakeMeasurements.throttle.type = jbeamData.intakeThrottle.type or "drive-by-wire"
    print("loaded intakeMeasurements.throttle.type: " .. intakeMeasurements.throttle.type .. " with diameter: " .. intakeMeasurements.throttle.throttleSize_mm .. "mm")

    local ve_table = tableFromHeaderTable(jbeamData.volumetric_efficiency)
    local rawBasePoints = {}
    for _, v in pairs(ve_table) do
      table.insert(rawBasePoints, { v.rpm, v.ve })
    end
    volumetric_efficiency_curve = createCurve(rawBasePoints, true)
  
    -- local tuneFle = readFile('data/tune.json')
  
    -- initialAfterfire.sustainedAfterFireCoef = thisEngine.sustainedAfterFireCoef
    -- initialAfterfire.sustainedAfterFireFuelDelay = thisEngine.sustainedAfterFireFuelDelay
    -- initialAfterfire.sustainedAfterFireTimer = thisEngine.sustainedAfterFireTimer
    -- initialAfterfire.instantAfterFireCoef = thisEngine.instantAfterFireCoef
    -- initialAfterfire.instantAfterFireFuelDelay = thisEngine.instantAfterFireFuelDelay
    -- initialAfterfire.instantAfterFireTimer = thisEngine.instantAfterFireTimer
   
    -- thisEngine.sustainedAfterFireCoef = 100
    -- thisEngine.sustainedAfterFireTimer = 100
    -- thisEngine.instantAfterFireCoef = 100
    -- thisEngine.instantAfterFireTimer = 100
    state = engine.ecu.init(data, state)
    state = engine.intake.init(data, state)
    state = engine.combustion.init(data, state)
    state = engine.rotating_assembly.init(data, state)
    return state
end

local tick = 0
function update(dt) -- -> modifyed state
    -- if combustionEngine.thermals then
    --   print(combustionEngine.thermals.coolantTemperature)
    -- end

    tick = tick + 1
    state.volumetric_efficiency = volumetric_efficiency_curve[math.floor(state.RPM)] or 0
    state.thermal_efficiency = 1 /
      (combustionEngine.invBurnEfficiencyTable[math.floor(state.instantEngineLoad * 100)] or 1)
    
    if not state.torqueCurveCreation then
      state.requestedThrottle = electrics.values[combustionEngine.electricsThrottleName]
    end

    if TuningCheatOverwrite and RpmOverwrite ~= nil and MapOverwrite ~= nil then
      state.RPM = RpmOverwrite
      state.AV = state.RPM * rpmToAV
      state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]
        state.manifold.MAP = MapOverwrite
    end
    -- 0 - ecu
    engine.ecu.update(state, dt)

    if TuningCheatOverwrite and RpmOverwrite ~= nil and MapOverwrite ~= nil then
      state.RPM = RpmOverwrite
      state.AV = state.RPM * rpmToAV
      state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]
      state.manifold.MAP = MapOverwrite
    end
    -- 1 - intake
    engine.intake.update(state, dt)
    combustionEngine.instantEngineLoad = state.instantEngineLoad
    combustionEngine.engineLoad = state.engineLoad
    
    if TuningCheatOverwrite and RpmOverwrite ~= nil and MapOverwrite ~= nil then
      state.RPM = RpmOverwrite
      state.AV = state.RPM * rpmToAV
      state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]
      state.manifold.MAP = MapOverwrite
    end
    -- 2 - combustion
    if tick % 50 == 0 then
        --printTable(state)
    end
    engine.combustion.update(state, dt)

    if TuningCheatOverwrite and RpmOverwrite ~= nil and MapOverwrite ~= nil then
      state.RPM = RpmOverwrite
      state.AV = state.RPM * rpmToAV
      state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]
      state.manifold.MAP = MapOverwrite
    end
    -- 3 - rotating assembly
    engine.rotating_assembly.update(state, dt)
    
    if TuningCheatOverwrite and RpmOverwrite ~= nil and MapOverwrite ~= nil then
      state.RPM = RpmOverwrite
      state.AV = state.RPM * rpmToAV
      state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]
      state.manifold.MAP = MapOverwrite
      combustionEngine.outputAV1 = state.AV
    end

    if tick % 50 == 0 then
      --printTable(state)
    end
    return state
end

function reset()
    -- TODO: NON VA
    state = {}
    state = engine.ecu.init(state)
    state = engine.intake.init(state)
    state = engine.combustion.init(state)
    state = engine.rotating_assembly.init(state)
    return state
end

local function updateGFX(device, dt)
  engine.ecu.updateGFX(dt)
end

M.init = init
M.update = update
M.reset = reset
M.state = state
M.setTempRevLimiter = engine.ecu.setTempRevLimiter
M.resetTempRevLimiter = engine.ecu.resetTempRevLimiter
M.get3DTableValue = engine.ecu.get3DTableValue
M.get2DTableValue = engine.ecu.get2DTableValue
M.updateGFX = updateGFX

return M