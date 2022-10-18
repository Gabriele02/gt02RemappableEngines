local M = {}
local pq = require"physicalQuantity.physicalQuantity"
local throttle_cv = nil
local simEngine = nil --engine.lua
local combustionEngine = nil --combustionEngine.lua
local engineMeasurements = nil

local intakeMeasurements = {
  throttleSize_mm = 65,

}

local function logistic(x, x0, k, l)
  return l / (1 + math.exp(-k * (x - x0)))
end

local function init(lEngine, lCombustionEngine, lEngineMeasurements, jbeamData)
  simEngine = lEngine
  combustionEngine = lCombustionEngine
  engineMeasurements = lEngineMeasurements
  --https://www.valteccn.com/blog/butterfly-valve-article/flow-coefficient-of-butterfly-valve-cv-value/
  local throttle_cv_points = {
    _50 = {
      { 0, 0 },
      { 10, 0.1 },
      { 20, 5 },
      { 30, 12 },
      { 40, 24 },
      { 50, 45 },
      { 60, 64 },
      { 70, 90 },
      { 80, 125 },
      { 90, 135 },
    },
    _65 = {
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
    },
    _80 = {
      { 0, 0 },
      { 10, 0.3 },
      { 20, 12 },
      { 30, 22 },
      { 40, 39 },
      { 50, 70 },
      { 60, 116 },
      { 70, 183 },
      { 80, 275 },
      { 90, 302 },
    }
  }
  throttle_cv = createCurve(throttle_cv_points['_' .. intakeMeasurements.throttleSize_mm], true)
end

local function getThrottleCv()
  return throttle_cv[math.min(math.ceil(
    math.acos(1 - simEngine.sensors.TPS) * 57.296--[[rad to deg]]
  ), 90.0)] + 1E-10
end

local function calculateThrottlePosition(dt, valuesOverwrite)
  local throttle = electrics.values[combustionEngine.electricsThrottleName]
  -- if combustionEngine.outputRPM > 0 and combustionEngine.outputRPM < 700 then
  local idleThrottle = math.min(1 / ((simEngine.sensors.RPM / (600*0.25) + 1) ^ 2), 1)
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
end

local debug = false
local function calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
  calculateThrottlePosition(dt, valuesOverwrite)

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
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]]) / 1000 --[[g/s to kg/s]]
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


-- The simulation speed is too slow to do a step by step simulation
-- It starts to become way to slow at about 6K RPM
-- The Game's simulation step is fixed so no optimization can fix this...
-- pq.addUnit("angularVelocity", "av", {  }, { "s" })
-- local crankAngle = pq.new(0, "rad")
-- local intakeStrokesEveryNDegrees = pq.new(360 * 2 / 6 * 0.017453 --[[degrees to rads]], pq.UNITS.radiant)
-- local revTime = 0
-- local function reset()
--   crankAngle = pq.new(0, "rad")
--   revTime = 0
-- end
-- local function calculateIntakePressureAndFlowDiscrete(lDt, tick, valuesOverwrite)
--   local rpmToAV = 0.104719755
--   local avToRPM = 9.549296596425384
--   local AV = pq.new(simEngine.sensors.RPM * rpmToAV, "av")
--   local dt = pq.new(lDt, "s")
--   local dAV = AV * dt
--   -- local tmp = crankAngle + dAV
--   if crankAngle.value >= (math.pi * 2) then
--     -- revTime = revTime + lDt
--     pq.setVal(crankAngle, 0)
--     if  tick % 500 == 0 then
--       print('AV: ' .. AV .. 'REVOLUTION!!! ' .. revTime .. ', RPM: ' .. (60.0 / revTime) .. ', reaplRPM: ' .. simEngine.sensors.RPM)
--     end
--     revTime = 0
--   else
--     crankAngle = crankAngle + dAV
--     revTime = revTime + lDt
--   end
--     -- revTime = revTime + lDt
--   -- else
--   -- end
--   -- print(crankAngle / math.pi * 180)
--   calculateIntakePressureAndFlow(lDt, tick, valuesOverwrite)
-- end

