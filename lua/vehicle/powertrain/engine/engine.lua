local ecu = require "lua.vehicle.powertrain.ecu.ecu"
local intake = require"lua.vehicle.powertrain.engine.intake"

local M = {}

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
  injector_cc_min = 0,
  thermal_efficiency = 0,
  volumetric_efficiency = 0,
  throttle_body_diameter_cm = 0,
  throttle_body_max_flow = 0,
}

local state = {
  TPS = 0,--[[0-1]]
  MAF = 0,--[[kg/s]]
  MAP = 100,--01.325,--[[kPa]]
  RPM = 0,--[[1/s]]
  AV = 0,--[[rad/s]]
  lambda = 0,
}

-- Same as state but updated at slower (More realistic) intervals
local sensors = {
  TPS = 0,--[[0-1]]
  MAF = 0,--[[kg/s]]
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

--local throttle_cv = nil -- take it from intake
local rpmToAV = 0.104719755

local tick = 0
local debug = false
-- Air
local volumetric_efficiency_curve = nil

-- Fuel
local afr_power_curve = nil -- Times 10 to have integer indices
local fuel_burn_speed_curve = nil -- Times 10 to have integer indices
local misfire_probability = 0
local misfire_cooldown = 0
local misfire_timer = 0

local prev_data = {}

local thisEngine = nil
local function init(localEngine, jbeamData)
  print(v.config.partConfigFilename)

  thisEngine = localEngine
  engineMeasurements.compression_ratio = jbeamData.compression_ratio

  engineMeasurements.stroke_cm = jbeamData.stroke_cm
  engineMeasurements.bore_cm = jbeamData.bore_cm
  engineMeasurements.num_cylinders = jbeamData.num_cylinders
  engineMeasurements.displacement_cc = math.pi * (engineMeasurements.bore_cm / 2) * (engineMeasurements.bore_cm / 2) *
  engineMeasurements.stroke_cm * engineMeasurements.num_cylinders
  print("displacement_cc: " .. engineMeasurements.displacement_cc)

  engineMeasurements.injector_cc_min = jbeamData.injector_cc_min
  engineMeasurements.throttle_body_diameter_cm = jbeamData.throttle_body_diameter_cm
  engineMeasurements.throttle_body_max_flow = jbeamData.throttle_body_max_flow

  local ve_table = tableFromHeaderTable(jbeamData.volumetric_efficiency)
  local rawBasePoints = {}
  for _, v in pairs(ve_table) do
    table.insert(rawBasePoints, { v.rpm, v.ve })
  end
  volumetric_efficiency_curve = createCurve(rawBasePoints, true)

  local afr_power_curve_points = {
    { 30, 0 },
    { 40, 0 },
    { 50, 0 },
    { 60, 0.5 },
    { 90, 0.8 },
    { 115, 0.95 },
    { 122, 1 },
    { 133, 0.95 },
    { 147, 0.87 },
    { 155, 0.76 },
    { 165, 0.62 },
    { 180, 0.45 },
    { 220, 0.23 },
    { 250, 0 },
    { 260, 0 },
    { 270, 0 },
  }
  afr_power_curve = createCurve(afr_power_curve_points, true)

  local fuel_burn_speed_points = {
    { 30, 0 },
    { 40, 0 },
    { 50, 0 },
    { 60, 0.025 },
    { 70, 0.05 },
    { 80, 0.1 },
    { 95, 0.35 },
    { 102, 0.529411764705882 },
    { 117, 0.741176470588235 },
    { 132, 0.882352941176471 },
    { 147, 1 },
    { 161, 1.03529411764706 },
    { 176, 0.988235294117647 },
    { 191, 0.870588235294118 },
    { 200, 0.8 },
    { 210, 0.69 },
    { 220, 0.51 },
    { 230, 0.3 },
    { 250, 0.05 },
    { 260, 0.025 },
    { 270, 0 },
  }
  fuel_burn_speed_curve = createCurve(fuel_burn_speed_points, true)

  -- local tuneFle = readFile('data/tune.json')

  intake.init(M, localEngine, engineMeasurements, jbeamData)
  ecu.init(M, localEngine, engineMeasurements, jbeamData)
  print('ENGINE INITIALIZED')
end

local function reset()
  ecu.reset()
  intake.reset()
end

local function updateGFX(device, dt)
  ecu.updateGFX(device, dt)
end

-- local function updateGFX(dt)
local function simulateEngine(dt, valuesOverwrite, torqueCurveCreation)
  valuesOverwrite = valuesOverwrite == nil and {} or valuesOverwrite
  thisEngine.instantEngineLoad = valuesOverwrite.instantEngineLoad ~= nil and valuesOverwrite.instantEngineLoad or
      thisEngine.instantEngineLoad
  tick = tick + 1
  if tick >= 100000 then
    tick = 0
  end

  local torque = 0


  state.RPM = valuesOverwrite.RPM ~= nil and valuesOverwrite.RPM or math.abs(thisEngine.outputRPM) -- For consistency
  state.AV = state.RPM * rpmToAV
  sensors.RPM = state.RPM
  sensors.AV = state.AV

  engineMeasurements.thermal_efficiency = 1 /
      (thisEngine.invBurnEfficiencyTable[math.floor(thisEngine.instantEngineLoad * 100)] or 1)
  -- print(test_curve[RPM])
  engineMeasurements.volumetric_efficiency = volumetric_efficiency_curve[math.floor(state.RPM)] or 0
  -- engineMeasurements.volumetric_efficiency = engineMeasurements.volumetric_efficiency --* combustionEngine.intakeAirDensityCoef+ (electrics.values.turboBoost / 14.7)

  --AIR
  intake.calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)

  -- FUEL
  -- Varies with engine map
  -- print('got: ' .. get3DTableValue(ecu.maps['injector-table'], RPM, MAP, true))
  local injector_duty = ecu.getInjectorsDuty(dt)

  -- local fuelflow_cfm = injector_lb_h * engineMeasurements.num_cylinders * injector_duty * 0.000266974

  local fuel_mass_flow = ((engineMeasurements.injector_cc_min / 60--[[cc/min to cc/s]]) / 1000000--[[cc/s to m^3/s]]) * 748.9--[[m^3/s to kg/s]] * engineMeasurements.num_cylinders * injector_duty

  local air_fuel_ratio
  if fuel_mass_flow < 1e-30 or (fuel_mass_flow ~= fuel_mass_flow) then
    air_fuel_ratio = 0
  else
    -- air_fuel_ratio = air_mass_flow / fuel_mass_flow
    air_fuel_ratio = state.MAF / fuel_mass_flow
  end
  if air_fuel_ratio ~= air_fuel_ratio then
    air_fuel_ratio = 0
  end

  if not valuesOverwrite.doNotRandom and air_fuel_ratio > 17 or air_fuel_ratio < 9 then
    if air_fuel_ratio > 17 then
      misfire_probability = (air_fuel_ratio / 20) * (state.MAP / 100) * dt
      local damage_probability = (air_fuel_ratio / 25) ^ 9 * (state.MAP / 1000) * dt
      if air_fuel_ratio < 25 and math.random() < damage_probability then
        thisEngine:scaleOutputTorque(1 - (damage_probability * 100000))
        misfire_timer = 0.8 * math.random()
        thisEngine.instantAfterFireFuelDelay:push(10000000000000)
        if thisEngine.outputTorqueState < 0.2 then
          thisEngine:lockUp()
        end
      end
    end
    if air_fuel_ratio < 9 then
      misfire_probability = 4 / air_fuel_ratio * thisEngine.instantEngineLoad * dt
    end
  else
    -- misfire_cooldown = 0
    misfire_timer = 0
    misfire_probability = 0
  end

  local lambda = air_fuel_ratio / 14.7 -- AFR / Stoichyometric
  state.lambda = lambda
  if tick % 500 == 0 then --TODO: fix timing
    sensors.lambda = state.lambda
  end
  -- print('fuel_mass_flow: ' .. fuel_mass_flow)
  -- print("throttle: " .. string.format("%.2f",throttle) .. ", afr: " .. string.format("%.2f",air_fuel_ratio))
  -- print("lambda: " .. lambda)
  -- print("injector_lb_h: " .. injector_lb_h)

  -- SPARK

  local ignition_advance_deg = ecu.getSparkAdvance(dt) -- BTDC
  -- ignition_advance_deg = ignition_advance_deg - ecu.corrections.ignition_knock_retard -- ecu.safeties.soft_limiter_ignition_retard
  -- local piston_speed_ms = 2 * (engineMeasurements.stroke_cm / 100) * (RPM / 60)
  -- local flame_speed = 25
  -- local boh = 1 / 7000 * RPM
  -- dump(math.sqrt((0.01737)*(engineMeasurements.stroke_cm /2.54)*(RPM)/engineMeasurements.compression_ratio + 3))
  -- dump('iad: ' .. ignition_advance_deg)
  -- ignition_advance_deg = ignition_advance_deg + (2 * math.sqrt((0.01737)*(engineMeasurements.stroke_cm /2.54)*(RPM)/engineMeasurements.compression_ratio + 3))
  local fuel_burn_speed = math.max(fuel_burn_speed_curve[math.max(math.min(math.floor(air_fuel_ratio * 10), 270), 0)]
    or 1, 0)
  local fuel_burn_duration_deg
  local detonationFactor = 1

  local max_pressure_point_dATDC
  if fuel_burn_speed >= 0 then
    -- fuel_burn_duration_deg = ((20 * (engineMeasurements.stroke_cm / 8.2) / (((MAP / 100) ^ 0.3))) * state.RPM / 3600) / fuel_burn_speed
    -- fuel_burn_duration_deg = ((20*(engineMeasurements.stroke_cm/8.2)/((((MAP+100)/100)^0.8)))*(RPM/3600)^0.9)/ fuel_burn_speed
    -- fuel_burn_duration_deg = ((20*(engineMeasurements.stroke_cm/8.2)/((((MAP+100)/100)^0.8)))*(RPM/3600))/ fuel_burn_speed
    fuel_burn_duration_deg = ((20 * (engineMeasurements.stroke_cm / 8.2) / ((((state.MAP + 100) / 100) ^ 0.8))) *
        ((state.RPM + 1800) / 3600) ^ 0.8) / fuel_burn_speed

    -- if debug and tick % 50 == 0 then
    --   print((20 / ((engineMeasurements.volumetric_efficiency ^ 0.2) * (engine.forcedInductionCoef^0.2))))
    -- end
    -- local stroke_duration_s = 1 / (RPM * 2 / 60)
    max_pressure_point_dATDC = -ignition_advance_deg + fuel_burn_duration_deg
    -- print('ignition_advance: ' .. ignition_advance_deg)
    -- print('max_pressure_point_dATDC: ' .. max_pressure_point_dATDC)
    -- print('ignition_advance: ' .. ignition_advance_deg)
    -- print('burn duratoin degrees: ' .. fuel_burn_duration_deg)
    -- print('max_pressure_point_dATDC: ' .. max_pressure_point_dATDC)
    debugValues.max_pressure_point_dATDC = max_pressure_point_dATDC
    if max_pressure_point_dATDC < 0 then
      detonationFactor = math.min(math.max(1 - math.abs(max_pressure_point_dATDC / fuel_burn_duration_deg), 0), 1)
      -- print("KNOCK KNOCK")
      if not valuesOverwrite.doNotRandom and math.random() < math.abs(max_pressure_point_dATDC / 20) ^ 5 then
        thisEngine:lockUp()
      end
      -- if ecu.maps.options["knock-correction"] and thisEngine.ignitionCoef > 0 and max_pressure_point_dATDC < -2 then
      --   --throttle = 0
      --   -- return 0 --TODO: find a better way to do knock detection and ignition cut
      --   ecu.corrections.ignition_knock_retard = ecu.corrections.ignition_knock_retard + 5
      -- else
      --   ecu.corrections.ignition_knock_retard = math.max(0, ecu.corrections.ignition_knock_retard - 0.1)
      -- end
    else
      -- ecu.corrections.ignition_knock_retard = math.max(0, ecu.corrections.ignition_knock_retard - 0.1)
    end
    -- if debug and tick % 50 == 0 then
    --   print("Ignition knock retard: " .. ecu.corrections.ignition_knock_retard)
    -- end

    local combustion_pressure = engineMeasurements.compression_ratio * 17 * ((state.MAP / 100) ^ 2) *
        (engineMeasurements.volumetric_efficiency or 0) -- ^ 2 may give incorrect results for turbo
    if ignition_advance_deg > 0 then
      combustion_pressure = combustion_pressure + (ignition_advance_deg * 2)

      thisEngine.sustainedAfterFireCoef = prev_data.sustainedAfterFireCoef or thisEngine.sustainedAfterFireCoef
      thisEngine.sustainedAfterFireFuelDelay = prev_data.sustainedAfterFireFuelDelay or
          thisEngine.sustainedAfterFireFuelDelay
      thisEngine.sustainedAfterFireTimer = prev_data.sustainedAfterFireTimer or thisEngine.sustainedAfterFireTimer
      thisEngine.instantAfterFireCoef = prev_data.instantAfterFireCoef or thisEngine.instantAfterFireCoef
      thisEngine.instantAfterFireFuelDelay = prev_data.instantAfterFireFuelDelay or thisEngine.instantAfterFireFuelDelay
      thisEngine.instantAfterFireTimer = prev_data.instantAfterFireTimer or thisEngine.instantAfterFireTimer
      thisEngine.slowIgnitionErrorChance = prev_data.slowIgnitionErrorChance or thisEngine.slowIgnitionErrorChance
      thisEngine.slowIgnitionErrorInterval = prev_data.slowIgnitionErrorInterval or thisEngine.slowIgnitionErrorInterval
      prev_data.modified = false
    else
      combustion_pressure = combustion_pressure + (ignition_advance_deg * 4)
    end
    if prev_data.modified == false then
      prev_data.sustainedAfterFireCoef = thisEngine.sustainedAfterFireCoef
      prev_data.sustainedAfterFireFuelDelay = thisEngine.sustainedAfterFireFuelDelay
      prev_data.sustainedAfterFireTimer = thisEngine.sustainedAfterFireTimer
      prev_data.instantAfterFireCoef = thisEngine.instantAfterFireCoef
      prev_data.instantAfterFireFuelDelay = thisEngine.instantAfterFireFuelDelay
      prev_data.instantAfterFireTimer = thisEngine.instantAfterFireTimer
      prev_data.slowIgnitionErrorChance = thisEngine.slowIgnitionErrorChance
      prev_data.slowIgnitionErrorInterval = thisEngine.slowIgnitionErrorInterval
      prev_data.modified = false
    end
    if max_pressure_point_dATDC >= 30 and state.RPM > 2 * thisEngine.idleRPM and
        not (max_pressure_point_dATDC == conversions.inf or max_pressure_point_dATDC == -conversions.inf) then
      -- engine.sustainedAfterFireCoef = 100
      -- engine.sustainedAfterFireFuelDelay:push(1000)
      -- engine.sustainedAfterFireTimer = 20
      local factor = math.min(max_pressure_point_dATDC / 90, 1)
      thisEngine.instantAfterFireCoef = 100 * factor * math.random()
      thisEngine.instantAfterFireFuelDelay:push(factor * math.random())
      thisEngine.instantAfterFireTimer = factor * math.random()
      thisEngine.slowIgnitionErrorChance = factor ^ 2
      thisEngine.slowIgnitionErrorInterval = math.random(0.1, 1)
      prev_data.modified = true
    end
    
    local mean_compression_pressure = (engineMeasurements.compression_ratio + 1) / 2 -- manca VE
    local mean_exhaust_pressure = (combustion_pressure / 50 + 1) / 2
    -- local mean_exhaust_pressure = (combustion_pressure + 1) / 2
    local MEP_approx = (
        (-mean_compression_pressure * (9 * --[[Perché si lol]] (1 - detonationFactor))) * 2 +
            combustion_pressure * detonationFactor - mean_exhaust_pressure * 2) / 5 * conversions.bar_to_psi
    if debug and tick % 50 == 0 then
      print('MEP_approx: ' .. MEP_approx)
    end

    local p = MEP_approx

    -- PLANK
    local l = engineMeasurements.stroke_cm * conversions.cm_to_feet
    local radius_cm = engineMeasurements.bore_cm / 2
    local area_cm2 = math.pi * radius_cm * radius_cm
    local a = area_cm2 * conversions.cm2_to_in2

    local n = state.RPM / 2

    local k = engineMeasurements.num_cylinders

    local IHP = (p * l * a * n * k) / 33000

    local fuel_misfire = 1
    if not valuesOverwrite.doNotRandom and math.random() < misfire_probability and misfire_timer <= 0 then
      misfire_timer = 0.25 * misfire_probability / dt
      -- print("MISFIRE: " .. air_fuel_ratio .. ', misfire_probability: ' .. (misfire_probability / dt))
    end
    misfire_cooldown = misfire_cooldown - dt

    if misfire_timer > 0 then
      fuel_misfire = 0
      misfire_timer = misfire_timer - dt
    end

    local afr_power_factor = afr_power_curve[math.max(math.min(math.floor(air_fuel_ratio * 10), 270), 0)] or 0
    local SHP = IHP * engineMeasurements.thermal_efficiency * afr_power_factor -- * engine.forcedInductionCoef--* (engineMeasurements.volumetric_efficiency * MAP / 100)
    torque = (state.RPM < 100 or SHP < 0.5) and 0 or
        (math.min(((SHP * 5280 / (state.RPM + 1e-30)) * 1.3558), 10000000)) * thisEngine.outputTorqueState * fuel_misfire
    if debug and tick % 50 == 0 then
      print('state.RPM: ' ..
        state.RPM ..
        ', throttle: ' ..
        state.TPS ..
        ', SHP: ' ..
        SHP ..
        ', torque: ' ..
        torque .. ', air_fuel_ratio: ' .. air_fuel_ratio .. ', afr_power_factor: ' .. afr_power_factor)
    end
  end

  return torque
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.simulateEngine = simulateEngine

M.state = state
M.sensors = sensors
M.debugValues = debugValues
M.engineMeasurements = engineMeasurements
M.ecu = ecu
M.intake = intake
M.volumetric_efficiency_curve = volumetric_efficiency_curve

return M
