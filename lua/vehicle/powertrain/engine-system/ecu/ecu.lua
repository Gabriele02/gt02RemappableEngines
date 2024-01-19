local tunerServer = require("tunerServer/tunerServer")
local PIDController = require "lua.vehicle.powertrain.engine-system.ecu.PIDController"
local M = {}
M.SUPPORTED_MAPS_VERSION = 0.31

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384

local simEngine = nil -- engine.lua
local combustionEngine = nil -- tunableCombustionEngine.lua
local intakeMeasurements = nil
local engineMeasurements = nil
local fuelSystemMeasurements = nil

local throttleSmoother = newTemporalSmoothing(15, 10)
local mapSmoother = newTemporalSmoothing(300, 200)
local maps = nil
local corrections = {
  ignition_knock_retard = 0,
}
local tuneOutData = {
  lambda = 0,
  afr = 0,
  rpm = 0,
  load = 0,
  throttle = 0,
  ignTiming = 0,
}
local timers = {
  limiter_fuel_cut = 0
}
local safeties = {
  -- soft_rev_limiter = {
  --   RPM = 0,
  --   enabled = true,
  --   soft_limiter_ignition_retard = 0,
  -- },
  hard_rev_limiter = {
    tempRPM = 0,
    RPM = 0,
    type = 'fuel_cut'
  },
  fuel_cut = false
}

local controllers = {
  idleThrottlePID = nil
}

local closedLoop = true

local logs = {}
local isLoggingEnabled = true

local function reloadTuneFromFile()
  if not v.config or not v.config.partConfigFilename then
    guihooks.message("ERROR: no vehicle configuration loaded! Please load a configuration")
    return
  end
  local tuneFilePath = "mods/yourTunes/" .. v.config.partConfigFilename .. "/tune.json"
  local tuneFile = io.open(tuneFilePath, "r")
  if tuneFile == nil then
    local emptyTuneFile = io.open("emptyTune.json", "r")
    io.input(emptyTuneFile)

    tuneFile = io.open(tuneFilePath, "w")
    assert(tuneFile)

    io.output(tuneFile)
    io.write(io.read())
    io.close(emptyTuneFile)
    io.close(tuneFile)

    tuneFile = io.open(tuneFilePath, "r")
  end
  io.input(tuneFile)
  local tuneStr = io.read()
  io.close(tuneFile)

  print(tuneStr)
  tuneOutData.tuneFilePath = tuneFilePath
  maps = jsonDecode(tuneStr, 'tune-json-decode')

  if maps.version == nil or maps.version < M.SUPPORTED_MAPS_VERSION then
    maps = nil
    require "lua.tuneFileUpdater".updateTuneFile(tuneFilePath, M.SUPPORTED_MAPS_VERSION)
    local updatedTuneFile = io.open(tuneFilePath, "r")
    io.input(updatedTuneFile)
    local lTuneStr = io.read()
    io.close(updatedTuneFile)
    maps = jsonDecode(lTuneStr, 'tune-json-decode')
  end
  for mapName, map in pairs(maps) do
    if type(map) == "table" then
      if map.type == '3D' then 
        table.sort(map.yValues, function(a, b)
          return a < b
        end)
        table.sort(map.xValues, function(a, b)
          return a < b
        end)
      end
      if map.type == '2D' then
        table.sort(map.xValues, function(a, b)
          return a < b
        end)
      end
    end
  end
    -- Load settings from tune
  safeties.hard_rev_limiter.RPM = tonumber(maps.options['RPM-limit'].value)
  safeties.hard_rev_limiter.type = 'fuel_cut'
end