local atmToKPa = 101.325
local function calculateIntakePressureAndFlowOrifice(dt, tick, valuesOverwrite)
  -- if valuesOverwrite.doNotRandom then
    -- calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
    -- return
  -- end
  calculateThrottlePosition(dt, valuesOverwrite)
  -- simEngine.sensors.TPS = 1
  
  -- https://www.speed-talk.com/forum/viewtopic.php?t=43375
  local displacement = pq.new(simEngine.engineMeasurements.displacement_cc / 1000, 'l')
  local required_volume_flow = displacement * simEngine.engineMeasurements.volumetric_efficiency * 0.5 * simEngine.sensors.RPM * 60 / 1000 --[m^3/h]
  local air_density = 1 * atmToKPa / (0.287--[[kJ/kg]] * 293.15--[[K]])
  local required_mass_flow = required_volume_flow * air_density --[[ * (prev_MAP --(In kPa) / atmToKPa) * (293.15 / IAT)]]
  required_mass_flow = required_mass_flow.value --[[kg/h]]

  local throttle_body_area = math.pi * ((engineMeasurements.throttle_body_diameter_cm / 100--[[cm to m]] / 2) ^ 2)
  local throttle_open_area = throttle_body_area - (throttle_body_area * math.cos((math.pi / 2) * simEngine.sensors.TPS)) --+ 0.000033
  local throttle_open_diameter = 2 * math.sqrt(throttle_open_area / math.pi)

  --https://www3.nd.edu/~powers/ame.30332/notes.pdf 4.2.4, pag 84
  local max_mass_flow = air_density * ((2 / (1.4 + 1)) ^ (0.5 * (1.4 + 1) / (1.4 - 1))) * math.sqrt(1.4 * 0.287 * 293.15) * throttle_open_area * 3600--[[kg/s to kg/h]] -- UHM... NOT QUITE RIGHT

  --https://en.wikipedia.org/wiki/Orifice_plate
  local cd = 0.8
  local beta = throttle_open_diameter / (engineMeasurements.throttle_body_diameter_cm / 100--[[cm to m]])
  local exp_factor = 0.99 --http://nafta.wiki/display/GLOSSARY/Orifice+Plate+Expansibility+Factor+@+model
  local delta_pressure = (((required_mass_flow / 3600--[[kg/h to kg/s]]) / ((cd / math.sqrt(1 - (beta ^ 4))) * (exp_factor) * (math.pi / 4) * (throttle_open_diameter ^ 2))) ^ 2) / (2 * air_density)
  delta_pressure = delta_pressure / 1000--[[Pa to kPa]]
  local overall_pressure_drop = delta_pressure --* (1 - (beta ^ 1.9))--[[kPa]]
  if tick % 50 == 0 then
    print(overall_pressure_drop / atmToKPa * 14.7 .. " [PSI]")
  end
  simEngine.sensors.MAP = math.max(math.min(atmToKPa - overall_pressure_drop, atmToKPa), 0)

  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * simEngine.sensors.MAP / IAT / 2
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.min(simEngine.sensors.MAP / atmToKPa, 1)
  -- combustionEngine.instantEngineLoad = math.min(IMAP / indicated_air_mass_flow, 1)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  simEngine.sensors.MAF = air_mass_flow
  
  -- calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
  -- if(tick % 50 == 0) then
  --   -- print(required_mass_flow .. ', max: ' .. max_mass_flow)
  --   -- print("MAP: " .. simEngine.sensors.MAP)
  --   -- print("MAF: " .. simEngine.sensors.MAF)
  --   -- print(throttle_open_diameter)
  --   -- print(max_mass_flow)
  --   print("simEngine.sensors.MAF: " .. simEngine.sensors.MAF .. ', RPM: ' .. simEngine.sensors.RPM)
  -- end
end

