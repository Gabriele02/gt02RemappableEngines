local M = {}

local throttle_cv = nil
local intakeMeasurements = nil

local atmToKPa = 101.325
local specific_gravity_air = 1

local function init(data, state)
  intakeMeasurements = data.intakeMeasurements
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
  throttle_cv = createCurve(throttle_cv_points['_' .. intakeMeasurements.throttle.throttleSize_mm], true)
  
  if not throttle_cv then
    log("E", "throttle", "Failed to create throttle curve")
  else
    log("I", "throttle", "Created throttle curve for " .. intakeMeasurements.throttle.throttleSize_mm .. "mm throttle")
  end
  
  if state.manifold.throttle == nil then
    state.manifold.throttle = {
        massAirflowIntoIntake = 0
    }
  end

  return state
end

local function calculateThrottlePosition(state)
    local throttle = state.requestedTPS --or intakeMeasurements.idle_throttle
    --   if state.ignitionCoef == 0 and state.manifold.throttle == nil then
    --     throttle = 0
    -- end
    state.manifold.throttle.TPS = throttle
    --   sensors.TPS = simEngine.state.TPS
    --return state
end

local function getThrottleCv(state) -- no need to have cv in state
    return throttle_cv[
        math.min(
            math.ceil(
                math.acos(1 - state.manifold.throttle.TPS ^ (1.5)--[[^ 2]]) * 57.296--[[rad to deg]]
                ),
            90.0
        )
    ] + 1E-10
end

local function calculateThrottleAirflow(state)
    local mapAtm = state.manifold.MAP / atmToKPa --[[KPa to atm]]
    local intake_air_pressure_psi =  intakeMeasurements.IAP / atmToKPa * 14.7
    local t = (intakeMeasurements.IAT) * 9/5 --[[ºR]]
    local map_psi = math.min(mapAtm * 14.7, intake_air_pressure_psi)
    local cv = getThrottleCv(state)
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

local function update(state, dt) -- -> modifyed state
    calculateThrottlePosition(state)
    local throttleCv = getThrottleCv(state)
    local massAirflowIntoIntake = calculateThrottleAirflow(state)
    state.manifold.throttle.massAirflowIntoIntake = massAirflowIntoIntake
    --return state
end

M.init = init
M.update = update
return M