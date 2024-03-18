local tunerServer = require("tunerServer/tunerServer")
local PIDController = require "lua.vehicle.powertrain.engine-system.ecu.PIDController"
local flatdb = require("lua.libs.ext.flatdb.flatdb")

local M = {}
M.SUPPORTED_MAPS_VERSION = 0.4
M.TUNES_DB_LOCATION = "mods/yourTunes/db/"

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

local db = flatdb(M.TUNES_DB_LOCATION)

-- UTILS --
-- This function pulls a value from a 3D table given a target for X and Y coordinates.
-- It performs a 2D linear interpolation as described in: www.megamanual.com/v22manual/ve_tuner.pdf
local function get3DTableValue(map, x, y, nearestCellOnly)
  --[[
          Q12		R1	Q22
  
          				P
  
          Q11		R2	Q21
      ]]
  -- if map is string then map = maps[map] end
  if maps == nil then
    return 0
  end
  if type(map) == 'string' then
    map = maps[map]
  end

  local y_min = tonumber(map.yValues[1])
  local y_max = tonumber(map.yValues[#map.yValues])
  local x_min = tonumber(map.xValues[1])
  local x_max = tonumber(map.xValues[#map.xValues])

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
      x_min = tonumber(map.xValues[i])
      x_max = tonumber(map.xValues[i])
      break
    end
    -- print(map.xValues[i])
    if x >= map.xValues[i] and x < map.xValues[i + 1] then
      x_min = tonumber(map.xValues[i])
      x_max = tonumber(map.xValues[i + 1])
      break
    end
  end
  local yMin = tonumber(map.yValues[1])
  local xMin = tonumber(map.xValues[1])
  local yMax = tonumber(map.yValues[#map.yValues])
  local xMax = tonumber(map.xValues[#map.xValues])

  if nearestCellOnly then
    local x_diff = math.abs(x - x_min) < math.abs(x - x_max) and x_min or x_max
    local y_diff = math.abs(y - y_min) < math.abs(y - y_max) and y_min or y_max
    return tonumber(map.values['' .. y_diff]['' .. x_diff])
  end

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
  local Q11 = tonumber(map.values['' .. y_min]['' .. x_min])
  local Q12 = tonumber(map.values['' .. y_max]['' .. x_min])
  local Q21 = tonumber(map.values['' .. y_min]['' .. x_max])
  local Q22 = tonumber(map.values['' .. y_max]['' .. x_max])

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

local function set3DTableValue(map, x, y, newValue)
  if map == nil then
    return
  end
  local y_min = tonumber(map.yValues[1])
  local y_max = tonumber(map.yValues[#map.yValues])
  local x_min = tonumber(map.xValues[1])
  local x_max = tonumber(map.xValues[#map.xValues])

  for i = 1, #map.yValues - 1, 1 do
    if math.abs(map.yValues[i] - y) <= 0.00001 then
      y_min = tonumber(map.yValues[i])
      y_max = tonumber(map.yValues[i])
      break
    end
    if y >= map.yValues[i] and y < map.yValues[i + 1] then
      y_min = tonumber(map.yValues[i])
      y_max = tonumber(map.yValues[i + 1])
      break
    end
  end
  for i = 1, #map.xValues - 1, 1 do
    if math.abs(map.xValues[i] - x) <= 0.00001 then
      x_min = tonumber(map.xValues[i])
      x_max = tonumber(map.xValues[i])
      break
    end
    if x >= map.xValues[i] and x < map.xValues[i + 1] then
      x_min = tonumber(map.xValues[i])
      x_max = tonumber(map.xValues[i + 1])
      break
    end
  end
  -- set only the value with nearest x and y
  local selectedX = math.abs(x - x_min) < math.abs(x - x_max) and x_min or x_max
  local selectedY = math.abs(y - y_min) < math.abs(y - y_max) and y_min or y_max
  map.values['' .. selectedY]['' .. selectedX] = newValue
  return newValue
end

local function get2DTableValue(map, x)
  if map == nil then
    return 0
  end
  local x_min = tonumber(map.xValues[1])
  local x_max = tonumber(map.xValues[#map.xValues])

  for i = 1, #map.xValues - 1, 1 do
    if math.abs(map.xValues[i] - x) <= 0.00001 then
      x_min = tonumber(map.xValues[i])
      x_max = tonumber(map.xValues[i])
      break
    end
    if x >= map.xValues[i] and x < map.xValues[i + 1] then
      x_min = tonumber(map.xValues[i])
      x_max = tonumber(map.xValues[i + 1])
      break
    end
  end

  local Q11 = tonumber(map.values['' .. x_min])
  local Q12 = tonumber(map.values['' .. x_max])

  if math.abs(x_min - x_max) <= 0.00001 then
    return tonumber(Q11) -- dovrebbero essere tutti e 4 uguali
  end
  return (Q11 * ((x_max - x) / (x_max - x_min))) + (Q12 * ((x - x_min) / (x_max - x_min)))
end

local function getOptionValue(optionName)
  if optionName == nil or optionName == "" then
    return 0
  end
  return tonumber(maps.options[optionName].value)
end

local function getTuneFileKey()
  return v.config.partConfigFilename
end
-- END UTILS --

local function reloadTuneFromFile()
  if not v.config or not v.config.partConfigFilename then
    guihooks.message("ERROR: no vehicle configuration loaded! Please load a configuration")
    return
  end

  local tuneFileKey = getTuneFileKey()
  if not db.tunes then
    db.tunes = {}
  end
  tunerServer.setDB(db)
  print("loading tune file: " .. tuneFileKey)
  local tunes = deepcopy(db.tunes)
  local updated = false
  local updater = require "lua.tuneFileUpdater"
  for tuneKey, tune in pairs(tunes) do
    -- check if tunekey ends with _backup
    if string.sub(tuneKey, -7) ~= "_backup" then
      if tune.version == nil or tune.version < M.SUPPORTED_MAPS_VERSION then
        local newTune = updater.updateTuneFile(db, tuneKey, M.SUPPORTED_MAPS_VERSION)
        print("Updated tune file: " .. tuneKey .. " to version " .. newTune.version)
        db.tunes[tuneKey] = newTune
        updated = true
      end
    end
  end
  if updated then
    db:save()
  end

  maps = db.tunes[tuneFileKey]
  if maps == nil then
    -- load from old file and save to db
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
    local oldTune = jsonDecode(tuneStr, 'tune-json-decode')
    db.tunes[tuneFileKey] = oldTune
    db:save()
    reloadTuneFromFile() -- load fdrom dbn and proceed as normal
    return
  end
  tunerServer.setTuneFileKey(tuneFileKey)

  if maps == nil then
    guihooks.message("ERROR: no tune file loaded! Please load a tune file")
    return
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
  safeties.hard_rev_limiter.RPM = getOptionValue('RPM-limit')
  safeties.hard_rev_limiter.type = 'fuel_cut'
end

local function reset()
  throttleSmoother:reset()
  tunerServer.reset()
  if maps ~= nil then -- no maps loaded yet
    -- save knock map to db
    local tuneFileKey = getTuneFileKey()
    db.tunes[tuneFileKey]['knock-autoadaptation-table'] = maps['knock-autoadaptation-table']
    print("saving knock map to db")
    db:save()
  end
  reloadTuneFromFile()
end

local function init(data, state)
  
  simEngine = data.engine
  engineMeasurements = data.engineMeasurements
  combustionEngine = data.combustionEngine
  intakeMeasurements = data.intakeMeasurements
  fuelSystemMeasurements = data.fuelSystemMeasurements
  local jbeamData = data.jbeamData
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
  return state
end

--[[
    Returns a negative value if the ignition advance needs to be decreased, a positive or 0 value otherwise
]]
local function getSparkAdvanceCorrections()
  local corr = 0

  -- Knock correction
  if maps.options["knock-correction"] and combustionEngine.ignitionCoef > 0 then
    if simEngine.readings.knockSensor then
      --corrections.ignition_knock_retard = math.min(corrections.ignition_knock_retard + 5, 30)
    else
      corrections.ignition_knock_retard = math.max(0, corrections.ignition_knock_retard - 0.1)
    end
    corr = corr - corrections.ignition_knock_retard
  end
  if electrics.values.tcsActive and simEngine.readings.RPM >= 1200 then
    corr = corr - 30
  end

  local IATCorrection = get2DTableValue(maps['iat-timing-compensation-table'], simEngine.state.manifold.IAT - 273.15 --[[K To C]])

  corr = corr + IATCorrection

  return corr
end

local function getSparkAdvance()
  local mapAdvance = get3DTableValue(maps['advance-table'], simEngine.readings.RPM, simEngine.readings.MAP) --[[ºbTDC]]

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
  local target_mg_fuel = simEngine.readings.MAF / targetAFR
  target_mg_fuel = target_mg_fuel --+ target_mg_fuel * (simEngine.state.lambda - 1)
  local injectors_on_time_s = target_mg_fuel / fuelSystemMeasurements.injectors.injector_max_mg_s * 1000 --[[s to ms]]
  --injector_duty = (rpm * ipw --[[ms]]) / 1200
  local injector_duty = injectors_on_time_s * simEngine.readings.RPM / 1200
  print(injector_duty)
  return injector_duty --+ injector_duty * (simEngine.readings.lambda - 1)
end
local lastTPS = 0
local ae_timer = 0
local aeSmoother = newLinearSmoothing(1 / 2000, 0.5, 0.5)--newTemporalSmoothing(0.5, 0.5)
local test = createCurve({
  {   0,  1 },
  {  400, 1.02 },
  {  600, 1.05 },
  { 1000, 1.07 },
  { 1500, 1.1  },
  { 2000, 1.12 },
  { 3000, 1.15 },
  { 4000, 1.2  },
  { 5000, 1.25 },
  { 8000, 1.3  },
  { 20000, 1.3  },
}, true)
local frozenTPSdot = 0
local function getInjectorsDutyCorrections(sensors, rawDuty, dt)
  if sensors.torqueCurveCreation then
    return rawDuty
  end

  local afterStartEnrichment = get2DTableValue(maps['after-start-enrichment-table'], sensors.coolantTemperature) or 1
  afterStartEnrichment = math.max(afterStartEnrichment, 1)

  local IATInjectionCompenstation = get2DTableValue(maps['iat-injection-compensation-table'], sensors.IAT - 273.15 --[[K To C]]) or 1

  -- Acceleration enrichment
  local TPSdot = (sensors.TPS - lastTPS) * 100 / dt
  lastTPS = sensors.TPS
  local AE = 1

  if TPSdot > 1000 and frozenTPSdot == 0 then
    ae_timer = 0.5
    frozenTPSdot = TPSdot
  end
  if ae_timer > 0 then
    ae_timer = ae_timer - dt
    local index = math.ceil(frozenTPSdot)
    if index > 20000 then
      index = 20000
    end
    AE = test[index] or 1
    AE = math.max(AE, 1)
    --print("dTPS: " .. frozenTPSdot .. ", AE: " .. AE)
    aeSmoother:get(AE, dt) -- keep it updated but ignore the value
  else
    AE = aeSmoother:get(AE, dt)
    frozenTPSdot = 0
  end
  AE = math.max(AE, 1)
  return rawDuty * afterStartEnrichment * IATInjectionCompenstation * AE
end

local function getInjectorsDuty(sensors, dt)
  if sensors.RPM <= 20 then
    return 0
  end

  local revLimitRPM = safeties.hard_rev_limiter.RPM
  if safeties.hard_rev_limiter.tempRPM > 0 then
    revLimitRPM = math.min(safeties.hard_rev_limiter.RPM, safeties.hard_rev_limiter.tempRPM)
  end

  if
    safeties.hard_rev_limiter.type == 'fuel_cut'
    and timers.limiter_fuel_cut <= 0
    and sensors.RPM >= revLimitRPM
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

  if sensors.TPS <= 0.0 then
    return 0
  end

  local rawDuty = 0
  -- if closedLoop and not simEngine.state.torqueCurveCreation then
  --   rawDuty = calculateClosedLoopInjectorsDuty(dt)
  -- else
    rawDuty = get3DTableValue(maps['injector-table'], sensors.RPM, sensors.MAP, true) / 100 --[[Duty 0-1]]
  -- end
  -- Apply corrections
  local duty = getInjectorsDutyCorrections(sensors, rawDuty, dt)

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
    targetPressure = get3DTableValue(maps['boost-table'], state.RPM, state.requestedTPS * 100) --[[psi]]
  end
  return targetPressure
end

local lastIdleThrottle = 0
local function getThrottlePosition(state, dt)
  if simEngine.state.torqueCurveCreation then
    return state.requestedThrottle
  end

  -- TODOç get from map
  --local idleRPM = combustionEngine.thermals ~= nil and (combustionEngine.thermals.coolantTemperature > 40 and  642 or 1200) or 1000
  local throttle = get3DTableValue(maps['accelerator-position-table'], state.RPM, state.requestedThrottle * 100) / 100 --[[%]]
  if TuningCheatOverwrite then
    throttle = 1
  end

  -- TODO: check if drive by wire is enabled
  local idleThrottle = (maps.options["dbw-idle-throttle"].value or 0) / 100
  if combustionEngine.starterEngagedCoef > 0 then
    idleThrottle = idleThrottle * 2
  elseif combustionEngine.thermals.coolantTemperature < 50 then
    idleThrottle = idleThrottle * 1.1
  end
  -- idleThrottle = controllers.idleThrottlePID:iterate(idleRPM * rpmToAV, simEngine.readings.AV, dt/dt) + (combustionEngine.starterEngagedCoef * combustionEngine.starterThrottleKillCoef * 0.05 )--math.min(1 / ((simEngine.state.RPM / (750) + 1) ^ 2.75), 1)

  if throttle == 0 and combustionEngine.ignitionCoef == 1 then
    --idleThrottle = math.min(math.max(idleThrottle + controllers.idleThrottlePID:iterate_v2(1, simEngine.readings.RPM / idleRPM --[[idleRPM, simEngine.readings.RPM]], dt), 0), 1)-- + (combustionEngine.starterEngagedCoef * combustionEngine.starterThrottleKillCoef * 0.05 )--math.min(1 / ((simEngine.state.RPM / (750) + 1) ^ 2.75), 1)
    lastIdleThrottle = idleThrottle
  end

  throttle = math.min((idleThrottle ~= 0 and idleThrottle or lastIdleThrottle) + throttle * (1 - (idleThrottle ~= 0 and idleThrottle or lastIdleThrottle)), 1)

  -- if electrics.values.tcsActive and simEngine.readings.RPM >= 1200 then
  --   --throttle = throttle * 0.45
  -- end
  return throttle
end

local function update(state, dt)
  local engineRunning = state.RPM > 200 and combustionEngine.ignitionCoef ~= 0
  if maps == nil then
    state.targetBoostPressure = 0
    state.ADV = 0
    state.manifold.runners.injectors.on_time_s = 0
    state.manifold.runners.injectors.duty = 0
    return
  end
  simEngine.debugValues = {
    max_pressure_point_dATDC = 0
  }
  simEngine.readings = {
    RPM = simEngine.state.RPM,
    MAP = simEngine.sensors.getSensorValue("MAP"), --simEngine.state.manifold.MAP,
    TPS = simEngine.state.manifold.throttle.TPS or 0,
    AV = simEngine.state.AV,
    MAF = simEngine.state.manifold.MAF,
    MAFTotal = simEngine.state.manifold.MAFTotal,
    lambda = simEngine.sensors.getSensorValue("lambda"),
    knockSensor = simEngine.state.knockSensor,
    max_pressure_point_dATDC = simEngine.state.max_pressure_point_dATDC or 0,
    coolantTemperature = combustionEngine.thermals and combustionEngine.thermals.coolantTemperature or 0,
    IAT = simEngine.state.manifold.IAT
  }
  -- INPUT
  state.requestedTPS = getThrottlePosition(state, dt, 0)
  handlePWM(state, dt)

  state.targetBoostPressure = getBoostTarget(state, dt) * 6894.76 --[[psi to Pa]]
  if timers.limiter_fuel_cut > 0 then
    state.targetBoostPressure = 0
  end

  local injector_duty = 0
  if engineRunning then
    -- BOOST CUT
    local boostCut = getOptionValue('boost-cut')
    if boostCut > 0 and not simEngine.state.torqueCurveCreation then
      local actualBoostPressurePSI = (simEngine.readings.MAP / 100 --[[kPa to Bar]] - 1) * 14.7 --[[Bar to psi]]
      if actualBoostPressurePSI > boostCut then --TODO: cut spark, not fuel
        safeties.fuel_cut = true
        timers.limiter_fuel_cut = 1 --TODO: add to options
      end
    end

    -- KNOCK
    if not simEngine.state.torqueCurveCreation then
      local knkCount = get3DTableValue(maps['knock-autoadaptation-table'], simEngine.readings.RPM, simEngine.readings.MAP)
      if knkCount > 0 then -- knock is known to happen at this RPM and MAP, prevent it by reducing ignition advance
        local maxRetard = get2DTableValue(maps['max-knk-timing-retard-table'], knkCount)
        corrections.ignition_knock_retard = math.min(corrections.ignition_knock_retard + 5, maxRetard)
      end
    end

    -- IGNITION
    state.ADV = getSparkAdvance()

    -- FUEL
    injector_duty = math.max(math.min(getInjectorsDuty(simEngine.readings, dt), 1), 0)
    state.manifold.runners.injectors.duty = injector_duty
    injector_duty = injector_duty * 100

    if simEngine.sensors.getSensorValue ~= nil and not simEngine.state.torqueCurveCreation then
      local knock = simEngine.sensors.getSensorValue("knock")
      if knock > 0 then
        local current = get3DTableValue(maps['knock-autoadaptation-table'], simEngine.readings.RPM, simEngine.readings.MAP, true)
        local new = current + 1--knock --* knockadaptspeed
        set3DTableValue(maps['knock-autoadaptation-table'], simEngine.readings.RPM, simEngine.readings.MAP, new)
      end
    end
    -- https://injector-rehab.com/knowledge-base/injector-duty-cycle/
    -- injector_duty = (rpm * ipw) / 1200
    state.manifold.runners.injectors.on_time_s = (1200 * injector_duty / simEngine.readings.RPM) / 1000 --[[ms to s]]

    --TODO: get closedloop params from config
    closedLoop = simEngine.readings.RPM < 4000 and simEngine.readings.MAP < 85 and false
  else
    state.targetBoostPressure = 0
    state.ADV = 0
    state.manifold.runners.injectors.on_time_s = 0
    state.manifold.runners.injectors.duty = 0
    injector_duty = 0
  end

  -- OUTPUT
  local dataOut = {
    RPM = simEngine.readings.RPM,
    ADV = state.ADV,
    lambda = simEngine.readings.lambda,
    manifold = {
        IAT = simEngine.state.manifold.IAT,
        MAF = simEngine.state.manifold.MAF,
        MAP = simEngine.readings.MAP,
        throttle = {
            TPS = simEngine.readings.TPS,
        },
        runners = {
            air_fuel_ratio = simEngine.readings.lambda * 14.7,
            injectors = {
                duty = injector_duty / 100,
            },
        }
    },
    fuelSystem = {
        pressure_bar = state.fuelSystem.pressure_bar,
    },
    targetBoostPressure = state.targetBoostPressure,
    knockSensor = simEngine.readings.knockSensor,
  }
  tunerServer.setOutData(dataOut)
end

local function setTempRevLimiter(device, revLimiterAV, maxOvershootAV)
  safeties.hard_rev_limiter.tempRPM = revLimiterAV * avToRPM
end

local function resetTempRevLimiter(device)
  safeties.hard_rev_limiter.tempRPM = 0
end

local function updateGFX(dt)
  tunerServer.update()
  if tunerServer.isTuneUpdated() then
    print("Tune updated!")
    reloadTuneFromFile()
  end
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
M.getOptionValue = getOptionValue

return M