local prevMAP = 0
local function calculateIntakePressureAndFlowCv(dt, tick, valuesOverwrite)
  calculateThrottlePosition(dt, valuesOverwrite)
  local cv = getThrottleCv()
  -- if tick % 50 == 0 then
  --   print(cv)
  -- end

  -- -- https://www.speed-talk.com/forum/viewtopic.php?t=43375
  local displacement = pq.new(simEngine.engineMeasurements.displacement_cc / 1000, 'l')
  local required_volume_flow = displacement * simEngine.engineMeasurements.volumetric_efficiency * 0.5 * simEngine.sensors.RPM * 60 / 1000 --[m^3/h]
  local air_density = 1 * atmToKPa / (0.287--[[kJ/kg]] * 293.15--[[K]])
  local required_mass_flow = required_volume_flow * air_density --[[ * (prev_MAP --(In kPa) / atmToKPa) * (293.15 / IAT)]]
  required_mass_flow = required_mass_flow.value --[[kg/h]]

  -- local throttle_body_area = math.pi * ((engineMeasurements.throttle_body_diameter_cm / 100--[[cm to m]] / 2) ^ 2) --[[m^2]]

  -- local mean_velocity = required_mass_flow / (air_density * throttle_body_area) --[[m/s]]

  -- local head_loss = 0.1--[[m]]
  -- local specific_weight = 12 --[[N/m^3]]
  -- local pressure_drop = head_loss * specific_weight * (mean_velocity) ^ 2 / 2 * 9.81
  

  -- https://www.fujikin.co.jp/en/support/calculator/
  -- local p1 = 0.101325 --[MPa]
  -- local gg = 1 --[pure]
  -- local t = 20 --[ºC]
  -- local mass_flow = (2070 * p1 * cv) / math.sqrt(gg * (273 + t))
  -- local pressure_drop = --[[math.sqrt]]((required_volume_flow.value * 4.402867539--[[m^3/h to gal/min]]) / (20*cv))^(1)
  -- if pressure_drop > 7 then
    -- pressure_drop = (-1 / pressure_drop + 14.7)
  -- if tick % 50 == 0 then
  --   print('bf [PSI]: ' .. pressure_drop)
  -- end
  -- pressure_drop = (-0.0001 * (pressure_drop^3)) + (0.0019 * (pressure_drop^2)) + (0.0614 * pressure_drop) + 0.0022
  -- pressure_drop = pressure_drop * 14.7
  -- if pressure_drop > 14.7 then
  --   pressure_drop = 14.7
  -- end
  -- end

  -- https://www.engineeringtoolbox.com/flow-coefficients-d_277.html
  -- Very good results, but it does not account for engine load
  local specific_gravity = 0.00103
  local specific_gravity_air = 1 --Specific Gravity of medium where air at 70º F and 14.7 psia = 1.0
  required_volume_flow = required_volume_flow
  local pressure_drop =  ((11.6^2) * (required_volume_flow.value^2) * specific_gravity) / (cv^2)
  local intake_air_pressure = atmToKPa
  local t = (20--[[C]] + 273.15) * 9/5 --[[ºR]]
  if intake_air_pressure >= 2 * simEngine.sensors.MAP then --critical flow
    local q = cv * (816 * intake_air_pressure) / math.sqrt(specific_gravity_air * t) * 0.028316847 
    if tick % 50 == 0 then
      print("c: " .. q)
    end
  else -- sub critical flow
    local q = 962 * cv * math.sqrt((intake_air_pressure^2 - simEngine.sensors.MAP^2)/(specific_gravity_air * t)) * 0.028316847
    if tick % 50 == 0 then
      print("s: " .. q)
    end
  end


  -- local q = required_volume_flow.value * 35.3147 --[[m^3/h to cu. ft/h]]
  -- local inlet_pressure = 14.7 --[[psia]]
  -- local specific_gravity_gas = 1.0
  -- local t = 60 --[ºF]
  -- pressure_drop = (q^2 * (specific_gravity_gas * (t + 460))) / (1360^2 * cv^2 * inlet_pressure)

  -- local flow_rate_l_min = required_volume_flow.value * 16.6667--[[m^3/h to L/min]]
  -- pressure_drop = (1.225 / 999) * ((0.0694 * flow_rate_l_min / cv)^2)

  -- pressure_drop = inlet_pressure - math.sqrt(inlet_pressure^2 - (specific_gravity_gas * (t + 460) * (q / (963 * cv))^2))
  if tick % 50 == 0 then
    -- print('pd [PSI]: ' .. pressure_drop)
    -- print(
    --   inlet_pressure^2 - (specific_gravity_gas * (t + 460) * (q / (963 * cv))^2)
    -- )
  end

  -- prevMAP = simEngine.sensors.MAP
  simEngine.sensors.MAP = math.max(math.min(14.7 - pressure_drop, 14.7), 0) / 14.7 * atmToKPa

  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * simEngine.sensors.MAP / IAT / 2
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.min(simEngine.sensors.MAP / atmToKPa, 1)
  -- combustionEngine.instantEngineLoad = math.min(IMAP / indicated_air_mass_flow, 1)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  simEngine.sensors.MAF = air_mass_flow

  -- calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
