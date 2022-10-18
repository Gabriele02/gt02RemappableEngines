local M = {}
local simEngine = require"lua.vehicle.powertrain.engine.engine"
local engineFunctions = nil

local function init(localEngine, jbeamData)
  simEngine.init(localEngine, jbeamData)
end

-- local function initSecondStage()

-- end

local function resetSimEngine()
  simEngine.reset()
end

--------------------------------------------------------------------------
-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- local M = {}

M.outputPorts = { [1] = true } --set dynamically
M.deviceCategories = { engine = true }

local delayLine = require("delayLine")

local max = math.max
local min = math.min
local abs = math.abs
local floor = math.floor
local random = math.random

local rpmToAV = 0.104719755
local avToRPM = 9.549296596425384
local torqueToPower = 0.0001404345295653085
local psToWatt = 735.499
local hydrolockThreshold = 0.9

local function getTorqueData(device)

  -- Warm up the engine
  print("Warming up engine...")
  for i = 1, 50, 1 do
    simEngine.simulateEngine(0.01, {RPM = 250 + i*10, warmup = true, warmupCycleNum = i, throttle = 1, instantEngineLoad = 1, doNotRandom = true}, true)
  end
  -- pippo.pluto.paperino()

  local curves = {}
  local curveCounter = 1
  local maxTorque = 0
  local maxTorqueRPM = 0
  local maxPower = 0
  local maxPowerRPM = 0
  local maxRPM = device.maxRPM

  local turboCoefs = nil
  local superchargerCoefs = nil
  local nitrousTorques = nil

  local torqueCurve = {}
  local powerCurve = {}

  for k, v in pairs(device.torqueCurve) do
    if type(k) == "number" and k < maxRPM then
      simEngine.sensors.RPM = k
      simEngine.sensors.TPS = 1
      if k < 200 then
        print(k)        
      end
      torqueCurve[k + 1] = simEngine.simulateEngine(1/2000, {RPM = k, throttle = 1, instantEngineLoad = 1, doNotRandom = true}, true) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
          (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
          device.torqueCurve[k + 1] = torqueCurve[k + 1]
      powerCurve[k + 1] = torqueCurve[k + 1] * k * torqueToPower
      if torqueCurve[k + 1] > maxTorque then
        maxTorque = torqueCurve[k + 1]
        maxTorqueRPM = k + 1
      end
      if powerCurve[k + 1] > maxPower then
        maxPower = powerCurve[k + 1]
        maxPowerRPM = k + 1
      end
    end
  end
  -- pippo.scopa()
  table.insert(curves, curveCounter, { torque = torqueCurve, power = powerCurve, name = "NA", priority = 10 })
  -- dumpToFile("t.txt", torqueCurve)
  -- if device.nitrousOxideInjection.isExisting then
  --   local torqueCurveNitrous = {}
  --   local powerCurveNitrous = {}
  --   nitrousTorques = device.nitrousOxideInjection.getAddedTorque()

  --   for k, v in pairs(device.torqueCurve) do
  --     if type(k) == "number" and k < maxRPM then
  --       torqueCurveNitrous[k + 1] = v + (nitrousTorques[k] or 0) -
  --           device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
  --           (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
  --       powerCurveNitrous[k + 1] = torqueCurveNitrous[k + 1] * k * torqueToPower
  --       if torqueCurveNitrous[k + 1] > maxTorque then
  --         maxTorque = torqueCurveNitrous[k + 1]
  --         maxTorqueRPM = k + 1
  --       end
  --       if powerCurveNitrous[k + 1] > maxPower then
  --         maxPower = powerCurveNitrous[k + 1]
  --         maxPowerRPM = k + 1
  --       end
  --     end
  --   end

  --   curveCounter = curveCounter + 1
  --   table.insert(curves, curveCounter,
  --     { torque = torqueCurveNitrous, power = powerCurveNitrous, name = "N2O", priority = 20 })
  -- end

  -- if device.turbocharger.isExisting then
  --   local torqueCurveTurbo = {}
  --   local powerCurveTurbo = {}
  --   turboCoefs = device.turbocharger.getTorqueCoefs()

  --   for k, v in pairs(device.torqueCurve) do
  --     if type(k) == "number" and k < maxRPM then
  --       torqueCurveTurbo[k + 1] = (v * (turboCoefs[k] or 0)) -
  --           device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
  --           (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
  --       powerCurveTurbo[k + 1] = torqueCurveTurbo[k + 1] * k * torqueToPower
  --       if torqueCurveTurbo[k + 1] > maxTorque then
  --         maxTorque = torqueCurveTurbo[k + 1]
  --         maxTorqueRPM = k + 1
  --       end
  --       if powerCurveTurbo[k + 1] > maxPower then
  --         maxPower = powerCurveTurbo[k + 1]
  --         maxPowerRPM = k + 1
  --       end
  --     end
  --   end

  --   curveCounter = curveCounter + 1
  --   table.insert(curves, curveCounter,
  --     { torque = torqueCurveTurbo, power = powerCurveTurbo, name = "Turbo", priority = 30 })
  -- end

  -- if device.supercharger.isExisting then
  --   local torqueCurveSupercharger = {}
  --   local powerCurveSupercharger = {}
  --   superchargerCoefs = device.supercharger.getTorqueCoefs()

  --   for k, v in pairs(device.torqueCurve) do
  --     if type(k) == "number" and k < maxRPM then
  --       torqueCurveSupercharger[k + 1] = (v * (superchargerCoefs[k] or 0)) -
  --           device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
  --           (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
  --       powerCurveSupercharger[k + 1] = torqueCurveSupercharger[k + 1] * k * torqueToPower
  --       if torqueCurveSupercharger[k + 1] > maxTorque then
  --         maxTorque = torqueCurveSupercharger[k + 1]
  --         maxTorqueRPM = k + 1
  --       end
  --       if powerCurveSupercharger[k + 1] > maxPower then
  --         maxPower = powerCurveSupercharger[k + 1]
  --         maxPowerRPM = k + 1
  --       end
  --     end
  --   end

  --   curveCounter = curveCounter + 1
  --   table.insert(curves, curveCounter,
  --     { torque = torqueCurveSupercharger, power = powerCurveSupercharger, name = "SC", priority = 40 })
  -- end

  -- if device.turbocharger.isExisting and device.supercharger.isExisting then
  --   local torqueCurveFinal = {}
  --   local powerCurveFinal = {}

  --   for k, v in pairs(device.torqueCurve) do
  --     if type(k) == "number" and k < maxRPM then
  --       torqueCurveFinal[k + 1] = (v * (turboCoefs[k] or 0) * (superchargerCoefs[k] or 0)) -
  --           device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
  --           (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
  --       powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
  --       if torqueCurveFinal[k + 1] > maxTorque then
  --         maxTorque = torqueCurveFinal[k + 1]
  --         maxTorqueRPM = k + 1
  --       end
  --       if powerCurveFinal[k + 1] > maxPower then
  --         maxPower = powerCurveFinal[k + 1]
  --         maxPowerRPM = k + 1
  --       end
  --     end
  --   end

  --   curveCounter = curveCounter + 1
  --   table.insert(curves, curveCounter,
  --     { torque = torqueCurveFinal, power = powerCurveFinal, name = "Turbo + SC", priority = 50 })
  -- end

  -- if device.turbocharger.isExisting and device.nitrousOxideInjection.isExisting then
  --   local torqueCurveFinal = {}
  --   local powerCurveFinal = {}

  --   for k, v in pairs(device.torqueCurve) do
  --     if type(k) == "number" and k < maxRPM then
  --       torqueCurveFinal[k + 1] = (v * (turboCoefs[k] or 0) + (nitrousTorques[k] or 0)) -
  --           device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
  --           (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
  --       powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
  --       if torqueCurveFinal[k + 1] > maxTorque then
  --         maxTorque = torqueCurveFinal[k + 1]
  --         maxTorqueRPM = k + 1
  --       end
  --       if powerCurveFinal[k + 1] > maxPower then
  --         maxPower = powerCurveFinal[k + 1]
  --         maxPowerRPM = k + 1
  --       end
  --     end
  --   end

  --   curveCounter = curveCounter + 1
  --   table.insert(curves, curveCounter,
  --     { torque = torqueCurveFinal, power = powerCurveFinal, name = "Turbo + N2O", priority = 60 })
  -- end

  -- if device.supercharger.isExisting and device.nitrousOxideInjection.isExisting then
  --   local torqueCurveFinal = {}
  --   local powerCurveFinal = {}

  --   for k, v in pairs(device.torqueCurve) do
  --     if type(k) == "number" and k < maxRPM then
  --       torqueCurveFinal[k + 1] = (v * (superchargerCoefs[k] or 0) + (nitrousTorques[k] or 0)) -
  --           device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
  --           (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
  --       powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
  --       if torqueCurveFinal[k + 1] > maxTorque then
  --         maxTorque = torqueCurveFinal[k + 1]
  --         maxTorqueRPM = k + 1
  --       end
  --       if powerCurveFinal[k + 1] > maxPower then
  --         maxPower = powerCurveFinal[k + 1]
  --         maxPowerRPM = k + 1
  --       end
  --     end
  --   end

  --   curveCounter = curveCounter + 1
  --   table.insert(curves, curveCounter,
  --     { torque = torqueCurveFinal, power = powerCurveFinal, name = "SC + N2O", priority = 70 })
  -- end

  -- if device.turbocharger.isExisting and device.supercharger.isExisting and device.nitrousOxideInjection.isExisting then
  --   local torqueCurveFinal = {}
  --   local powerCurveFinal = {}

  --   for k, v in pairs(device.torqueCurve) do
  --     if type(k) == "number" and k < maxRPM then
  --       torqueCurveFinal[k + 1] = (v * (turboCoefs[k] or 0) * (superchargerCoefs[k] or 0) + (nitrousTorques[k] or 0)) -
  --           device.friction * device.wearFrictionCoef * device.damageFrictionCoef -
  --           (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
  --       powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
  --       if torqueCurveFinal[k + 1] > maxTorque then
  --         maxTorque = torqueCurveFinal[k + 1]
  --         maxTorqueRPM = k + 1
  --       end
  --       if powerCurveFinal[k + 1] > maxPower then
  --         maxPower = powerCurveFinal[k + 1]
  --         maxPowerRPM = k + 1
  --       end
  --     end
  --   end

  --   curveCounter = curveCounter + 1
  --   table.insert(curves, curveCounter,
  --     { torque = torqueCurveFinal, power = powerCurveFinal, name = "Turbo + SC + N2O", priority = 80 })
  -- end

  table.sort(
    curves,
    function(a, b)
      local ra, rb = a.priority, b.priority
      if ra == rb then
        return a.name < b.name
      else
        return ra > rb
      end
    end
  )

  local dashes = { nil, { 10, 4 }, { 8, 3, 4, 3 }, { 6, 3, 2, 3 }, { 5, 3 } }
  for k, v in ipairs(curves) do
    v.dash = dashes[k]
    v.width = 2
  end

  return { maxRPM = maxRPM, curves = curves, maxTorque = maxTorque, maxPower = maxPower, maxTorqueRPM = maxTorqueRPM,
    maxPowerRPM = maxPowerRPM, finalCurveName = 1, deviceName = device.name, vehicleID = obj:getId() }
end

local function updateEnergyStorageRatios(device)
  for _, s in pairs(device.registeredEnergyStorages) do
    local storage = energyStorage.getStorage(s)
    if storage and storage.energyType == device.requiredEnergyType then
      if storage.storedEnergy > 0 then
        device.energyStorageRatios[storage.name] = 1 / device.storageWithEnergyCounter
      else
        device.energyStorageRatios[storage.name] = 0
      end
    end
  end
end

local function sendTorqueData(device, data)
  if not data then
    data = device:getTorqueData()
  end
  guihooks.trigger("TorqueCurveChanged", data)
end

local function updateFuelUsage(device)
  if not device.energyStorage then
    return
  end

  local hasFuel = false
  local previousTankCount = device.storageWithEnergyCounter
  local remainingFuelRatio = 0
  for _, s in pairs(device.registeredEnergyStorages) do
    local storage = energyStorage.getStorage(s)
    if storage and storage.energyType == device.requiredEnergyType then
      local previous = device.previousEnergyLevels[storage.name]
      storage.storedEnergy = max(storage.storedEnergy - (device.spentEnergy * device.energyStorageRatios[storage.name]),
        0)
      if previous > 0 and storage.storedEnergy <= 0 then
        device.storageWithEnergyCounter = device.storageWithEnergyCounter - 1
      elseif previous <= 0 and storage.storedEnergy > 0 then
        device.storageWithEnergyCounter = device.storageWithEnergyCounter + 1
      end
      device.previousEnergyLevels[storage.name] = storage.storedEnergy
      hasFuel = hasFuel or storage.storedEnergy > 0
      remainingFuelRatio = remainingFuelRatio + storage.remainingRatio
    end
  end

  if previousTankCount ~= device.storageWithEnergyCounter then
    device:updateEnergyStorageRatios()
  end

  if not hasFuel and device.hasFuel then
    device:disable()
  elseif hasFuel and not device.hasFuel then
    device:enable()
  end

  device.hasFuel = hasFuel
  device.remainingFuelRatio = remainingFuelRatio / device.storageWithEnergyCounter
end

local function updateGFX(device, dt)
  simEngine.updateGFX(device, dt)
  engineFunctions.updateGFX(device, dt)
end

--velocity update is always nopped for engines

local function updateTorque(device, dt)
  local engineAV = device.outputAV1

  local throttle = (electrics.values[device.electricsThrottleName] or 0) *
      (electrics.values[device.electricsThrottleFactorName] or device.throttleFactor)
  device.requestedThrottle = throttle

  local idleAVError = max(device.idleAV - engineAV + device.idleAVReadError + device.idleAVStartOffset, 0)
  local idleThrottle = max(throttle, min(idleAVError * 0.01, device.maxIdleThrottle))
  throttle = min(max(idleThrottle * device.starterThrottleKillCoef * device.ignitionCoef, 0), 1)

  if device.applyRevLimiter then
    throttle = device:applyRevLimiter(engineAV, throttle, dt)
  end

  --smooth our actual throttle value to simulate various effects in a real engine that do not allow immediate throttle changes
  throttle = device.throttleSmoother:getUncapped(throttle, dt)

  local finalFriction = device.friction * device.wearFrictionCoef * device.damageFrictionCoef
  local finalDynamicFriction = device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef

  local torque = (device.torqueCurve[floor(engineAV * avToRPM)] or 0) * device.intakeAirDensityCoef
  local maxCurrentTorque = torque - finalFriction - (finalDynamicFriction * engineAV)
  --blend pure throttle with the constant power map
  local throttleMap = min(max(throttle +
    throttle * device.maxPowerThrottleMap / (torque * device.forcedInductionCoef * engineAV + 1e-30) * (1 - throttle), 0)
    , 1)

  local ignitionCut = device.ignitionCutTime > 0
  torque = ((torque * device.forcedInductionCoef * throttleMap) + device.nitrousOxideTorque) * device.outputTorqueState *
      (ignitionCut and 0 or 1) * device.slowIgnitionErrorCoef * device.fastIgnitionErrorCoef

  local lastInstantEngineLoad = device.instantEngineLoad
  -- local instantLoad = min(max(torque /
  --   ((maxCurrentTorque + 1e-30) * device.outputTorqueState * device.forcedInductionCoef), 0), 1)
  -- device.instantEngineLoad = instantLoad
  -- device.engineLoad = device.loadSmoother:get(device.instantEngineLoad, dt)

  local absEngineAV = abs(engineAV)
  local dtT = dt * torque
  local dtTNitrousOxide = dt * device.nitrousOxideTorque

  local burnEnergy = dtT * (dtT * device.halfInvEngInertia + engineAV)
  local burnEnergyNitrousOxide = dtTNitrousOxide * (dtTNitrousOxide * device.halfInvEngInertia + engineAV)
  device.engineWorkPerUpdate = device.engineWorkPerUpdate + burnEnergy
  device.frictionLossPerUpdate = device.frictionLossPerUpdate + finalFriction * absEngineAV * dt
  device.pumpingLossPerUpdate = device.pumpingLossPerUpdate + finalDynamicFriction * engineAV * engineAV * dt
  local invBurnEfficiency = device.invBurnEfficiencyTable[floor(device.instantEngineLoad * 100)] *
      device.invBurnEfficiencyCoef
  device.spentEnergy = device.spentEnergy + burnEnergy * invBurnEfficiency
  device.spentEnergyNitrousOxide = device.spentEnergyNitrousOxide + burnEnergyNitrousOxide * invBurnEfficiency

  local frictionTorque = finalFriction + finalDynamicFriction * absEngineAV +
      device.engineBrakeTorque * (1 - device.instantEngineLoad)
  --friction torque is limited for stability
  frictionTorque = min(frictionTorque, absEngineAV * device.inertia * 2000) * sign(engineAV)

  local starterTorque = device.starterEngagedCoef * device.starterTorque *
      min(max(1 - engineAV / device.starterMaxAV, -0.5), 1)

  --iterate over all connected clutches and sum their torqueDiff to know the final torque load on the engine
  local torqueDiffSum = 0
  for i = 1, device.numberOfOutputPorts do
    torqueDiffSum = torqueDiffSum + device.clutchChildren[i].torqueDiff
  end
  --calculate the AV based on all loads
  local outputAV = 0
  if TuningCheatOverwrite then
    torque = simEngine.simulateEngine(dt, {RPM = RpmOverwrite, throttle = 1, instantEngineLoad = 1, map = MapOverwrite}, false)
    outputAV = RpmOverwrite * rpmToAV
  else
    torque = simEngine.simulateEngine(dt, nil, false)
    outputAV = (engineAV + dt * (torque - torqueDiffSum - frictionTorque + starterTorque) * device.invEngInertia) * device.outputAVState
  end
  --set all output torques and AVs to the newly calculated values
  for i = 1, device.numberOfOutputPorts do
    device[device.outputTorqueNames[i]] = torqueDiffSum
    device[device.outputAVNames[i]] = outputAV
  end
  device.throttle = throttle
  device.combustionTorque = torque - frictionTorque
  device.frictionTorque = frictionTorque

  local inertialTorque = (device.outputAV1 - device.lastOutputAV1) * device.inertia / dt
  ffi.C.bng_applyTorqueAxisCouple(ffiObjPtr, inertialTorque, device.torqueReactionNodes[1],
    device.torqueReactionNodes[2
    ], device.torqueReactionNodes[3])
  device.lastOutputAV1 = device.outputAV1

  local dLoad = min((device.instantEngineLoad - lastInstantEngineLoad) / dt, 0)
  local instantAfterFire = engineAV > device.idleAV * 2 and
      max(device.instantAfterFireCoef * -dLoad * lastInstantEngineLoad * absEngineAV, 0) or 0
  local sustainedAfterFire = (device.instantEngineLoad <= 0 and device.sustainedAfterFireTimer > 0) and
      max(engineAV * device.sustainedAfterFireCoef, 0) or 0

  device.instantAfterFireFuel = device.instantAfterFireFuel + instantAfterFire
  device.sustainedAfterFireFuel = device.sustainedAfterFireFuel + sustainedAfterFire
  device.shiftAfterFireFuel = device.shiftAfterFireFuel + instantAfterFire * (ignitionCut and 1 or 0)

  device.lastOutputTorque = torque
  device.ignitionCutTime = max(device.ignitionCutTime - dt, 0)

  device.fixedStepTimer = device.fixedStepTimer + dt
  if device.fixedStepTimer >= device.fixedStepTime then
    device:updateFixedStep(device.fixedStepTimer)
    device.fixedStepTimer = device.fixedStepTimer - device.fixedStepTime
  end
end

local function selectUpdates(device)
  device.velocityUpdate = nop
  device.torqueUpdate = updateTorque
end

local function reset(device, jbeamData)
  resetSimEngine()
  device.friction = jbeamData.friction or 0

  --reset output AVs and torques
  for i = 1, device.numberOfOutputPorts, 1 do
    device[device.outputTorqueNames[i]] = 0
    device[device.outputAVNames[i]] = jbeamData.idleRPM * rpmToAV
  end
  device.inputAV = 0
  device.virtualMassAV = 0
  device.isBroken = false
  device.combustionTorque = 0
  device.frictionTorque = 0
  device.nitrousOxideTorque = 0

  device.electricsThrottleName = jbeamData.electricsThrottleName or "throttle"
  device.electricsThrottleFactorName = jbeamData.electricsThrottleFactorName or "throttleFactor"
  device.throttleFactor = 1

  device.throttle = 0
  device.requestedThrottle = 0
  device.ignitionCoef = 1
  device.dynamicFriction = jbeamData.dynamicFriction or 0

  device.idleAVReadError = 0
  device.idleAVStartOffset = 0
  device.inertia = device.initialInertia
  device.invEngInertia = 1 / device.inertia
  device.halfInvEngInertia = device.invEngInertia * 0.5

  device.slowIgnitionErrorSmoother:reset()
  device.slowIgnitionErrorTimer = 0
  device.slowIgnitionErrorChance = 0.0
  device.slowIgnitionErrorCoef = 1
  device.fastIgnitionErrorSmoother:reset()
  device.fastIgnitionErrorChance = 0.0
  device.fastIgnitionErrorCoef = 1

  device.starterEngagedCoef = 0
  device.starterThrottleKillCoef = 1
  device.starterThrottleKillTimer = 0
  device.starterDisabled = false
  device.idleAVStartOffsetSmoother:reset()
  device.shutOffSoundRequested = false

  device.stallTimer = 1
  device.isStalled = false

  device.floodLevel = 0
  device.prevFloodPercent = 0

  device.forcedInductionCoef = 1
  device.intakeAirDensityCoef = 1
  device.outputTorqueState = 1
  device.outputAVState = 1
  device.isDisabled = false
  device.lastOutputAV1 = jbeamData.idleRPM * rpmToAV
  device.lastOutputTorque = 0

  device.loadSmoother:reset()
  device.throttleSmoother:reset()
  device.engineLoad = 0
  device.instantEngineLoad = 0
  device.ignitionCutTime = 0
  device.slowIgnitionErrorCoef = 1
  device.fastIgnitionErrorCoef = 1

  device.sustainedAfterFireTimer = 0
  device.instantAfterFireFuel = 0
  device.sustainedAfterFireFuel = 0
  device.shiftAfterFireFuel = 0
  device.continuousAfterFireFuel = 0
  device.instantAfterFireFuelDelay:reset()
  device.sustainedAfterFireFuelDelay:reset()

  device.overRevDamage = 0
  device.overTorqueDamage = 0

  device.engineWorkPerUpdate = 0
  device.frictionLossPerUpdate = 0
  device.pumpingLossPerUpdate = 0
  device.spentEnergy = 0
  device.spentEnergyNitrousOxide = 0
  device.storageWithEnergyCounter = 0
  device.registeredEnergyStorages = {}
  device.previousEnergyLevels = {}
  device.energyStorageRatios = {}
  device.hasFuel = true
  device.remainingFuelRatio = 1

  device.revLimiterActive = false
  device.revLimiterWasActiveTimer = 999

  device.brakeSpecificFuelConsumption = 0

  device.wearFrictionCoef = 1
  device.damageFrictionCoef = 1
  device.wearDynamicFrictionCoef = 1
  device.damageDynamicFrictionCoef = 1
  device.wearIdleAVReadErrorRangeCoef = 1
  device.damageIdleAVReadErrorRangeCoef = 1

  device:resetTempRevLimiter()

  device.thermals.reset(jbeamData)

  device.turbocharger.reset(v.data[jbeamData.turbocharger])
  device.supercharger.reset(v.data[jbeamData.supercharger])
  device.nitrousOxideInjection.reset(jbeamData)

  device.torqueData = getTorqueData(device)
  device.maxPower = device.torqueData.maxPower
  device.maxTorque = device.torqueData.maxTorque
  device.maxPowerThrottleMap = device.torqueData.maxPower * psToWatt

  damageTracker.setDamage("engine", "engineDisabled", false)
  damageTracker.setDamage("engine", "engineLockedUp", false)
  damageTracker.setDamage("engine", "engineReducedTorque", false)
  damageTracker.setDamage("engine", "catastrophicOverrevDamage", false)
  damageTracker.setDamage("engine", "mildOverrevDamage", false)
  damageTracker.setDamage("engine", "overRevDanger", false)
  damageTracker.setDamage("engine", "catastrophicOverTorqueDamage", false)
  damageTracker.setDamage("engine", "overTorqueDanger", false)
  damageTracker.setDamage("engine", "engineHydrolocked", false)
  damageTracker.setDamage("engine", "engineIsHydrolocking", false)
  damageTracker.setDamage("engine", "impactDamage", false)

  selectUpdates(device)
end

local function revLimiterDisabledMethod(device, engineAV, throttle, dt)
  return throttle
end

local function revLimiterSoftMethod(device, engineAV, throttle, dt)
  local limiterAV = min(device.maxAV, device.tempRevLimiterAV)
  local correctedThrottle = -throttle * min(max(engineAV - limiterAV, 0), device.revLimiterMaxAVOvershoot) *
      device.invRevLimiterRange + throttle

  if device.isTempRevLimiterActive and correctedThrottle < throttle then
    device:setExhaustGainMufflingOffsetRevLimiter(-0.1, 2)
  end
  return correctedThrottle
end

local function revLimiterTimeMethod(device, engineAV, throttle, dt)
  local limiterAV = min(device.maxAV, device.tempRevLimiterAV)
  if device.revLimiterActive then
    device.revLimiterActiveTimer = device.revLimiterActiveTimer - dt
    local revLimiterAVThreshold = min(limiterAV - device.revLimiterMaxAVDrop, limiterAV)
    --Deactivate the limiter once below the deactivation threshold
    device.revLimiterActive = device.revLimiterActiveTimer > 0 and engineAV > revLimiterAVThreshold
    device.revLimiterWasActiveTimer = 0
    return 0
  end

  if engineAV > limiterAV and not device.revLimiterActive then
    device.revLimiterActiveTimer = device.revLimiterCutTime
    device.revLimiterActive = true
    device.revLimiterWasActiveTimer = 0
    return 0
  end

  return throttle
end

local function revLimiterRPMDropMethod(device, engineAV, throttle, dt)
  local limiterAV = min(device.maxAV, device.tempRevLimiterAV)
  if device.revLimiterActive or engineAV > limiterAV then
    --Deactivate the limiter once below the deactivation threshold
    local revLimiterAVThreshold = min(limiterAV - device.revLimiterAVDrop, limiterAV)
    device.revLimiterActive = engineAV > revLimiterAVThreshold
    device.revLimiterWasActiveTimer = 0
    return 0
  end

  return throttle
end

local function new(jbeamData)
  local dummyData               = deepcopy(jbeamData)
  dummyData.numberOfOutputPorts = 1
  dummyData.name                = "mainEngine"
  dummyData.type                = "combustionEngine"
  engineFunctions               = require("powertrain/combustionEngine").new(dummyData)
  local device                  = {
    deviceCategories = shallowcopy(M.deviceCategories),
    requiredExternalInertiaOutputs = shallowcopy(M.requiredExternalInertiaOutputs),
    outputPorts = shallowcopy(M.outputPorts),
    name = jbeamData.name,
    type = jbeamData.type,
    inputName = jbeamData.inputName,
    inputIndex = jbeamData.inputIndex,
    friction = jbeamData.friction or 0,
    cumulativeInertia = 1,
    cumulativeGearRatio = 1,
    maxCumulativeGearRatio = 1,
    isPhysicallyDisconnected = true,
    isPropulsed = true,
    outputAV1 = jbeamData.idleRPM * rpmToAV,
    outputRPM = 0,
    inputAV = 0,
    outputTorque1 = 0,
    virtualMassAV = 0,
    isBroken = false,
    combustionTorque = 0,
    frictionTorque = 0,
    nitrousOxideTorque = 0,
    electricsThrottleName = jbeamData.electricsThrottleName or "throttle",
    electricsThrottleFactorName = jbeamData.electricsThrottleFactorName or "throttleFactor",
    throttleFactor = 1,
    throttle = 0,
    requestedThrottle = 0,
    ignitionCoef = 1,
    dynamicFriction = jbeamData.dynamicFriction or 0,
    idleRPM = jbeamData.idleRPM,
    idleAV = jbeamData.idleRPM * rpmToAV,
    maxRPM = jbeamData.maxRPM,
    maxAV = jbeamData.maxRPM * rpmToAV,
    idleAVReadError = 0,
    idleAVReadErrorRange = (jbeamData.idleRPMRoughness or 50) * rpmToAV,
    inertia = jbeamData.inertia or 0.1,
    idleAVStartOffset = 0,
    maxIdleThrottle = jbeamData.maxIdleThrottle or 0.15,
    starterTorque = jbeamData.starterTorque or (jbeamData.friction * 15),
    starterMaxAV = (jbeamData.starterMaxRPM or jbeamData.idleRPM * 0.7) * rpmToAV,
    shutOffSoundRequested = false,
    starterEngagedCoef = 0,
    starterThrottleKillCoef = 1,
    starterThrottleKillTimer = 0,
    starterThrottleKillTime = jbeamData.starterThrottleKillTime or 0.5,
    starterDisabled = false,
    stallTimer = 1,
    isStalled = false,
    floodLevel = 0,
    prevFloodPercent = 0,
    particulates = jbeamData.particulates,
    thermalsEnabled = jbeamData.thermalsEnabled,
    engineBlockMaterial = jbeamData.engineBlockMaterial,
    oilVolume = jbeamData.oilVolume,
    cylinderWallTemperatureDamageThreshold = jbeamData.cylinderWallTemperatureDamageThreshold,
    headGasketDamageThreshold = jbeamData.headGasketDamageThreshold,
    pistonRingDamageThreshold = jbeamData.pistonRingDamageThreshold,
    connectingRodDamageThreshold = jbeamData.connectingRodDamageThreshold,
    forcedInductionCoef = 1,
    intakeAirDensityCoef = 1,
    outputTorqueState = 1,
    outputAVState = 1,
    isDisabled = false,
    lastOutputAV1 = jbeamData.idleRPM * rpmToAV,
    lastOutputTorque = 0,
    loadSmoother = newTemporalSmoothing(2, 2),
    throttleSmoother = newTemporalSmoothing(15, 10),
    engineLoad = 0,
    instantEngineLoad = 0,
    ignitionCutTime = 0,
    slowIgnitionErrorCoef = 1,
    fastIgnitionErrorCoef = 1,
    instantAfterFireCoef = jbeamData.instantAfterFireCoef or 0,
    sustainedAfterFireCoef = jbeamData.sustainedAfterFireCoef or 0,
    sustainedAfterFireTimer = 0,
    sustainedAfterFireTime = jbeamData.sustainedAfterFireTime or 1.5,
    instantAfterFireFuel = 0,
    sustainedAfterFireFuel = 0,
    shiftAfterFireFuel = 0,
    continuousAfterFireFuel = 0,
    instantAfterFireFuelDelay = delayLine.new(0.1),
    sustainedAfterFireFuelDelay = delayLine.new(0.3),
    exhaustFlowDelay = delayLine.new(0.1),
    overRevDamage = 0,
    maxOverRevDamage = jbeamData.maxOverRevDamage or 1500,
    maxTorqueRating = jbeamData.maxTorqueRating or -1,
    overTorqueDamage = 0,
    maxOverTorqueDamage = jbeamData.maxOverTorqueDamage or 1000,
    engineWorkPerUpdate = 0,
    frictionLossPerUpdate = 0,
    pumpingLossPerUpdate = 0,
    spentEnergy = 0,
    spentEnergyNitrousOxide = 0,
    storageWithEnergyCounter = 0,
    registeredEnergyStorages = {},
    previousEnergyLevels = {},
    energyStorageRatios = {},
    hasFuel = true,
    remainingFuelRatio = 1,
    fixedStepTimer = 0,
    fixedStepTime = 1 / 100,
    --
    --wear/damage modifiers
    wearFrictionCoef = 1,
    damageFrictionCoef = 1,
    wearDynamicFrictionCoef = 1,
    damageDynamicFrictionCoef = 1,
    wearIdleAVReadErrorRangeCoef = 1,
    damageIdleAVReadErrorRangeCoef = 1,
    --
    --methods
    initSounds = engineFunctions.initSounds,
    resetSounds = engineFunctions.resetSounds,
    setExhaustGainMufflingOffset = engineFunctions.setExhaustGainMufflingOffset,
    setExhaustGainMufflingOffsetRevLimiter = engineFunctions.setExhaustGainMufflingOffsetRevLimiter,
    reset = reset,
    onBreak = engineFunctions.onBreak,
    beamBroke = engineFunctions.beamBroke,
    validate = engineFunctions.validate,
    calculateInertia = engineFunctions.calculateInertia,
    updateGFX = updateGFX,
    updateFixedStep = engineFunctions.updateFixedStep,
    updateSounds = nil,
    scaleFriction = engineFunctions.scaleFriction,
    scaleFrictionInitial = engineFunctions.scaleFrictionInitial,
    scaleOutputTorque = engineFunctions.scaleOutputTorque,
    activateStarter = engineFunctions.activateStarter,
    deactivateStarter = engineFunctions.deactivateStarter,
    sendTorqueData = sendTorqueData,
    getTorqueData = getTorqueData,
    checkHydroLocking = engineFunctions.checkHydroLocking,
    lockUp = engineFunctions.lockUp,
    disable = engineFunctions.disable,
    enable = engineFunctions.enable,
    setIgnition = engineFunctions.setIgnition,
    cutIgnition = engineFunctions.cutIgnition,
    setTempRevLimiter = engineFunctions.setTempRevLimiter,
    resetTempRevLimiter = engineFunctions.resetTempRevLimiter,
    updateFuelUsage = updateFuelUsage,
    updateEnergyStorageRatios = updateEnergyStorageRatios,
    registerStorage = engineFunctions.registerStorage,
    exhaustEndNodesChanged = engineFunctions.exhaustEndNodesChanged,
    initEngineSound = engineFunctions.initEngineSound,
    initExhaustSound = engineFunctions.initExhaustSound,
    setEngineSoundParameterList = engineFunctions.setEngineSoundParameterList,
    getSoundConfiguration = engineFunctions.getSoundConfiguration,
    applyDeformGroupDamage = engineFunctions.applyDeformGroupDamage,
    setPartCondition = engineFunctions.setPartCondition,
    getPartCondition = engineFunctions.getPartCondition,
  }
  
  --this code handles the requirement to support multiple output clutches
  --by default the engine has only one output, we need to know the number before building the tree, so it needs to be specified in jbeam
  device.numberOfOutputPorts = jbeamData.numberOfOutputPorts or 1
  device.outputPorts = {} --reset the defined outputports
  device.outputTorqueNames = {}
  device.outputAVNames = {}
  for i = 1, device.numberOfOutputPorts, 1 do
    device.outputPorts[i] = true --let powertrain know which outputports we support
    --cache the required output torque and AV property names for fast access
    device.outputTorqueNames[i] = "outputTorque" .. tostring(i)
    device.outputAVNames[i] = "outputAV" .. tostring(i)
    device[device.outputTorqueNames[i]] = 0
    device[device.outputAVNames[i]] = jbeamData.idleRPM * rpmToAV
  end
  
  device.initialFriction = device.friction
  device.engineBrakeTorque = jbeamData.engineBrakeTorque or device.friction * 2
  
  local torqueReactionNodes_nodes = jbeamData.torqueReactionNodes_nodes
  if torqueReactionNodes_nodes and type(torqueReactionNodes_nodes) == "table" then
    local hasValidReactioNodes = true
    for _, v in pairs(torqueReactionNodes_nodes) do
      if type(v) ~= "number" then
        hasValidReactioNodes = false
      end
    end
    if hasValidReactioNodes then
      device.torqueReactionNodes = torqueReactionNodes_nodes
    end
  end
  if not device.torqueReactionNodes then
    device.torqueReactionNodes = { -1, -1, -1 }
  end
  
  device.waterDamageNodes = jbeamData.waterDamage and jbeamData.waterDamage._engineGroup_nodes or {}
  
  device.canFlood = device.waterDamageNodes and type(device.waterDamageNodes) == "table" and #device.waterDamageNodes > 0
  
  device.maxPhysicalAV = (jbeamData.maxPhysicalRPM or (jbeamData.maxRPM * 1.05)) * rpmToAV --what the engine is physically capable of
  
  if not jbeamData.torque then
    log("E", "combustionEngine.init", "Can't find torque table... Powertrain is going to break!")
  end
  
  --   device.name = "mainEngine"
  --   dump(jbeamData)
  init(device, jbeamData)
  
  local tempBurnEfficiencyTable = nil
  if not jbeamData.burnEfficiency or type(jbeamData.burnEfficiency) == "number" then
    tempBurnEfficiencyTable = { { 0, jbeamData.burnEfficiency or 1 }, { 1, jbeamData.burnEfficiency or 1 } }
  elseif type(jbeamData.burnEfficiency) == "table" then
    tempBurnEfficiencyTable = deepcopy(jbeamData.burnEfficiency)
  end
  
  local copy = deepcopy(tempBurnEfficiencyTable)
  tempBurnEfficiencyTable = {}
  for k, v in pairs(copy) do
    if type(k) == "number" then
      table.insert(tempBurnEfficiencyTable, { v[1] * 100, v[2] })
    end
  end
  
  tempBurnEfficiencyTable = createCurve(tempBurnEfficiencyTable)
  device.invBurnEfficiencyTable = {}
  device.invBurnEfficiencyCoef = 1
  for k, v in pairs(tempBurnEfficiencyTable) do
    device.invBurnEfficiencyTable[k] = 1 / v
  end
  
  
  local baseTorqueTable = tableFromHeaderTable(jbeamData.torque)
  local rawBasePoints = {}
  local maxAvailableRPM = 0
  for _, v in pairs(baseTorqueTable) do
    maxAvailableRPM = max(maxAvailableRPM, v.rpm)
    
    -- table.insert(rawBasePoints, { v.rpm, v.torque })
    simEngine.sensors.RPM = v.rpm
    simEngine.sensors.TPS = 1
    -- simEngine.sensors.MAP = 102
    table.insert(rawBasePoints, { v.rpm, simEngine.simulateEngine(0.01, {RPM = v.rpm, throttle = 1, instantEngineLoad = 1}, true) })
  end
  local rawBaseCurve = createCurve(rawBasePoints)
  
  local rawTorqueMultCurve = {}
  if jbeamData.torqueModMult then
    local multTorqueTable = tableFromHeaderTable(jbeamData.torqueModMult)
    local rawTorqueMultPoints = {}
    for _, v in pairs(multTorqueTable) do
      maxAvailableRPM = max(maxAvailableRPM, v.rpm)
      table.insert(rawTorqueMultPoints, { v.rpm, v.torque })
    end
    rawTorqueMultCurve = createCurve(rawTorqueMultPoints)
  end
  
  local rawIntakeCurve = {}
  local lastRawIntakeValue = 0
  if jbeamData.torqueModIntake then
    local intakeTorqueTable = tableFromHeaderTable(jbeamData.torqueModIntake)
    local rawIntakePoints = {}
    for _, v in pairs(intakeTorqueTable) do
      maxAvailableRPM = max(maxAvailableRPM, v.rpm)
      table.insert(rawIntakePoints, { v.rpm, v.torque })
    end
    rawIntakeCurve = createCurve(rawIntakePoints)
    lastRawIntakeValue = rawIntakeCurve[#rawIntakeCurve]
  end
  
  local rawExhaustCurve = {}
  local lastRawExhaustValue = 0
  if jbeamData.torqueModExhaust then
    local exhaustTorqueTable = tableFromHeaderTable(jbeamData.torqueModExhaust)
    local rawExhaustPoints = {}
    for _, v in pairs(exhaustTorqueTable) do
      maxAvailableRPM = max(maxAvailableRPM, v.rpm)
      table.insert(rawExhaustPoints, { v.rpm, v.torque })
    end
    rawExhaustCurve = createCurve(rawExhaustPoints)
    lastRawExhaustValue = rawExhaustCurve[#rawExhaustCurve]
  end
  
  local rawCombinedCurve = {}
  for i = 0, maxAvailableRPM, 1 do
    local base = rawBaseCurve[i] or 0
    local baseMult = rawTorqueMultCurve[i] or 1
    local intake = rawIntakeCurve[i] or lastRawIntakeValue
    local exhaust = rawExhaustCurve[i] or lastRawExhaustValue
    rawCombinedCurve[i] = base * baseMult + intake + exhaust
  end
  
  device.maxAvailableRPM = maxAvailableRPM
  device.maxRPM = min(device.maxRPM, maxAvailableRPM)
  device.maxAV = min(device.maxAV, maxAvailableRPM * rpmToAV)
  
  device.applyRevLimiter = revLimiterDisabledMethod
  device.revLimiterActive = false
  device.revLimiterWasActiveTimer = 999
  device.hasRevLimiter = jbeamData.hasRevLimiter == nil and true or jbeamData.hasRevLimiter --TBD, default should be "no" rev limiter
  if device.hasRevLimiter then
    device.revLimiterType = jbeamData.revLimiterType or "rpmDrop" --alternatives: "timeBased", "soft"
    local revLimiterRPM = jbeamData.revLimiterRPM or device.maxRPM
    device.maxRPM = min(maxAvailableRPM, revLimiterRPM)
    device.maxAV = device.maxRPM * rpmToAV
    
    if device.revLimiterType == "rpmDrop" then --purely rpm drop based
      device.revLimiterAVDrop = (jbeamData.revLimiterRPMDrop or (jbeamData.maxRPM * 0.03)) * rpmToAV
      device.applyRevLimiter = revLimiterRPMDropMethod
    elseif device.revLimiterType == "timeBased" then --combined both time or rpm drop, whatever happens first
      device.revLimiterCutTime = jbeamData.revLimiterCutTime or 0.15
      device.revLimiterMaxAVDrop = (jbeamData.revLimiterMaxRPMDrop or 500) * rpmToAV
      device.revLimiterActiveTimer = 0
      device.applyRevLimiter = revLimiterTimeMethod
    elseif device.revLimiterType == "soft" then --soft limiter without any "drop", it just smoothly fades out throttle
      device.revLimiterMaxAVOvershoot = (jbeamData.revLimiterSmoothOvershootRPM or 50) * rpmToAV
      device.revLimiterMaxAV = device.maxAV + device.revLimiterMaxAVOvershoot
      device.invRevLimiterRange = 1 / (device.revLimiterMaxAV - device.maxAV)
      device.applyRevLimiter = revLimiterSoftMethod
    else
      log("E", "combustionEngine.init", "Unknown rev limiter type: " .. device.revLimiterType)
      log("E", "combustionEngine.init", "Rev limiter will be disabled!")
      device.hasRevLimiter = false
    end
    engineFunctions.applyRevLimiter = device.applyRevLimiter
  end
  
  device:resetTempRevLimiter()
  
  --cut off torque below a certain RPM to help stalling
  for i = 0, device.idleRPM * 0.3, 1 do
    rawCombinedCurve[i] = 0
  end
  
  local combinedTorquePoints = {}
  for i = 0, device.maxRPM, 1 do
    table.insert(combinedTorquePoints, { i, rawCombinedCurve[i] or 0 })
  end
  
  --past redline we want to gracefully reduce the torque for a natural redline
  device.redlineTorqueDropOffRange = clamp(jbeamData.redlineTorqueDropOffRange or 500, 10, device.maxRPM)
  
  --last usable torque value for a smooth transition to past-maxRPM-drop-off
  local rawMaxRPMTorque = rawCombinedCurve[device.maxRPM] or 0
  
  --create the drop off past the max rpm for a natural redline
  table.insert(combinedTorquePoints, { device.maxRPM + device.redlineTorqueDropOffRange * 0.5, rawMaxRPMTorque * 0.7 })
  table.insert(combinedTorquePoints, { device.maxRPM + device.redlineTorqueDropOffRange, rawMaxRPMTorque / 5 })
  table.insert(combinedTorquePoints, { device.maxRPM + device.redlineTorqueDropOffRange * 2, 0 })
  
  --actually create the final torque curve
  device.torqueCurve = createCurve(combinedTorquePoints)
  
  device.invEngInertia = 1 / device.inertia
  device.halfInvEngInertia = device.invEngInertia * 0.5
  
  local idleReadErrorRate = jbeamData.idleRPMRoughnessRate or device.idleAVReadErrorRange * 2
  device.idleAVReadErrorSmoother = newTemporalSmoothing(idleReadErrorRate, idleReadErrorRate)
  device.idleAVReadErrorRangeHalf = device.idleAVReadErrorRange * 0.5
  device.maxIdleAV = device.idleAV + device.idleAVReadErrorRangeHalf
  device.minIdleAV = device.idleAV - device.idleAVReadErrorRangeHalf
  
  local idleAVStartOffsetRate = jbeamData.idleRPMStartRate or 1
  device.idleAVStartOffsetSmoother = newTemporalSmoothingNonLinear(idleAVStartOffsetRate, 100)
  device.idleStartCoef = jbeamData.idleRPMStartCoef or 2
  
  device.idleTorque = device.torqueCurve[floor(device.idleRPM)] or 0
  
  --ignition error properties
  --slow
  device.slowIgnitionErrorSmoother = newTemporalSmoothing(2, 2)
  device.slowIgnitionErrorTimer = 0
  device.slowIgnitionErrorChance = 0.0
  device.slowIgnitionErrorInterval = 5
  device.slowIgnitionErrorCoef = 1
  --fast
  device.fastIgnitionErrorSmoother = newTemporalSmoothing(10, 10)
  device.fastIgnitionErrorChance = 0.0
  device.fastIgnitionErrorCoef = 1
  
  device.brakeSpecificFuelConsumption = 0
  
  -- local tempBurnEfficiencyTable = nil
  -- if not jbeamData.burnEfficiency or type(jbeamData.burnEfficiency) == "number" then
  --   tempBurnEfficiencyTable = { { 0, jbeamData.burnEfficiency or 1 }, { 1, jbeamData.burnEfficiency or 1 } }
  -- elseif type(jbeamData.burnEfficiency) == "table" then
  --   tempBurnEfficiencyTable = deepcopy(jbeamData.burnEfficiency)
  -- end
  
  -- local copy = deepcopy(tempBurnEfficiencyTable)
  -- tempBurnEfficiencyTable = {}
  -- for k, v in pairs(copy) do
  --   if type(k) == "number" then
  --     table.insert(tempBurnEfficiencyTable, { v[1] * 100, v[2] })
  --   end
  -- end
  
  -- tempBurnEfficiencyTable = createCurve(tempBurnEfficiencyTable)
  -- device.invBurnEfficiencyTable = {}
  -- device.invBurnEfficiencyCoef = 1
  -- for k, v in pairs(tempBurnEfficiencyTable) do
  --   device.invBurnEfficiencyTable[k] = 1 / v
  -- end
  
  device.requiredEnergyType = jbeamData.requiredEnergyType or "gasoline"
  device.energyStorage = jbeamData.energyStorage
  
  if device.torqueReactionNodes and #device.torqueReactionNodes == 3 and device.torqueReactionNodes[1] >= 0 then
    local pos1 = vec3(v.data.nodes[device.torqueReactionNodes[1]].pos)
    local pos2 = vec3(v.data.nodes[device.torqueReactionNodes[2]].pos)
    local pos3 = vec3(v.data.nodes[device.torqueReactionNodes[3]].pos)
    local avgPos = (((pos1 + pos2) / 2) + pos3) / 2
    device.visualPosition = { x = avgPos.x, y = avgPos.y, z = avgPos.z }
  end
  
  device.engineNodeID = device.torqueReactionNodes and (device.torqueReactionNodes[1] or v.data.refNodes[0].ref) or
  v.data.refNodes[0].ref
  if device.engineNodeID < 0 then
    log("W", "combustionEngine.init", "Can't find suitable engine node, using ref node instead!")
    device.engineNodeID = v.data.refNodes[0].ref
  end
  
  device.engineBlockNodes = {}
  if jbeamData.engineBlock and jbeamData.engineBlock._engineGroup_nodes and
  #jbeamData.engineBlock._engineGroup_nodes >= 2 then
    device.engineBlockNodes = jbeamData.engineBlock._engineGroup_nodes
  end
  
  --dump(jbeamData)
  
  local thermalsFileName = jbeamData.thermalsLuaFileName or "powertrain/combustionEngineThermals"
  device.thermals = require(thermalsFileName)
  device.thermals.init(device, jbeamData)

  if jbeamData.turbocharger and v.data[jbeamData.turbocharger] then
    local turbochargerFileName = jbeamData.turbochargerLuaFileName or "powertrain/turbocharger"
    device.turbocharger = require(turbochargerFileName)
    device.turbocharger.init(device, v.data[jbeamData.turbocharger])
  else
    device.turbocharger = { reset = nop, updateGFX = nop, updateFixedStep = nop, updateSounds = nop, initSounds = nop,
    resetSounds = nop, getPartCondition = nop, isExisting = false }
  end
  
  if jbeamData.supercharger and v.data[jbeamData.supercharger] then
    local superchargerFileName = jbeamData.superchargerLuaFileName or "powertrain/supercharger"
    device.supercharger = require(superchargerFileName)
    device.supercharger.init(device, v.data[jbeamData.supercharger])
  else
    device.supercharger = { reset = nop, updateGFX = nop, updateFixedStep = nop, updateSounds = nop, initSounds = nop,
    resetSounds = nop, getPartCondition = nop, isExisting = false }
  end
  
  if jbeamData.nitrousOxideInjection and v.data[jbeamData.nitrousOxideInjection] then
    local nitrousOxideFileName = jbeamData.nitrousOxideLuaFileName or "powertrain/nitrousOxideInjection"
    device.nitrousOxideInjection = require(nitrousOxideFileName)
    device.nitrousOxideInjection.init(device, v.data[jbeamData.nitrousOxideInjection])
  else
    device.nitrousOxideInjection = { reset = nop, updateGFX = nop, updateSounds = nop, initSounds = nop,
    resetSounds = nop, registerStorage = nop, getAddedTorque = nop, getPartCondition = nop, isExisting = false }
  end

  device.torqueData = getTorqueData(device)
  device.maxPower = device.torqueData.maxPower
  device.maxTorque = device.torqueData.maxTorque
  device.maxPowerThrottleMap = device.torqueData.maxPower * psToWatt
  
  device.breakTriggerBeam = jbeamData.breakTriggerBeam
  if device.breakTriggerBeam and device.breakTriggerBeam == "" then
    --get rid of the break beam if it's just an empty string (cancellation)
    device.breakTriggerBeam = nil
  end
  
  damageTracker.setDamage("engine", "engineDisabled", false)
  damageTracker.setDamage("engine", "engineLockedUp", false)
  damageTracker.setDamage("engine", "engineReducedTorque", false)
  damageTracker.setDamage("engine", "catastrophicOverrevDamage", false)
  damageTracker.setDamage("engine", "mildOverrevDamage", false)
  damageTracker.setDamage("engine", "catastrophicOverTorqueDamage", false)
  damageTracker.setDamage("engine", "mildOverTorqueDamage", false)
  damageTracker.setDamage("engine", "engineHydrolocked", false)
  damageTracker.setDamage("engine", "engineIsHydrolocking", false)
  damageTracker.setDamage("engine", "impactDamage", false)
  
  selectUpdates(device)
  
  return device
end

M.new = new

--local command = "obj:queueGameEngineLua(string.format('scenarios.getScenario().wheelDataCallback(%s)', serialize({wheels.wheels[0].absActive, wheels.wheels[0].angularVelocity, wheels.wheels[0].angularVelocityBrakeCouple}))"

return M

--------------------------------------------------------------------------
