local M = {}

local throttle_cv = nil
local simEngine = nil --engine.lua
local combustionEngine = nil --combustionEngine.lua
local engineMeasurements = nil

local function logistic(x, x0, k, l)
  return l / (1 + math.exp(-k * (x - x0)))
end

local function init(lEngine, lCombustionEngine, lEngineMeasurements, jbeamData)
  simEngine = lEngine
  combustionEngine = lCombustionEngine
  engineMeasurements = lEngineMeasurements
  --https://www.valteccn.com/blog/butterfly-valve-article/flow-coefficient-of-butterfly-valve-cv-value/
  local throttle_cv_points = {
    { 0, 0 },
    { 10, 0.2 },
    { 20, 8 },
    { 30, 20 },
    { 40, 37 },
    { 50, 65 },
    { 60, 98 },
    { 70, 144 },
    { 80, 204 },
    { 90, 220 },
  }
  throttle_cv = createCurve(throttle_cv_points, true)
end

local function getThrottleCv()
  return throttle_cv[math.min(math.ceil(
    math.acos(1 - simEngine.sensors.TPS) * 57.296--[[rad to deg]]
  ), 90.0)] * 0.00033
end

local function calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
  local throttle = electrics.values[combustionEngine.electricsThrottleName]
  -- if combustionEngine.outputRPM > 0 and combustionEngine.outputRPM < 700 then
  local idleThrottle = math.min(1 / ((simEngine.sensors.RPM / 600 + 1) ^ 3), 1)
  if simEngine.sensors.RPM > 600 * 2 or simEngine.sensors.RPM <= 300 then
    idleThrottle = 0
  end

  throttle = math.min(idleThrottle + throttle * (1 - idleThrottle), 1)
  -- throttle = math.min(math.max(throttle * combustionEngine.starterThrottleKillCoef * combustionEngine.ignitionCoef, 0), 1)
  -- end
  -- print(throttle)
  throttle = simEngine.ecu.throttleSmoother:getUncapped(throttle, dt)
  combustionEngine.throttle = 0

  if combustionEngine.ignitionCoef == 0 and valuesOverwrite.throttle == nil then
    throttle = 0
  end
  -- throttle = math.min(throttle, 0.3)
  throttle = valuesOverwrite.throttle ~= nil and valuesOverwrite.throttle or throttle
  simEngine.sensors.TPS = throttle

  --*combustionEngine.forcedInductionCoef--* combustionEngine.forcedInductionCoef-- * simEngine.sensors.TPS
  -- AIR

  -- local teorical_airflow_CFM = simEngine.sensors.RPM * displacement_ci / 3456
  -- local airflow_CFM = engineMeasurements.volumetric_efficiency * teorical_airflow_CFM
  local throttle_body_area = math.pi *
      ((--[[engineMeasurements.throttle_body_diameter_cm]](6 / 100) --[[cm to m]] / 2) ^ 2)
  local throttle_open_area = throttle_body_area - (throttle_body_area * math.cos((math.pi / 2) * simEngine.sensors.TPS)) -- FAKY WAKY
  -- local simulated_diameter = 2 * math.sqrt(opening / math.pi)
  -- print("opening: " .. opening .. ", diameter: " .. simulated_diameter)
  -- local simulated_diameter_in = simulated_diameter * conversions.cm_to_in
  local indicated_air_mass_flow = --[[100 *]] (
      combustionEngine.intakeAirDensityCoef + ((electrics.values.turboBoost or 0) * (simEngine.sensors.TPS <= 0 and 0 or 1) / 14.7)) *
      (simEngine.sensors.RPM * 100 / 293.15 / 2 / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])

  -- --[[
  -- 	https://www.engineersedge.com/fluid_flow/flow_of_air_in_pipes_14029.htm
  -- 	https://esenssys.com/air-velocity-flow-rate-measurement/#:~:text=Mass%20Flow%20Rate%20(%E1%B9%81)%20%3D,rate%20of%204.703%20kg%2Fs.
  -- ]]
  -- local air_speed = indicated_air_mass_flow * 0.00006 / (60 * math.pi * (simulated_diameter * 0.01/2) ^ 2)
  -- --  / combustionEngine.intakeAirDensityCoef
  -- print('air_speed: ' .. air_speed .. ', indicated_air_mass_flow: ' .. indicated_air_mass_flow)
  -- local air_speed_ft_s = air_speed * 0.911344
  -- local pressure_drop = (2 * (air_speed_ft_s ^ 2))/(25000 * simulated_diameter_in + 1e-30)
  -- print("TEST: " .. (pressure_drop * 0.0625) .. ' PSI')

  local m3_of_air = indicated_air_mass_flow / 1000

  -- TODO: fix
  if m3_of_air ~= m3_of_air then -- temp bug fix
    return 0
  end
  --/ 1.225


  -- local air_speed_m_s = (m3_of_air / (1.225 * opening))
  -- print("velocity: " .. air_speed_m_s)
  -- local air_speed_ft_s = air_speed_m_s * 0.911344

  -- local pressure_drop = logistic(m3_of_air/(engineMeasurements.throttle_body_max_flow * (1 - math.cos((math.pi / 2)* simEngine.sensors.TPS))), 2, 2, 14.7)
  -- local pressure_drop = logistic(m3_of_air / (engineMeasurements.throttle_body_max_flow * (1 - math.cos((math.pi / 2) * (simEngine.sensors.TPS ^ 0.75)))), 2, 1, 14.7)
  local intake_air_pressure = 287.058 *
      (
      1.225 *
          (combustionEngine.intakeAirDensityCoef + ((electrics.values.turboBoost or 0) * (simEngine.sensors.TPS <= 0 and 0 or 1) / 14.7)
          --[[* combustionEngine.forcedInductionCoef]])) * 293 / 1000
  if debug and tick % 50 == 0 then
    print("intake_air_pressure: " .. (intake_air_pressure * 1000 / 6894.76))
    print("intake_air_pressure: " .. (intake_air_pressure))
  end

  -- TEST
  local flow_rate = 0.75 --[[Cd]] * throttle_open_area * math.sqrt(
    1.4 --[[air heat capacity ratio]] *
    1.2041 --[[air density]] *
    intake_air_pressure *
    (2 / (1.4 + 1)) ^ ((1.4 + 1) / (1.4 - 1))
  )

  -- if debug and tick % 50 == 0 then
  --   print("flow_rate: " .. flow_rate)
  -- end
  -- local flow_mean_speed_0 = flow_rate / throttle_body_area
  -- local flow_mean_speed_1 = flow_rate / throttle_open_area
  -- local p2 = intake_air_pressure*1000 - 0.5 * 1.2041 * (flow_mean_speed_1 ^ 2 - flow_mean_speed_0 ^ 2)
  -- if debug and tick % 50 == 0 then
  --   -- print("p2: " .. p2 / 1000)
  -- end
  -- local v_cyl = engineMeasurements.displacement_cc / engineMeasurements.num_cylinders
  -- local mol_cyl_atm = intake_air_pressure--[[pa]] * (v_cyl--[[cc]] / 1000000 --[[cc to m^3]]) / (8.314--[[R]] * 293--[[K]])

  -- local tMAP = flow_rate--[[m^3/s]] / (((engineMeasurements.displacement_cc --[[cc]] / 1000000 --[[cc to m^3]] * RPM) / (2 * 8.314--[[R]] * 293--[[K]])) * engineMeasurements.volumetric_efficiency)
  -- local dp = math.min((1.5 * (m3_of_air / (engineMeasurements.throttle_body_max_flow * (throttle_flow_vs_position[math.ceil(simEngine.sensors.TPS * 100)]) / 100)) ^ 2) * 3386, 90 * 1000)
  -- if debug and tick % 50 == 0 then
  --   print('Dp: ' .. (
  --     dp
  --   ))
  --   -- print('tMAP: ' .. tMAP)
  --   -- print('flow_rate: ' .. flow_rate)
  -- end
  -- local pressure_drop = ((m3_of_air / (0.75 * throttle_open_area)) ^ 2) * (1.2041 / 2) / (6895--[[pa to psi]])
  -- local pressure_drop = ((m3_of_air / (0.75 * throttle_open_area)) ^ 2) * (1.2041 / 2) / (6895 --[[pa to psi]])
  local pressure_drop = logistic(m3_of_air / (engineMeasurements.throttle_body_max_flow * (1 - math.cos((math.pi / 2) * (simEngine.sensors.TPS)))), 4.5, 1, intake_air_pressure * 1000 / 6894.76)
  -- local pressure_drop = logistic(m3_of_air / (engineMeasurements.throttle_body_max_flow * ((simEngine.sensors.TPS ))), 4.5, 1, intake_air_pressure * 1000 / 6894.76)
  -- local flowAttenuation = (math.cos(simEngine.sensors.TPS * math.pi / 2) ^ --[[m_throttleGamma]] 2)
  -- local pressure_drop = logistic(m3_of_air / (engineMeasurements.throttle_body_max_flow * (1 - flowAttenuation)), 4.5, 1, 14.7)
  -- print(pressure_drop)
  -- print(m3_of_air .. ', ' ..simEngine.sensors.TPS)
  -- local pressure_drop = m3_of_air/(engineMeasurements.throttle_body_max_flow * (1 - math.cos(math.pi / 2* simEngine.sensors.TPS)))  *14.7
  -- local pressure_drop = m3_of_air/(engineMeasurements.throttle_body_max_flow * simEngine.sensors.TPS) *14.7

  --https://www.erpublication.org/published_paper/IJETR042360.pdf
  -- local inlet_air_speed--[[m/s]]       = (
  --     1 / (simEngine.sensors.TPS + 1e-12) * engineMeasurements.volumetric_efficiency * 4 * engineMeasurements.displacement_cc / 1000
  --         / 1000--[[cc to L]]) * (simEngine.sensors.RPM / 2 / 60) / (0.9 --[[Cd]] * math.pi * (5 / 100--[[cm to m]]) ^ 2)
  -- local volumetric_flow_rate--[[scfh]] = math.pi / 4 * (5 / 100--[[cm to m]]) ^ 2 * inlet_air_speed --[[m/s]] *
  --     35.314666721 --[[m3/h to scfh]]
  -- local dp--[[psi]]                    = (
  --     (529.47 --[[ºR]] * 1--[[(Molecular weight of gas)/(Molecular weight of air)]]) /
  --         (intake_air_pressure * 1000 / 6894.76--[[pa to PSI]])
  --     ) * (
  --     volumetric_flow_rate --[[scfh]] / (1.4 --[[Gas constant]] * 1360 * intake.getThrottleCv() * 0.75--[[Cv Valve flow coefficient]])
  --     )

  -- prev_air_vol_flow  = volumetric_flow_rate
  -- local volumetric_flow_rate--[[scfh]] = math.pi / 4 * (6/100 --[[cm to m]])^2 * inlet_air_speed--[[m/s]] * 35.314666721 --[[m3/h to scfh]]
  -- local dp--[[psi]] = (
  --                     (529.47--[[ºR]] * 1--[[(Molecular weight of gas)/(Molecular weight of air)]]) / (intake_air_pressure * 1000 / 6894.76 --[[pa to PSI]])
  --                     ) * (
  --                       volumetric_flow_rate--[[scfh]]/(1.4--[[Gas constant]] * 1360 * throttle_cv[math.min(math.ceil(
  --                         math.acos(1-simEngine.sensors.TPS) * 57.296--[[rad to deg]]
  --                       ), 90.0)]*15--[[Cv Valve flow coefficient]])
  --                     )

  -- if debug and tick % 50 == 0 then
  --   -- print("throttle_cv: " ..
  --   --   throttle_cv[math.min(math.ceil(
  --   --     math.acos(1 - simEngine.sensors.TPS) * 57.296--[[rad to deg]]
  --   --   ), 90.0)]
  --   -- )
  --   print("inlet_air_speed: " .. inlet_air_speed)
  --   print("volumetric_flow_rate: " .. volumetric_flow_rate)
  --   print("dp: " .. dp)
  -- end

  if debug and tick % 50 == 0 then
    print("m3_of_air: " ..
      m3_of_air ..
      ", pressure_drop: " ..
      pressure_drop ..
      ", throttle_open_area: " ..
      throttle_open_area
    )
  end

  --(0.1 * (air_speed_ft_s ^ 2))/(25000 * simulated_diameter_in + 1e-30)
  --pressure_drop =
  --(0.5 * 77--[[0.77]] * 1.225 * air_speed_m_s^2) / 1000 / 6894.76
  --air_speed_m_s^2 / (simulated_diameter * 0.001) / 1000 / 6894.76
  --  (0.5 * 0.77 * 1.225 * air_speed_m_s)
  if debug and tick % 50 == 0 then
    --   -- print("air_speed: " .. air_speed_m_s)
    -- print("pressure_drop: " .. pressure_drop)
    -- print("simEngine.sensors.TPS: " .. simEngine.sensors.TPS)
    -- print("combustionEngine.instantAfterFireCoef: " .. combustionEngine.instantAfterFireCoef)
    -- print the following lines every 50 debug and ticks
    -- print("combustionEngine.instantAfterFireTimer: " .. (combustionEngine.instantAfterFireTimer or 0))
    -- print("combustionEngine.slowIgnitionErrorChance: " .. combustionEngine.slowIgnitionErrorChance)
    -- print("combustionEngine.slowIgnitionErrorInterval: " .. combustionEngine.slowIgnitionErrorInterval)
    --   -- local k = 0.77
    --   -- print("pressure_drop2: " .. (0.5 * k * 1.225 * air_speed_m_s) / 1000 * 0.00014503773773)
    --   print("simulated_diameter: " .. simulated_diameter)
  end
  -- pressure_drop = (air_speed_m_s * air_speed_m_s) / (2 * opening) / 1000 / 6894.76

  -- print("pressure_drop: " .. pressure_drop)
  -- print("pressure_drop: " .. (pressure_drop * 0.0625))
  -- print(combustionEngine.forcedInductionCoef)
  -- local MAP = 100 * math.sqrt(simEngine.sensors.TPS)-- Kpa

  local MAP = valuesOverwrite.map and valuesOverwrite.map or math.max(intake_air_pressure - ((pressure_drop * 6894.76) / 1000), 0) -- Kpa
  simEngine.sensors.MAP = MAP
  -- local MAP = valuesOverwrite.map and valuesOverwrite.map or
  --     math.max(intake_air_pressure - (dp * 6.895--[[psi to kPa]]), 0) -- Kpa
  -- MAP = simEngine.ecu.mapSmoother:getUncapped(MAP, dt)
  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * MAP / IAT / 2
  if debug and tick % 50 == 0 then
    print('MAP: ' .. MAP)
  end
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.min(IMAP / intake_air_pressure, 1)
  -- combustionEngine.instantEngineLoad = math.min(IMAP / indicated_air_mass_flow, 1)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])
      if debug and tick % 50 == 0 then
        print("air_mass_flow: " .. air_mass_flow)
      end
  simEngine.sensors.MAF = air_mass_flow
  -- (grams of air) = (IMAP/60)*(Vol Eff/100)*(Eng Disp)*(MM Air)/(R)
  -- where R is 8.314 J/°K/mole,
  -- the average molecular mass of air (MM) is 28.97 g/mole. Note that in the above formula the volumetric efficiency of the combustionEngine is measured in percent and the displacement is in liters.

  -- print('Airflow (t / actual) (CFM): ' .. teorical_airflow_CFM .. ' / ' .. airflow_CFM)
  -- print('Air mass flow: ' .. air_mass_flow)

end

M.init = init
M.getThrottleCv = getThrottleCv
M.calculateIntakePressureAndFlow = calculateIntakePressureAndFlow

return M