end
local function calculateIntakePressureAndFlowPipe(dt, tick, valuesOverwrite)
  calculateThrottlePosition(dt, valuesOverwrite)

  -- https://www.speed-talk.com/forum/viewtopic.php?t=43375
  local displacement = pq.new(simEngine.engineMeasurements.displacement_cc / 1000, 'l')
  local required_volume_flow = displacement * simEngine.engineMeasurements.volumetric_efficiency * 0.5 * simEngine.sensors.RPM * 60 / 1000 --[m^3/h]
  local air_density = 1 * atmToKPa / (0.287--[[kJ/kg]] * 293.15--[[K]])
  local required_mass_flow = required_volume_flow * air_density --[[ * (prev_MAP --(In kPa) / atmToKPa) * (293.15 / IAT)]]
  required_mass_flow = required_mass_flow.value --[[kg/h]]

  local throttle_body_area = math.pi * ((engineMeasurements.throttle_body_diameter_cm / 100--[[cm to m]] / 2) ^ 2)
  local throttle_open_area = throttle_body_area - (throttle_body_area * math.cos((math.pi / 2) * simEngine.sensors.TPS)) + 0.000033
  -- local throttle_open_diameter = 2 * math.sqrt(throttle_open_area / math.pi)
  if simEngine.sensors.MAF <= 0.01 then
    simEngine.sensors.MAF = 0.01
  end
  local air_velocity = (simEngine.sensors.MAF * 3600--[[kg/s to kg/h]] / air_density)  / throttle_body_area--[[m/s]]
  -- if air_velocity <= 0.01 then
  --   air_velocity = 100
  -- end
  local throttle_max_flow = math.pi * air_velocity * throttle_open_area--[[m^3/h]]
  -- throttle_max_flow = 5000
  local pressure_drop = math.min(required_volume_flow.value / throttle_max_flow, 14.5)
  if tick % 50 == 0 then
    print("throttle_open_area: " .. throttle_open_area .. ", pressure_drop: " .. pressure_drop)
    -- print(air_velocity)
    -- print(math.pi * air_velocity * throttle_open_area)
  end
  simEngine.sensors.MAP = math.max(math.min(14.7 - pressure_drop, 14.7), 0) / 14.7 * atmToKPa
  
  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * simEngine.sensors.MAP / IAT / 2
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.min(simEngine.sensors.MAP / atmToKPa, 1)
  -- combustionEngine.instantEngineLoad = math.min(IMAP / indicated_air_mass_flow, 1)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  simEngine.sensors.MAF = air_mass_flow

end

