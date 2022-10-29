local tunerServer = require("tunerServer/tunerServer")

local M = {}
M.SUPPORTED_MAPS_VERSION = 0.2

local simEngine = nil -- engine.lua
local combustionEngine = nil -- tunableCombustionEngine.lua
local engineMeasurements = nil

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
    RPM = 0,
    type = 'fuel_cut'
  },
  fuel_cut = false
}

local logs = {}
local isLoggingEnabled = true

local function reloadTuneFromFile()
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
      if map.type == '3D' or map.type == '2D' then
        table.sort(map.yValues, function(a, b)
          return a < b
        end)
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
  local y_min = 0.0
  local y_max = 0.0
  local x_min = 0.0
  local x_max = 0.0

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
  local yMax = map.yValues[#map.yValues]
  local xMax = map.xValues[#map.xValues]

  if y_max >= yMax then
    y_max = yMax
    y_min = yMax
  end
  if x_max >= xMax then
    x_max = xMax
    x_min = xMax
  end
  -- dump({
  --   y_min = y_min,
  --   y_max = y_max,
  --   x_min = x_min,
  --   x_max = x_max
  -- })
  -- print(y_max)
  -- dumpToFile("Sos.map", map)
  -- print("here")
  local Q11 = map.values['' .. y_min]['' .. x_min]
  local Q12 = map.values['' .. y_max]['' .. x_min]
  local Q21 = map.values['' .. y_min]['' .. x_max]
  local Q22 = map.values['' .. y_max]['' .. x_max]

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

local function updateGFX(device, dt)
  tuneOutData.lambda = simEngine.sensors.lambda

  local afr = simEngine.sensors.lambda * 14.7 --NOTE: If using another fuel instead of gasoline, change this value
  tuneOutData.afr = string.format("%.2f", afr)

  tuneOutData.rpm = string.format("%.2f", simEngine.sensors.RPM)
  tuneOutData.throttle = string.format("%.2f", simEngine.sensors.TPS)
  tuneOutData.map = string.format("%.2f", simEngine.sensors.MAP)
  tuneOutData.maf = string.format("%.2f", simEngine.sensors.MAF*1000)

  -- Debug
  tuneOutData.max_pressure_point_dATDC = string.format("%.2f", simEngine.debugValues.max_pressure_point_dATDC)

  --TODO: use for the logs
  tuneOutData.ignTiming = string.format("%.2f", logs[#logs].ignition_advance_deg)
  tuneOutData.injDuty = string.format("%.4f", logs[#logs].injector_duty)
  tunerServer.setOutData(tuneOutData)

  tunerServer.update()
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

local function init(lEngine, lCombustionEngine, lEngineMeasurements, jbeamData)
  simEngine = lEngine
  engineMeasurements = lEngineMeasurements
  combustionEngine = lCombustionEngine
  table.insert(
    logs,
    {
      ignition_advance_deg = 0,
      injector_duty = 0
    }
  )
  reset()
end

--[[
    Returns a negative value if the ignition advance needs to be decreased, a positive or 0 value otherwise
]]
local function getSparkAdvanceCorrections()
  local corr = 0

  -- Knock correction
  corr = -corrections.ignition_knock_retard

  --TODO: Add temperature corrections and other factors
  return corr
end

local function getSparkAdvance()
  local mapAdvance = get3DTableValue(maps['advance-table'], simEngine.sensors.RPM, simEngine.sensors.MAP) --[[ºbTDC]]

  -- Apply corrections
  local advance = mapAdvance + getSparkAdvanceCorrections()

  if isLoggingEnabled then
    logs[#logs].ignition_advance_deg = advance -- TODO: scroll logs instead of overwriting the last value
  end

  return advance
end

local function getInjectorsDutyCorrections()
  --TODO: Add temperature corrections, acceleration enrichment, etc...
  return 0
end

local function getInjectorsDuty(dt)
  -- if ecu.safeties.soft_rev_limiter.enabled and sensors.RPM >= ecu.safeties.soft_rev_limiter.RPM then
  -- ecu.safeties.soft_limiter_ignition_retard =
  -- else
  -- ecu.safeties.soft_limiter_ignition_retard = 0
  -- end
  if safeties.hard_rev_limiter.type == 'fuel_cut' and timers.limiter_fuel_cut <= 0 and simEngine.sensors.RPM >= safeties.hard_rev_limiter.RPM then
    timers.limiter_fuel_cut = 0.05
    -- engine.instantAfterFireFuelDelay:push(10000000000000) -- To simulate spark cut limiter
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

  local mapDuty = get3DTableValue(maps['injector-table'], simEngine.sensors.RPM, simEngine.sensors.MAP) / 100 --[[Duty 0-1]]

  -- Apply corrections
  local duty = mapDuty + getInjectorsDutyCorrections()

  if isLoggingEnabled then
    logs[#logs].injector_duty = duty -- TODO: scroll logs instead of overwriting the last value
  end

  return duty
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.getSparkAdvance = getSparkAdvance
M.getInjectorsDuty = getInjectorsDuty

M.throttleSmoother = throttleSmoother
M.mapSmoother = mapSmoother

return M
