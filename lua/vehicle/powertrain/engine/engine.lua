local ecu = require "lua.vehicle.powertrain.ecu.ecu"
local intake = require"lua.vehicle.powertrain.engine.intake"

local M = {}

local timing = {
  base_adv_deg = 0, -- calc

  quench_adv_deg = 22, -- 33 open chamber / 28 2 valve closed chamber w optimized quench / 22 3-4 valve w shirl and tumble
  fuel_adv_deg = 0, -- -2 87oct / -1 91-92 oct / 0 94+oct / 2 E85
  compression_ratio_adv_deg = 1, -- 2 cr < 9.0 / 1 9.1 < cr < 10.0 / 0 10.1 < cr < 11.5 / -2 cr > 11.6
  per_kpa_adv_deg = -0.3
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

  injector_cc_min = 0,
  injector_max_mg_s = 0,
  
  thermal_efficiency = 0,
  volumetric_efficiency = 0,
  
  throttle_body_diameter_cm = 0,
  throttle_body_max_flow = 0,
}

local state = {
  TPS = 0,--[[0-1]]
  MAF = 0,--[[mg/c]]
  MAFTotal = 0, --[[kg/s]]
  MAP = 100,--01.325,--[[kPa]]
  RPM = 0,--[[1/s]]
  AV = 0,--[[rad/s]]
  lambda = 0,
  torqueCurveCreation = false
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
  engineMeasurements.injector_max_mg_s = engineMeasurements.injector_cc_min / 1.38888889 --[[cc/min to g/min @ 720kg/m^3]] / 60 --[[g/min to g/s]] * 1000 --[[g/s to mg/s]]

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
local function simulateEngine(dt, valuesOverwrite, tcc)
  state.torqueCurveCreation = tcc
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
  state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]

  sensors.RPM = state.RPM
  sensors.AV = state.AV
  sensors.combustionsPerSecond = state.combustionsPerSecond

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
  local injector_duty = math.max(math.min(ecu.getInjectorsDuty(dt), 1), 0) -- * 100  
  -- https://injector-rehab.com/knowledge-base/injector-duty-cycle/+
    -- injector_duty = (rpm * ipw) / 1200
  local injectors_on_time_s = (2 / (state.RPM / 60)) * injector_duty
  local fuel_mg_per_combustion = engineMeasurements.injector_max_mg_s * injectors_on_time_s + math.random(-0.5, 0.5)
  -- add some errors
  if tick % 50 == 0 then
    print(fuel_mg_per_combustion .. ", " .. (state.MAF / fuel_mg_per_combustion))
  end
  if not valuesOverwrite.doNotRandom then
    fuel_mg_per_combustion = fuel_mg_per_combustion + (math.random(-100000, 100000) / 100000) * fuel_mg_per_combustion/100
  end
  if tick % 50 == 0 then
    print(fuel_mg_per_combustion .. ", " .. (state.MAF / fuel_mg_per_combustion))

  end
  local air_fuel_ratio
  if fuel_mg_per_combustion < 1e-30 or (fuel_mg_per_combustion ~= fuel_mg_per_combustion) then
    air_fuel_ratio = 0
  else
    -- air_fuel_ratio = air_mass_flow / fuel_mass_flow
    air_fuel_ratio = state.MAF / fuel_mg_per_combustion
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
  if TuningCheatOverwrite then
    sensors.lambda = state.lambda
  end
  -- print('fuel_mass_flow: ' .. fuel_mass_flow)
  -- print("throttle: " .. string.format("%.2f",throttle) .. ", afr: " .. string.format("%.2f",air_fuel_ratio))
  -- print("lambda: " .. lambda)
  if tick % 50 == 0 then
    print("injector_max_mg_s: " .. engineMeasurements.injector_max_mg_s .. ", DC: " .. injector_duty .. ", RPM: " .. state.RPM .. ", injectors_on_time: " .. injectors_on_time_s*1000 .. ", MAF: " .. state.MAF .. ", mg/c: " .. fuel_mg_per_combustion ..", lambda: " .. lambda )
  end
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

    --local initial_propagation_phase = --something dependent on lambda, cr, map and rpm
    --local burn_phase = --something dependent on lambda, cr, rpm, map 

    --old
    fuel_burn_duration_deg = ((20 * (engineMeasurements.stroke_cm / 8.2) / ((((state.MAP + 103) / 100) ^ 0.4))) *
        ((state.RPM + 1800) / 3600) ^ 0.8) / fuel_burn_speed

    local total_adv = (engineMeasurements.bore_cm * 2.45 / 4.000)
    total_adv = total_adv * 6.0; 
    total_adv = total_adv + timing.quench_adv_deg + timing.fuel_adv_deg + timing.compression_ratio_adv_deg;
    timing.base_adv_deg = total_adv

    fuel_burn_duration_deg = 
      (total_adv --[[math.max(timing.per_kpa_adv_deg * (state.MAP - 100), total_adv * 0.5)]])
      * math.max(((100 - (100 - state.MAP ) * (-0.1)) / 100), 0.5)
      * ((7200 - (7200 - state.RPM ) * (0.3)) / 7200)
    -- if state.RPM > 2999 then
    --   fuel_burn_duration_deg = fuel_burn_duration_deg * 
    -- end
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
      
      
    else
      -- ecu.corrections.ignition_knock_retard = math.max(0, ecu.corrections.ignition_knock_retard - 0.1)
    end
    sensors.knockSensor = max_pressure_point_dATDC < -2
    -- if debug and tick % 50 == 0 then
    --   print("Ignition knock retard: " .. ecu.corrections.ignition_knock_retard)
    -- end

    local combustion_pressure = engineMeasurements.compression_ratio * 17 * ((state.MAP / 100) ^ 2) *
        (engineMeasurements.volumetric_efficiency or 0) -- ^ 2 may give incorrect results for turbo
    if tick % 50 == 0 then
      local gasEnergyDensity_J = 46.4 * 1000000 -- [J/kg]

      local test = 0

      --print("Cp: " .. test)
    end
    
    -- if max_pressure_point_dATDC > 0 then
    --   -- if max_pressure_point_dATDC > 10 then
    --   --   combustion_pressure = combustion_pressure + (ignition_advance_deg * 2)
    --   -- else
    --   --   combustion_pressure = combustion_pressure + (ignition_advance_deg)
    --   -- end

    --   combustion_pressure = combustion_pressure + max_pressure_point_dATDC * (1 + (2 / (1 + math.exp(-(max_pressure_point_dATDC - 10)))) - (3 / (1 + math.exp(-(max_pressure_point_dATDC - 20)))))

    -- else
    --   combustion_pressure = combustion_pressure + (ignition_advance_deg * 3)
    -- end

    -- Simulate effect of combustion timing
    combustion_pressure = combustion_pressure + max_pressure_point_dATDC * (
      -2
      + 3 / (1 + math.exp(-max_pressure_point_dATDC)) -- too soon --> knock and less power
      + 2 / (1 + math.exp(-(max_pressure_point_dATDC - 10))) -- sooner than optimal: less power
      - 2 / (1 + math.exp(-(max_pressure_point_dATDC - 30))) -- just right ;)
      - 1 / (1 + math.exp(-(max_pressure_point_dATDC - 45))) -- too late: less power
    )

    if max_pressure_point_dATDC >= 30 and state.RPM > 2 * thisEngine.idleRPM and
        not (max_pressure_point_dATDC == conversions.inf or max_pressure_point_dATDC == -conversions.inf) then
      -- thisEngine.sustainedAfterFireCoef = 100
      -- thisEngine.sustainedAfterFireTimer = 20
      -- local factor = 1--math.min(max_pressure_point_dATDC / 90, 1)
      -- thisEngine.instantAfterFireCoef = 100 * factor --* math.random()
      -- -- thisEngine.instantAfterFireFuelDelay:push(factor *1000000000) -- math.random())

      -- thisEngine.instantAfterFireTimer = factor *10 --* math.random()
    else
      -- thisEngine.sustainedAfterFireCoef = initialAfterfire.sustainedAfterFireCoef
      -- thisEngine.sustainedAfterFireFuelDelay = initialAfterfire.sustainedAfterFireFuelDelay
      -- thisEngine.sustainedAfterFireTimer = initialAfterfire.sustainedAfterFireTimer
      -- thisEngine.instantAfterFireCoef = initialAfterfire.instantAfterFireCoef
      -- thisEngine.instantAfterFireFuelDelay = initialAfterfire.instantAfterFireFuelDelay
      -- thisEngine.instantAfterFireTimer = initialAfterfire.instantAfterFireTimer
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