-- This function pulls a value from a 3D table given a target for X and Y coordinates.
-- It performs a 2D linear interpolation as described in: www.megamanual.com/v22manual/ve_tuner.pdf
local function get3DTableValue(map, x, y, p)
  --[[
          Q12		R1	Q22
  
          				P
  
          Q11		R2	Q21
      ]]
  -- if map is string then map = maps[map] end

  if type(map) == 'string' then
    map = maps[map]
  end

  local y_min = map.yValues[1]
  local y_max = map.yValues[#map.yValues]
  local x_min = map.xValues[1]
  local x_max = map.xValues[#map.xValues]

  for i = 1, #map.yValues - 1, 1 do
    if math.abs(tonumber(map.yValues[i]) - y) <= 0.00001 then
      y_min = tonumber(map.yValues[i])
      y_max = tonumber(map.yValues[i])
      break
    end

    if y >= tonumber(map.yValues[i]) and y < tonumber(map.yValues[i + 1]) then
      y_min = tonumber(map.yValues[i])
      y_max = tonumber(map.yValues[i + 1])
      break
    end
  end
  for i = 1, #map.xValues - 1, 1 do
    if math.abs(map.xValues[i] - x) <= 0.00001 then
      x_min = map.xValues[i]
      x_max = map.xValues[i]
      break
    end
    -- print(map.xValues[i])
    if x >= map.xValues[i] and x < map.xValues[i + 1] then
      x_min = map.xValues[i]
      x_max = map.xValues[i + 1]
      break
    end
  end
  local yMin = map.yValues[1]
  local xMin = map.xValues[1]
  local yMax = map.yValues[#map.yValues]
  local xMax = map.xValues[#map.xValues]
  

  if y >= yMax then
    y_max = yMax
    y_min = yMax
  end
  if x >= xMax then
    x_max = xMax
    x_min = xMax
  end

  if y <= yMin then
    y_max = yMin
    y_min = yMin
  end
  if x <= xMin then
    x_max = xMin
    x_min = xMin
  end

  -- if p then
  --   dump({
  --     y_min = y_min,
  --     y_max = y_max,
  --     x_min = x_min,
  --     x_max = x_max
  --   })
  -- end
  -- print(y_max)
  -- dumpToFile("Sos.map", map)
  -- print("here")
  local Q11 = map.values['' .. y_min]['' .. x_min]
  local Q12 = map.values['' .. y_max]['' .. x_min]
  local Q21 = map.values['' .. y_min]['' .. x_max]
  local Q22 = map.values['' .. y_max]['' .. x_max]

  -- if p then
  --   dump({
  --     Q11 = Q11,
  --     Q12 = Q12,
  --     Q21 = Q21,
  --     Q22 = Q22
  --   })
  -- end

  if math.abs(x_min - x_max) <= 0.00001 and math.abs(y_min - y_max) <= 0.00001 then
    return Q11 -- dovrebbero essere tutti e 4 uguali
  end
  if math.abs(x_min - x_max) <= 0.00001 then
    return (Q11 * ((y_max - y) / (y_max - y_min))) + (Q12 * ((y - y_min) / (y_max - y_min)))
  end
  if math.abs(y_min - y_max) <= 0.00001 then
    return (Q11 * ((x_max - x) / (x_max - x_min))) + (Q21 * ((x - x_min) / (x_max - x_min)))
  end
  return (
      Q11 * (x_max - x) * (y_max - y) +
          Q21 * (x - x_min) * (y_max - y) +
          Q12 * (x_max - x) * (y - y_min) +
          Q22 * (x - x_min) * (y - y_min)
      ) / (
      (x_max - x_min) * (y_max - y_min)
      )
end

local function get2DTableValue(map, x)
  local x_min = map.xValues[1]
  local x_max = map.xValues[#map.xValues]

  for i = 1, #map.xValues - 1, 1 do
    if math.abs(map.xValues[i] - x) <= 0.00001 then
      x_min = map.xValues[i]
      x_max = map.xValues[i]
      break
    end
    if x >= map.xValues[i] and x < map.xValues[i + 1] then
      x_min = map.xValues[i]
      x_max = map.xValues[i + 1]
      break
    end
  end

  local Q11 = map.values['' .. x_min]
  local Q12 = map.values['' .. x_max]

  if math.abs(x_min - x_max) <= 0.00001 then
    return Q11 -- dovrebbero essere tutti e 4 uguali
  end
  return (Q11 * ((x_max - x) / (x_max - x_min))) + (Q12 * ((x - x_min) / (x_max - x_min)))
end

local function reset()
  throttleSmoother:reset()
  tuneOutData.afr = 0
  tuneOutData.rpm = 0
  tuneOutData.throttle = 0
  tuneOutData.map = 0
  tuneOutData.max_pressure_point_dATDC = 0
  tuneOutData.lambda = 0
  tunerServer.reset()
  reloadTuneFromFile()
end

local function init(data, state)

  simEngine = data.engine
  engineMeasurements = data.engineMeasurements
  combustionEngine = data.combustionEngine
  intakeMeasurements = data.intakeMeasurements
  fuelSystemMeasurements = data.fuelSystemMeasurements
  jbeamData = data.jbeamData
  -- controllers.idleThrottlePID = PIDController.new(0.5, 0.001, 1, 0, 0, 1)
  -- controllers.idleThrottlePID = PIDController.new(0.55, 0.0152715, 0.0038279, 0, 0, 1)
  -- controllers.idleThrottlePID = PIDController.new(100, 0.5, 0, 0, 0, 1)
  
  --controllers.idleThrottlePID = PIDController.new(6.9, 0.0016, 0.69, 0, 0, 1) -- Low but stable idle, COVET
  -- controllers.idleThrottlePID = PIDController.new(25, 0.0016, 0.8, 0, 0, 1) -- COVET

  -- controllers.idleThrottlePID = PIDController.new(2000, 0, 0, 10, -1, 1) -- ETK
  controllers.idleThrottlePID = PIDController.new(0.00091, 0.000000065, 10 , 0, -1, 1) -- ETK
  table.insert(
    logs,
    {
      ignition_advance_deg = 0,
      injector_duty = 0
    }
  )
  reset()
  
  maps['after-start-enrichment'] = createCurve(
    {
      -- { -20, 3 },
      -- { -10, 2 },
      { 0, 1.9 },
      { 10, 1.9 },
      { 20, 1.75 },
      { 30, 1.65 },
      { 40, 1.55 },
      { 50, 1.35 },
      { 60, 1.2 },
      { 70, 1.1 },
      { 80, 1 },
    },
    true
  )
  return state
end

--[[
    Returns a negative value if the ignition advance needs to be decreased, a positive or 0 value otherwise
]]
local function getSparkAdvanceCorrections()
  local corr = 0

  -- Knock correction
  if maps.options["knock-correction"] and combustionEngine.ignitionCoef > 0 then
    if simEngine.sensors.knockSensor then
      corrections.ignition_knock_retard = math.min(corrections.ignition_knock_retard + 5, 30)
    else
      corrections.ignition_knock_retard = math.max(0, corrections.ignition_knock_retard - 0.1)
    end
    corr = -corrections.ignition_knock_retard
  end
  if electrics.values.tcsActive and simEngine.sensors.RPM >= 1200 then
    corr = corr - 30
  end
  --TODO: Add temperature corrections and other factors
  return corr
end

local function getSparkAdvance()
  local mapAdvance = get3DTableValue(maps['advance-table'], simEngine.sensors.RPM, simEngine.sensors.MAP) --[[ºbTDC]]

  -- Apply corrections
  local advance = mapAdvance + getSparkAdvanceCorrections()

  if isLoggingEnabled then
    --logs[#logs].ignition_advance_deg = advance -- TODO: scroll logs instead of overwriting the last value
  end

  return advance
end

local function calculateClosedLoopInjectorsDuty(dt)
  -- todo: fix
  local targetAFR = 14.7
  local target_mg_fuel = simEngine.sensors.MAF / targetAFR
  target_mg_fuel = target_mg_fuel --+ target_mg_fuel * (simEngine.state.lambda - 1)
  local injectors_on_time_s = target_mg_fuel / fuelSystemMeasurements.injectors.injector_max_mg_s * 1000 --[[s to ms]]
  --injector_duty = (rpm * ipw --[[ms]]) / 1200
  local injector_duty = injectors_on_time_s * simEngine.sensors.RPM / 1200
  print(injector_duty)
  return injector_duty --+ injector_duty * (simEngine.sensors.lambda - 1)
end

local function getInjectorsDutyCorrections(state, rawDuty)
  --TODO: Add temperature corrections, acceleration enrichment, etc...
  local afterStartEnrichment = maps['after-start-enrichment'][combustionEngine.thermals.coolantTemperature] or 1
  afterStartEnrichment = math.max(afterStartEnrichment, 1)
  
  if state.torqueCurveCreation then
    afterStartEnrichment = 1
  end

  return rawDuty * afterStartEnrichment
end

local function getInjectorsDuty(state, dt)
  if simEngine.sensors.RPM <= 20 then
    return 0
  end

  -- if ecu.safeties.soft_rev_limiter.enabled and sensors.RPM >= ecu.safeties.soft_rev_limiter.RPM then
  -- ecu.safeties.soft_limiter_ignition_retard =
  -- else
  -- ecu.safeties.soft_limiter_ignition_retard = 0
  -- end
  local revLimitRPM = safeties.hard_rev_limiter.RPM
  if safeties.hard_rev_limiter.tempRPM > 0 then
    revLimitRPM = math.min(safeties.hard_rev_limiter.RPM, safeties.hard_rev_limiter.tempRPM)
  end

  if
    safeties.hard_rev_limiter.type == 'fuel_cut'
    and timers.limiter_fuel_cut <= 0
    and simEngine.sensors.RPM >= revLimitRPM
    and revLimitRPM > 0
  then
    timers.limiter_fuel_cut = 0.05
  end
  if timers.limiter_fuel_cut > 0 then
    timers.limiter_fuel_cut = timers.limiter_fuel_cut - dt
    combustionEngine.instantEngineLoad = 0
    combustionEngine.engineLoad = combustionEngine.loadSmoother:get(combustionEngine.instantEngineLoad, dt)
    safeties.fuel_cut = true
  else
    safeties.fuel_cut = false
  end

  if safeties.fuel_cut then
    return 0
  end

  -- if simEngine.sensors.TPS <= 0.0 then
  --   return 0
  -- end

  local rawDuty = 0
  if closedLoop and not simEngine.state.torqueCurveCreation then
    rawDuty = calculateClosedLoopInjectorsDuty(dt)
  else
    rawDuty = get3DTableValue(maps['injector-table'], simEngine.sensors.RPM, simEngine.sensors.MAP, true) / 100 --[[Duty 0-1]]
  end
  -- Apply corrections
  local duty = getInjectorsDutyCorrections(state, rawDuty)

  state.manifold.runners.injectors.duty = duty
  return duty
end

local function handlePWM(state, dt)
  -- vlr
  if intakeMeasurements.runners.type == 'variable' then
    local target_length_perc = get2DTableValue(maps['vlr-table'], state.RPM) --[[%]] / 100
    state.manifold.runners.variable.target_length_cm = target_length_perc * (intakeMeasurements.runners.variable.max_length_cm - intakeMeasurements.runners.variable.min_length_cm) + intakeMeasurements.runners.variable.min_length_cm
    print( "target_length_perc: " .. target_length_perc .. ", target_length_cm:" ..state.manifold.runners.variable.target_length_cm)
  end
end

local function getBoostTarget(state, dt)
  local targetPressure = 0
  if state.RPM > 0 then
    targetPressure = get3DTableValue(maps['boost-table'], state.RPM, state.requestedThrottle * 100) --[[psi]]
  end
  return targetPressure
end

local lastIdleThrottle = 0
local function getThrottlePosition(state, dt)
  --  TODO: use throttle map
  -- if tick % 50 == 0 then
  if simEngine.state.torqueCurveCreation then
    return simEngine.state.requestedThrottle
  end

  if  combustionEngine.thermals ~= nil then
    --print (combustionEngine.thermals.coolantTemperature)
  end
  local idleRPM = combustionEngine.thermals ~= nil and (combustionEngine.thermals.coolantTemperature > 40 and  642 or 1200) or 1000
  local throttle = state.requestedThrottle --electrics.values[combustionEngine.electricsThrottleName]
  local requestedThrottle = throttle
  if TuningCheatOverwrite then
    requestedThrottle = 1
  end
  -- if combustionEngine.outputRPM > 0 and combustionEngine.outputRPM < 700 then
  local idleThrottle = (maps.options["dbw-idle-throttle"].value or 0) / 100--intakeMeasurements.idle_throttle
  if combustionEngine.starterEngagedCoef > 0 then
    idleThrottle = idleThrottle * 2
  elseif combustionEngine.thermals.coolantTemperature < 50 then
    idleThrottle = idleThrottle * 1.1
  end
  -- idleThrottle = controllers.idleThrottlePID:iterate(idleRPM * rpmToAV, simEngine.sensors.AV, dt/dt) + (combustionEngine.starterEngagedCoef * combustionEngine.starterThrottleKillCoef * 0.05 )--math.min(1 / ((simEngine.state.RPM / (750) + 1) ^ 2.75), 1)

  if requestedThrottle == 0 and combustionEngine.ignitionCoef == 1 then
    --idleThrottle = math.min(math.max(idleThrottle + controllers.idleThrottlePID:iterate_v2(1, simEngine.sensors.RPM / idleRPM --[[idleRPM, simEngine.sensors.RPM]], dt), 0), 1)-- + (combustionEngine.starterEngagedCoef * combustionEngine.starterThrottleKillCoef * 0.05 )--math.min(1 / ((simEngine.state.RPM / (750) + 1) ^ 2.75), 1)
    lastIdleThrottle = idleThrottle
  end
  

  -- if combustionEngine.ignitionCoef == 0 then
  --   controllers.idleThrottlePID:reset()
  -- end
  -- idleThrottle = math.max(math.min(idleThrottle, 1), 0)
  -- print(idleThrottle)

  -- if (simEngine.state.RPM > (idleRPM * 3/2)) and (throttle >= idleThrottle or throttle == 0) then
  --   idleThrottle = 0
  -- end
  throttle = math.min((idleThrottle ~= 0 and idleThrottle or lastIdleThrottle) + throttle * (1 - (idleThrottle ~= 0 and idleThrottle or lastIdleThrottle)), 1)
  -- throttle = math.min(throttle + idleThrottle, 1)
  -- throttle = math.min(math.max(throttle * combustionEngine.starterThrottleKillCoef * combustionEngine.ignitionCoef, 0), 1)
  -- end
  -- print(throttle)
  -- throttle = simEngine.ecu.throttleSmoother:getUncapped(throttle, dt)
  -- combustionEngine.throttle = 0
  -- if simEngine.state.RPM <= 100 then
  --   throttle = 1
  -- end

  -- local ret = math.max(math.min(idleThrottle, 99999), -99999) * dt
  -- ret = math.max(math.min(ret + simEngine.sensors.TPS, 1), 0)
  -- print(ret .. ', ' .. idleThrottle * dt

  -- local ret = 
  -- local ret_b = ret
  -- ret =
  -- print(ret_b .. ', ' .. ret .. ', ' .. idleThrottle)
  if electrics.values.tcsActive and simEngine.sensors.RPM >= 1200 then
    --throttle = throttle * 0.45
  end
  return throttle
  -- else
  --   return simEngine.sensors.TPS
  -- end
end

local function update(state, dt)
  simEngine.debugValues = {
    max_pressure_point_dATDC = 0
  }
  -- INPUT
  state.requestedThrottle = getThrottlePosition(state, dt, 0)
  handlePWM(state, dt)

  state.targetBoostPressure = getBoostTarget(state, dt) * 6894.76 --[[psi to Pa]]
  if timers.limiter_fuel_cut > 0 then
    state.targetBoostPressure = 0 
  end
  
  simEngine.sensors = {
    RPM = simEngine.state.RPM,
    MAP = simEngine.state.manifold.MAP,
    TPS = simEngine.state.manifold.throttle.TPS,
    AV = simEngine.state.AV,
    MAF = simEngine.state.manifold.MAF,
    MAFTotal = simEngine.state.manifold.MAFTotal,
    lambda = simEngine.state.lambda,
    knockSensor = simEngine.state.knockSensor,
    max_pressure_point_dATDC = simEngine.state.max_pressure_point_dATDC or 0,
  }
  
  state.ADV = getSparkAdvance()  
  local injector_duty = math.max(math.min(getInjectorsDuty(state, dt), 1), 0) * 100
  if isLoggingEnabled then
    --logs[#logs].injector_duty = injector_duty -- TODO: scroll logs instead of overwriting the last value
  end

  -- https://injector-rehab.com/knowledge-base/injector-duty-cycle/
  -- injector_duty = (rpm * ipw) / 1200
  state.manifold.runners.injectors.on_time_s = (1200 * injector_duty / simEngine.sensors.RPM) / 1000 --[[ms to s]]
  --(2 / (state.RPM / 60)) * injector_duty
  
  --TODO: get closedloop params from config
  closedLoop = simEngine.sensors.RPM < 4000 and simEngine.sensors.MAP < 85 and false
  -- OUTPUT
  tuneOutData.lambda = simEngine.sensors.lambda

  local afr = simEngine.sensors.lambda * 14.7 --NOTE: If using another fuel instead of gasoline, change this value
  tuneOutData.afr = string.format("%.2f", afr)

  tuneOutData.rpm = string.format("%.2f", simEngine.sensors.RPM)
  tuneOutData.throttle = string.format("%.2f", simEngine.sensors.TPS)
  tuneOutData.map = string.format("%.2f", simEngine.sensors.MAP)
  tuneOutData.maf_total = string.format("%.2f", simEngine.sensors.MAFTotal*1000)
  tuneOutData.maf = string.format("%.2f", simEngine.sensors.MAF)

  -- Debug
  tuneOutData.max_pressure_point_dATDC = string.format("%.2f", simEngine.sensors.max_pressure_point_dATDC)

  --TODO: use for the logs
  tuneOutData.ignTiming = string.format("%.2f", logs[#logs].ignition_advance_deg)
  tuneOutData.injDuty = string.format("%.4f", logs[#logs].injector_duty)
  tuneOutData.inj_msOn = string.format("%.2f", state.manifold.runners.injectors.on_time_s * 1000)
  tuneOutData.inj_mgPerComb = string.format("%.2f", fuelSystemMeasurements.injectors.injector_max_mg_s * state.manifold.runners.injectors.on_time_s)
  -- tunerServer.setOutData(tuneOutData)
  tunerServer.setOutData(state)

  --return state
end

local function setTempRevLimiter(device, revLimiterAV, maxOvershootAV)
  safeties.hard_rev_limiter.tempRPM = revLimiterAV * avToRPM
end

local function resetTempRevLimiter(device)
  safeties.hard_rev_limiter.tempRPM = 0
end

local function updateGFX(dt)
  tunerServer.update()
end

M.init = init
M.reset = reset
M.update = update
M.updateGFX = updateGFX
M.getSparkAdvance = getSparkAdvance
M.getInjectorsDuty = getInjectorsDuty
M.getThrottlePosition = getThrottlePosition

M.throttleSmoother = throttleSmoother
M.mapSmoother = mapSmoother

M.setTempRevLimiter = setTempRevLimiter
M.resetTempRevLimiter = resetTempRevLimiter
M.get3DTableValue = get3DTableValue
M.get2DTableValue = get2DTableValue
M.getBoostTarget = getBoostTarget

return M
