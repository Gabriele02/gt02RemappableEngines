local M = {}
local delayLine = require("delayLine")
local fuel_lines_delay_line = nil
-- todo: find lore friendly names
local pressure_vs_flow = {
    walbro_255lph = {
        flow_data = {
            --{lph, psi}
            {0, 100}, --made up
            {121, 100},
            {142, 95},
            {163, 90},
            {178, 85},
            {203, 75},
            {212, 70},
            {222, 65},
            {231, 60},
            {239, 55},
            {246, 50},
            {255, 45},
            {265, 40},
            {271, 35},
            {193, 80},
            {276, 30},
            {400, 5}, --made up
        },
        max_pressure = {1, 100}, --{lph@psi}
        min_pressure = {400, 5}, --{lph@psi}
    },
}
local selected_pump_pressure_per_flow = nil
local pressure_range = {{}, {}} --{lph@psi}
local randomness = 0
local function init(data, state)
    local fuel_pump_data = data.fuelSystemMeasurements.fuelPump.flow_data
    randomness = 1 - data.fuelSystemMeasurements.fuelPump.quality

    pressure_range = {fuel_pump_data[1], fuel_pump_data[#fuel_pump_data]}
    selected_pump_pressure_per_flow = createCurve(fuel_pump_data, true)
    fuel_lines_delay_line = delayLine.new(0.1)

    return state
end

local function update(state, dt)
    local lookup_index = math.ceil(clamp(state.fuelSystem.flow_l_h, 0, pressure_range[2][1]))
    local rand_factor = math.random(1 - randomness, 1 + randomness)
    --TODO: CHECK
    if lookup_index < pressure_range[1][1] then
        lookup_index = pressure_range[1][1]
    elseif lookup_index > pressure_range[2][1] then
        lookup_index = pressure_range[2][1]
        rand_factor = math.random(0.85, 0.95)
    end

    local fuel_line_pressure_psi = selected_pump_pressure_per_flow[lookup_index] * rand_factor
    fuel_lines_delay_line:push(fuel_line_pressure_psi)
    local delayed = fuel_lines_delay_line:pop(dt)
    fuel_line_pressure_psi = delayed[#delayed] or fuel_line_pressure_psi

    state.fuelSystem.fuel_lines_pressure_bar = fuel_line_pressure_psi / 14.7 --[[psi to bar]]
end

M.init = init
M.update = update
return M