local M = {}
local pq = require"physicalQuantity.physicalQuantity"
local throttle_cv = nil
local simEngine = nil --engine.lua
local combustionEngine = nil --combustionEngine.lua
local engineMeasurements = nil

local intakeMeasurements = {
  throttleSize_mm = 65 --[[mm]],
  IAT = 293.15 --[[K]],
  IAP = 101.325--[[kPa]],
  airDensity = 1.2 --[[kg/m^3]]
}

local atmToKPa = 101.325
local specific_gravity_air = 1

local function init(lEngine, lCombustionEngine, lEngineMeasurements, jbeamData)
  simEngine = lEngine
  combustionEngine = lCombustionEngine
  engineMeasurements = lEngineMeasurements
  intakeMeasurements.throttleSize_mm = jbeamData.throttle_body_diameter_mm
  intakeMeasurements.idle_throttle = jbeamData.idle_throttle

  --https://www.valteccn.com/blog/butterfly-valve-article/flow-coefficient-of-butterfly-valve-cv-value/
  local throttle_cv_points = {
    _25 = {
      { 0, 0 },
      { 10, 0.05 },
      { 20, 0.55 },
      { 30, 1.9 },
      { 40, 3 },
      { 50, 5.5 },
      { 60, 11 },
      { 70, 18 },
      { 80, 28 },
      { 90, 31 },
    },
    _40 = {
      { 0, 0 },
      { 10, 0.1 },
      { 20, 0.85 },
      { 30, 3 },
      { 40, 6.4 },
      { 50, 13 },
      { 60, 25 },
      { 70, 42.5 },
      { 80, 65 },
      { 90, 75 },
    },
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
    math.acos(1 - simEngine.state.TPS ^ (1.5)--[[^ 2]]) * 57.296--[[rad to deg]]
  ), 90.0)] + 1E-10
end

local function calculateThrottlePosition(dt, valuesOverwrite, tick)
  local throttle = simEngine.ecu.getThrottlePosition(dt, tick)
  if combustionEngine.ignitionCoef == 0 and valuesOverwrite.throttle == nil then
    throttle = 0
  end
  -- throttle = math.min(throttle, 0.3)
  throttle = valuesOverwrite.throttle ~= nil and valuesOverwrite.throttle or throttle
  simEngine.state.TPS = throttle
  simEngine.sensors.TPS = simEngine.state.TPS
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
--   local AV = pq.new(simEngine.state.RPM * rpmToAV, "av")
--   local dt = pq.new(lDt, "s")
--   local dAV = AV * dt
--   -- local tmp = crankAngle + dAV
--   if crankAngle.value >= (math.pi * 2) then
--     -- revTime = revTime + lDt
--     pq.setVal(crankAngle, 0)
--     if  tick % 500 == 0 then
--       print('AV: ' .. AV .. 'REVOLUTION!!! ' .. revTime .. ', RPM: ' .. (60.0 / revTime) .. ', reaplRPM: ' .. simEngine.state.RPM)
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


local function calculateThrottleAirflow(mapAtm)

  local intake_air_pressure_psi =  intakeMeasurements.IAP / atmToKPa * 14.7
  local t = (intakeMeasurements.IAT) * 9/5 --[[ºR]]
  local map_psi = math.min(mapAtm * 14.7, intake_air_pressure_psi)
  local cv = getThrottleCv()
  local q = 0
  if intake_air_pressure_psi >= 2 * map_psi then --critical flow
    q = cv * (816 * intake_air_pressure_psi) / math.sqrt(specific_gravity_air * t) * 0.028316847
  else -- sub critical flow
    q = 962 * cv * math.sqrt((intake_air_pressure_psi^2 - map_psi^2)/(specific_gravity_air * t)) * 0.028316847
  end
  -- q is in m^3/h
  local res = q * intakeMeasurements.airDensity --[[m^3/h to kg/h]] / 3600 --[[kg/h to kg/s]] * 1000 --[[hg/s to g/s]]
  return res
end