--https://patents.google.com/patent/US9945313B2/
local function calculateIntakePressureAndFlowUS9945313B2(dt, tick, valuesOverwrite)
  if valuesOverwrite ~= nil and valuesOverwrite.warmup and valuesOverwrite.warmupCycleNum <= 10  then
    prev_mcylf = 1 / 1000
    simEngine.sensors.MAF = prev_mcylf * simEngine.engineMeasurements.num_cylinders
  end
  calculateThrottlePosition(dt, valuesOverwrite)

  -- https://www.speed-talk.com/forum/viewtopic.php?t=43375
  local displacement = pq.new(simEngine.engineMeasurements.displacement_cc / 1000, 'l')
  local required_volume_flow = displacement * simEngine.engineMeasurements.volumetric_efficiency * 0.5 * simEngine.sensors.RPM * 60 / 1000 --[m^3/h]
  local air_density = 1 * atmToKPa / (0.287--[[kJ/kg]] * 293.15--[[K]])
  local required_mass_flow = required_volume_flow * air_density --[[ * (prev_MAP --(In kPa) / atmToKPa) * (293.15 / IAT)]]
  required_mass_flow = required_mass_flow.value --[[kg/h]]

  local throttle_body_area = math.pi * ((engineMeasurements.throttle_body_diameter_cm / 100--[[cm to m]] / 2) ^ 2)
  local throttle_open_area = throttle_body_area - (throttle_body_area * math.cos((math.pi / 2) * simEngine.sensors.TPS)) + 0.000033
  -- local throttle_open_diameter = 2 * math.sqrt(throttle_open_area / math.pi)

  local MAC = simEngine.sensors.MAF / 1000--[[kg/s to g/s]] / simEngine.engineMeasurements.num_cylinders * simEngine.engineMeasurements.volumetric_efficiency

  -- MAF Integration
  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * simEngine.sensors.MAP / IAT / 2
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.min(simEngine.sensors.MAP / atmToKPa, 1)
  -- combustionEngine.instantEngineLoad = math.min(IMAP / indicated_air_mass_flow, 1)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  simEngine.sensors.MAF = air_mass_flow
  -- calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
end

--https://help.emtronaustralia.com.au/emtune/ThrottleMassFlow.html
local function calculateIntakePressureAndFlowTMS(dt, tick, valuesOverwrite)
  if valuesOverwrite ~= nil and valuesOverwrite.warmup and valuesOverwrite.warmupCycleNum <= 1  then
    -- prev_mcylf = 1 / 1000
    simEngine.sensors.MAF = 0.001
    print("a")
  end
  calculateThrottlePosition(dt, valuesOverwrite)

  -- https://www.speed-talk.com/forum/viewtopic.php?t=43375
  local displacement = pq.new(simEngine.engineMeasurements.displacement_cc / 1000, 'l')
  local required_volume_flow = displacement * simEngine.engineMeasurements.volumetric_efficiency * 0.5 * simEngine.sensors.RPM * 60 / 1000 --[m^3/h]
  local air_density = 1 * atmToKPa / (0.287--[[kJ/kg]] * 293.15--[[K]])
  local required_mass_flow = required_volume_flow * air_density --[[ * (prev_MAP --(In kPa) / atmToKPa) * (293.15 / IAT)]]
  required_mass_flow = required_mass_flow.value --[[kg/h]]

  local throttle_body_area = math.pi * ((engineMeasurements.throttle_body_diameter_cm / 100--[[cm to m]] / 2) ^ 2)
  local throttle_open_area = throttle_body_area - (throttle_body_area * math.cos((math.pi / 2) * simEngine.sensors.TPS))-- + 0.000033
  -- local throttle_open_diameter = 2 * math.sqrt(throttle_open_area / math.pi)

  --local tms--[[g/s]] = ( atmToKPa /  simEngine.sensors.MAP)  * throttle_open_area --*  Modelled throttle body fluid dynamics equation

  -- local pa = throttle_open_area * atmToKPa / (simEngine.sensors.MAF * 1000--[[kg/s to g/s]])
  -- local pa = simEngine.sensors.TPS*100 * atmToKPa / (simEngine.sensors.MAF * 1000--[[kg/s to g/s]])
  local pa = math.sqrt(throttle_open_area / throttle_body_area) * atmToKPa 
  -- if tick % 50 == 0 then
    -- print("tps: " .. simEngine.sensors.TPS .. ", pa: " .. pa)
  -- end
  simEngine.sensors.MAP = pa

  -- MAF Integration
  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * simEngine.sensors.MAP / IAT / 2
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.min(simEngine.sensors.MAP / atmToKPa, 1)
  -- combustionEngine.instantEngineLoad = math.min(IMAP / indicated_air_mass_flow, 1)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  simEngine.sensors.MAF = air_mass_flow
  -- print("simEngine.sensors.MAF: " .. simEngine.sensors.MAF)
  -- calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
