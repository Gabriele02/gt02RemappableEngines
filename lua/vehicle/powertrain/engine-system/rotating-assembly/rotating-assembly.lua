local M = {}
local combustionEngine = nil
local avToRPM = 9.549296596425384
local rpmToAV = 0.104719755
function init(data, state)
    combustionEngine = data.combustionEngine
    return state
end

function update(state, dt) -- -> modifyed state
    if TuningCheatOverwrite and RpmOverwrite ~= nil and MapOverwrite ~= nil then
      state.RPM = RpmOverwrite
      state.AV = state.RPM * rpmToAV
      state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]
    end
    if not state.torqueCurveCreation then
        state.RPM = combustionEngine.outputAV1 * avToRPM
        state.AV = combustionEngine.outputAV1
    else
        state.AV = state.RPM * rpmToAV
    end
    state.combustionsPerSecond = state.RPM / 60 --[[RPM to RPS]] / 2 --[[4 stroke engine]]
    state.torque = state.combustionTorque --TODO: add torque from rotating assembly
    -- return state
end

M.init = init
M.update = update
return M