local massAirflowIntoIntake = 0
local massAirflowOutIntake = 0
local function calculateIntakePressureAndFlowInOutBalance(dt, tick, valuesOverwrite)
  calculateThrottlePosition(dt, valuesOverwrite, tick)

  -- Get actual intake pressure and temperature, before throttle body
  --intakeMeasurements.IAP = 1 * atmToKPa--[[kPa]]
  --intakeMeasurements.IAT = 293.15--[[K]]

  -- Calculate air density
  intakeMeasurements.airDensity = (intakeMeasurements.IAP * 1000) --[[kPa to Pa]] / (287.0500676--[[J/(Kg*K)]] * intakeMeasurements.IAT)
  --TODO: calc IAP from IAT and airDensity
  --intakeMeasurements.IAP = intakeMeasurements.airDensity * 287.0500676 * intakeMeasurements.IAT / 1000 --[[Pa to kPa]]
  
  --#region Mass Airflow into intake manifold MathWorks method
  -- Mass airflow into intake manifold
  -- mai = 2.821 - (0.05231 * throttle_angle) + (0.10299 * (throttle_angle ^ 2)) - (0.00063 * (throttle_angle ^ 3)) --[[g/s]]
  -- simEngine.state.MAP = simEngine.state.MAP / atmToKPa --[[KPa to atm]]
  -- if simEngine.state.MAP <= intake_pressure * 0.5 then
  --   mai = mai * 1
  -- elseif intake_pressure * 0.5 <= simEngine.state.MAP and simEngine.state.MAP <= intake_pressure then
  --   mai = mai * ((2 / intake_pressure) * math.sqrt(simEngine.state.MAP * intake_pressure - (simEngine.state.MAP^2)))
  -- elseif intake_pressure <= simEngine.state.MAP and simEngine.state.MAP <= 2 * intake_pressure then
  --   mai = mai * (-((2 / intake_pressure) * math.sqrt(simEngine.state.MAP * intake_pressure - (intake_pressure^2))))
  -- elseif simEngine.state.MAP > 2 * intake_pressure then
  --   mai = -mai
  -- end
  --#endregion

  -- Calculate current throttle body max airflow
  local mapAtm = simEngine.state.MAP / atmToKPa --[[KPa to atm]]
  massAirflowIntoIntake = calculateThrottleAirflow(mapAtm)

  --https://it.mathworks.com/help/simulink/slref/modeling-engine-timing-using-triggered-subsystems.html
  -- Calculate MAP derivative
  --TODO: find temperature correction factor
  local MAP_derivative = 0.41328 * (massAirflowIntoIntake - massAirflowOutIntake)
  -- local MAP_derivative = ((0.083) * intakeMeasurements.IAT / (3)) * (massAirflowIntoIntake - massAirflowOutIntake)

  -- Mass airflow into engine from intake manifold
  massAirflowOutIntake = simEngine.state.MAFTotal * 1000 --[[kg/s to g/s]]
  --(-0.366) + (0.0879 * simEngine.state.AV * simEngine.state.MAP) - (0.0337 * simEngine.state.AV * (simEngine.state.MAP * simEngine.state.MAP)) + (0.0001 * (simEngine.state.AV * simEngine.state.AV) * simEngine.state.MAP)

  simEngine.state.MAP = valuesOverwrite.map and valuesOverwrite.map or math.max(math.min(mapAtm + (MAP_derivative * dt), 0.99 * intakeMeasurements.IAP / atmToKPa), 0) * atmToKPa
  if tick % 150 == 0 then
    simEngine.sensors.MAP = simEngine.state.MAP
  end
  if TuningCheatOverwrite then
    simEngine.sensors.MAP = simEngine.state.MAP
  end
  -- Calculate engine load
  combustionEngine.instantEngineLoad = math.max(math.min(simEngine.state.MAP / atmToKPa, 1), 0)
  combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)

  -- MAF Integration
  local IMAP = simEngine.state.RPM * simEngine.state.MAP / intakeMeasurements.IAT / 2
  -- where simEngine.state.RPM is combustionEngine speed in revolutions per minute
  -- MAP (manifold absolute pressure) is measured in KPa
  -- IAT (intake air temperature) is measured in degrees Kelvin.

  --http://www.lightner.net/obd2guru/IMAP_AFcalc.html
  local air_mass_flow = (IMAP / 60) * (engineMeasurements.volumetric_efficiency or 0) *
      (engineMeasurements.displacement_cc / 1000) * (28.97--[[MM Air]]) / (8.314--[[R]])--[[g/s]] / 1000 --[[g/s to kg/s]]

  local air_mass_flow_mg_s = air_mass_flow * 1000 --[[kg/s to g/s]] * 1000 --[[g/s to mg/s]] / engineMeasurements.num_cylinders
  local mg_per_combustion = air_mass_flow_mg_s / simEngine.state.combustionsPerSecond

  simEngine.state.MAF = mg_per_combustion
  simEngine.state.MAFTotal = air_mass_flow
  if tick % 500 == 0 then
    simEngine.sensors.MAF = simEngine.state.MAF
    simEngine.sensors.MAFTotal = simEngine.state.MAFTotal
  end
  if TuningCheatOverwrite then
    simEngine.sensors.MAF = simEngine.state.MAF
    simEngine.sensors.MAFTotal = simEngine.state.MAFTotal
  end

end
local function reset()
  
end

M.init = init
M.reset = reset
M.getThrottleCv = getThrottleCv
M.calculateIntakePressureAndFlow = calculateIntakePressureAndFlowInOutBalance
return M