end

--https://patents.google.com/patent/US7905135B2/en
local pthrup_1 = 0
local function calculateIntakePressureAndFlowUS7905135B2_gin(dt, tick, valuesOverwrite)
  if valuesOverwrite ~= nil and valuesOverwrite.warmup and valuesOverwrite.warmupCycleNum <= 1  then
    -- prev_mcylf = 1 / 1000
    simEngine.sensors.MAF = 0.001
    print("a")
  end
  calculateThrottlePosition(dt, valuesOverwrite)

  -- https://www.speed-talk.com/forum/viewtopic.php?t=43375
  local displacement = pq.new(simEngine.engineMeasurements.displacement_cc / 1000, 'l')
  local required_volume_flow = displacement * simEngine.engineMeasurements.volumetric_efficiency * 0.5 * simEngine.sensors.RPM * 60 / 1000 --[m^3/h]
  local air_density = 1 * atmToKPa / (0.287--[[kJ/kg]] * 293.15--[[K]])
  local required_mass_flow = required_volume_flow * air_density --[[ * (prev_MAP --(In kPa) / atmToKPa) * (293.15 / IAT)]]
  required_mass_flow = required_mass_flow.value --[[kg/h]]

  local throttle_body_area = math.pi * ((engineMeasurements.throttle_body_diameter_cm / 100--[[cm to m]] / 2) ^ 2)
  local throttle_open_area = throttle_body_area - (throttle_body_area * (1 - math.cos((math.pi / 2) * simEngine.sensors.TPS)^2))-- + 0.000033

  local mu = 1 -- flow coefficient
  local intake_pressure = atmToKPa
  local R = 8.31415
  local T = 273.15 + 20
  local gin = mu * throttle_open_area * (intake_pressure / math.sqrt(R * T)) * f(simEngine.sensors.MAP / intake_pressure) --[[kg/s]]
  local f_ = gin / (mu * throttle_open_area / math.sqrt(R*T) * pthrup_1)

  -- MAF Integration
  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * simEngine.sensors.MAP / IAT / 2
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.min(simEngine.sensors.MAP / atmToKPa, 1)
  -- combustionEngine.instantEngineLoad = math.min(IMAP / indicated_air_mass_flow, 1)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  simEngine.sensors.MAF = air_mass_flow
  -- print("simEngine.sensors.MAF: " .. simEngine.sensors.MAF)
  -- calculateIntakePressureAndFlow(dt, tick, valuesOverwrite)
end

local function  calculateThrottleAirflow()
  -- local flow = 0
  -- -- https://www.fujikin.co.jp/en/support/calculator/
  -- local t = 20 --[[ºC]]
  -- local cv = getThrottleCv()
  -- -- print(cv)

  -- local air_density = 1
  -- local intake_pressure = atmToKPa / 1000
  -- local map = simEngine.sensors.MAP / 1000
  -- local gg = 1
  -- if simEngine.sensors.MAP > intake_pressure * 0.5 then
  --   flow = (4140 * cv) / (math.sqrt((gg * (273.15 + t)) / ((intake_pressure - map) * map))) --[[m^3/h (normal)]]
  -- else
  --   flow = (2070 * intake_pressure * cv) / (gg * (273.15 + 20))
  -- end
  -- -- print(flow)
  -- local mass_flow = flow * 1.225 --[[m^3/h to kg/h]]

  -- return mass_flow / 3600 --[[kg/s]] * 1000
  local intake_air_pressure = atmToKPa
  local intake_air_pressure_psi =  intake_air_pressure / atmToKPa * 14.7
  local air_density = intake_air_pressure_psi * atmToKPa / (0.287--[[kJ/kg]] * 293.15--[[K]])
  local t = (20--[[C]] + 273.15) * 9/5 --[[ºR]]
  local map = math.min(simEngine.sensors.MAP * 14.7, intake_air_pressure_psi)
  local specific_gravity_air = 1
  local cv = getThrottleCv()
  local q = 0
  if intake_air_pressure_psi >= 2 * map then --critical flow
    q = cv * (816 * intake_air_pressure_psi) / math.sqrt(specific_gravity_air * t) * 0.028316847
    -- print("c: " .. q)
  else -- sub critical flow
    q = 962 * cv * math.sqrt((intake_air_pressure_psi^2 - map^2)/(specific_gravity_air * t)) * 0.028316847
    -- print("s: " .. q)
  end
  -- q is in m^3/h
  local res = q * 1.225 --[[m^3/h to kg/h]] / 3600 --[[kg/h to kg/s]] * 1000 --[[hg/s to g/s]]
  print(res)
  return res
end

local mai = 0
local mao = 0
local function calculateIntakePressureAndFlowInOutBalance(dt, tick, valuesOverwrite)
  calculateThrottlePosition(dt, valuesOverwrite)

  local intake_pressure = 1 --* atmToKPa--[[atm]]

  -- https://www.speed-talk.com/forum/viewtopic.php?t=43375

  -- Mass airflow into intake manifold
  -- mai = 2.821 - (0.05231 * throttle_angle) + (0.10299 * (throttle_angle ^ 2)) - (0.00063 * (throttle_angle ^ 3)) --[[g/s]]
  -- simEngine.sensors.MAP = simEngine.sensors.MAP / atmToKPa --[[KPa to atm]]
  -- if simEngine.sensors.MAP <= intake_pressure * 0.5 then
  --   mai = mai * 1
  -- elseif intake_pressure * 0.5 <= simEngine.sensors.MAP and simEngine.sensors.MAP <= intake_pressure then
  --   mai = mai * ((2 / intake_pressure) * math.sqrt(simEngine.sensors.MAP * intake_pressure - (simEngine.sensors.MAP^2)))
  -- elseif intake_pressure <= simEngine.sensors.MAP and simEngine.sensors.MAP <= 2 * intake_pressure then
  --   mai = mai * (-((2 / intake_pressure) * math.sqrt(simEngine.sensors.MAP * intake_pressure - (intake_pressure^2))))
  -- elseif simEngine.sensors.MAP > 2 * intake_pressure then
  --   mai = -mai
  -- end
  
  mai = calculateThrottleAirflow()

  --https://it.mathworks.com/help/simulink/slref/modeling-engine-timing-using-triggered-subsystems.html
  -- map
  local R = 8.31446261815324 --[[Quello che è]]
  local T = 293 --[[K]]
  local Vm = 0.003 --[[m^3]]
  local dotpm = 0.41328 * (mai - mao)

  -- Mass airflow into engine from intake manifold
  mao = simEngine.sensors.MAF * 1000 --[[kg/s to g/s]] --(-0.366) + (0.0879 * simEngine.sensors.AV * simEngine.sensors.MAP) - (0.0337 * simEngine.sensors.AV * (simEngine.sensors.MAP * simEngine.sensors.MAP)) + (0.0001 * (simEngine.sensors.AV * simEngine.sensors.AV) * simEngine.sensors.MAP)

  simEngine.sensors.MAP = math.max(math.min(simEngine.sensors.MAP + (dotpm * dt), 0.99 * intake_pressure), 0)
  simEngine.sensors.MAP = simEngine.sensors.MAP * atmToKPa --[[atm to KPa]]

  -- MAF Integration
  local IAT = 293.15 -- Kelvin
  local IMAP = simEngine.sensors.RPM * simEngine.sensors.MAP / IAT / 2
  -- where simEngine.sensors.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  combustionEngine.instantEngineLoad = math.max(math.min(simEngine.sensors.MAP / atmToKPa, 1), 0)

  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)


  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  simEngine.sensors.MAF = air_mass_flow

end
local function reset()
  
end

M.init = init
M.reset = reset
M.getThrottleCv = getThrottleCv
-- M.calculateIntakePressureAndFlow = calculateIntakePressureAndFlow
M.calculateIntakePressureAndFlow = calculateIntakePressureAndFlowInOutBalance


return M
