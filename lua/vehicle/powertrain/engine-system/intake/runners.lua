local M = {}
--[[
    idee:
    http://www.exx.se/techinfo/runners/runners.html
    https://www.thirdgen.org/forums/tpi/183201-equations-runner-length-runner.html#post1334232
]]
local injector = require("vehicle.powertrain.engine-system.actuators.injectors")
local variableDelayLine = require("vehicle.powertrain.engine-system.commons.variableDelayLine")
local condensedFuelDelayLine = nil
local combustionEngine = nil
local engineMeasurements = nil
local intakeMeasurements = nil
local variableRunnersLengthSmmother = nil

-- condensed fuel on the runners walls (mg)
local totalCondensedFuel_mg = 0
--[[idee:
    http://www.exx.se/techinfo/runners/runners.html
    https://www.thirdgen.org/forums/tpi/183201-equations-runner-length-runner.html#post1334232
]]
--[[
    https://www.engineeringtoolbox.com/methanol-properties-d_1209.html
    temp(C)    Latent Heat of Vaporization (kJ/kg) of methanol
    -50, 1194
    -30, 1187
    -10, 1182
    10, 1175
    30, 1155
    50, 1125
    70, 1085
    90, 1035
    110, 980
    130, 920
    150, 850

    https://www.engineeringtoolbox.com/fluids-evaporation-latent-heat-d_147.html
    ethanol 846
    gasoline 305
]]
--[[
local function check_multiple(to_check, number, multiple_ind)
    local multiple = number * multiple_ind
    local submultiple = number / multiple_ind
    local thightness = to_check / 8
    if to_check > (multiple - thightness) and to_check < (multiple + thightness) then
        return multiple
    end
    if to_check > (submultiple - thightness) and to_check < (submultiple + thightness) then
        return submultiple
    end
    return -1
    end
]]

local function init(data, state)
    combustionEngine = data.combustionEngine
    engineMeasurements = data.engineMeasurements
    intakeMeasurements = data.intakeMeasurements

    -- always assume circular runners
    intakeMeasurements.runners.cross_section_area_cm2 = math.pi * (intakeMeasurements.runners.diameter_cm / 2) ^ 2

    condensedFuelDelayLine = variableDelayLine.new()
    
    -- higher inRate: slower filter
    -- higer outRate: slower filter
    variableRunnersLengthSmmother = newTemporalSmoothing(2, 2)

    state = injector.init(data, state)

    return state
end

local function update(state, dt) -- -> modifyed state
    
    -- METHOD 1: but based on a made up function r(x)
    --[[
        -- https://www.researchgate.net/publication/287040569_Effect_of_Variable_Length_Intake_Manifold_on_a_Turbocharged_Multi-Cylinder_Diesel_Engine
        local c = 20.05 * math.sqrt(state.manifold.IAT) -- speed of sound in air [m/s]

        local fn = (c / (2 * math.pi)) * math.sqrt(s / (l * v))

        -- fn: runners natural frequency
        -- c: speed of sound
        -- s: cross section area of the runners
        -- l: length of the runners (actual parameter would be Leq (equivalent length) but circular runners are assumed so Leq = l)
        -- v: mean cylinder volume // cylinder volume for now

    
        a = 0.5
        l(x)=((8 a^(3))/((x-0.5 fn)^(2)+4 a^(2)))
        f(x)=sin(((x)/(0.5 fn)))
        r(x)=((f(x)+2 l(x))/(30))
    ]]

    -- METHOD 2:
    -- https://www.enginebasics.com/Advanced%20Engine%20Tuning/Intake%20Runner%20Length.html
    if false then
        local IVOT = 250 --[[deg]] -- intake valve open time
        local RPM = state.RPM
        local c = 20.05 * math.sqrt(state.manifold.IAT) -- speed of sound in air [m/s]
        local needed_round_trip_time = ((720 - IVOT) / 360) * ((1 / (state.RPM / 60))) --[[s]]
        local needed_round_trip_length = c * needed_round_trip_time --[[m]]
        local optimal_runners_length = 0.5 * needed_round_trip_length --[[m]]
        print("optimal_runners_length: " .. optimal_runners_length .. "m @ " .. RPM .. "RPM")
        
        -- all runners are assumed to have the same length
        -- the first 10 multiples or submultiples of the optimal length are assumed valid
        --local runners_length = 2.66 / 12 --optimized for 5000 RPM, 22.2cm runners, 12 pulses --state.manifold.runners.length
        local runners_length = math.max(math.min(optimal_runners_length / 12, 0.4), 0.2) --optimized for every RPM, variable length runners, 12 pulses

        -- check if runners length is in range of +-0.5 to a multiple or submultiple of the optimal length
        local harmonic = 1
        local closest = -1
        local closest1 = check_multiple(runners_length, optimal_runners_length, 1)
        for i = 2, 200, 2 do
            closest = check_multiple(runners_length, optimal_runners_length, i)
            if math.abs(closest1 - runners_length) < math.abs(closest - runners_length) then
                closest = closest1
                break
            end
            if closest ~= -1 then
                break
            end
            harmonic = i
        end
        local diff = math.abs(closest - runners_length)

        -- runners eff.
        local runners_efficiency = -math.log10(math.max(diff + 100^-1, 0.000001)) / math.log10(100) * math.min(12 / harmonic, 1)
        --runners_efficiency = runnersEfficiencySmmother:getUncapped(runners_efficiency, dt)
        if runners_efficiency < 0 or runners_efficiency ~= runners_efficiency then
            runners_efficiency = 0
        end
        print("runners_efficiency: " .. runners_efficiency)
    end
    if intakeMeasurements.runners.type == "fixed" then
        state.manifold.runners.length = intakeMeasurements.runners.fixed.length_cm
    elseif intakeMeasurements.runners.type == "variable" then
        local target_length = state.manifold.runners.variable.target_length_cm
        state.manifold.runners.length = math.max(
            math.min(
                state.torqueCurveCreation and target_length or variableRunnersLengthSmmother:getUncapped(target_length, dt),
                intakeMeasurements.runners.variable.max_length_cm
            ),
            intakeMeasurements.runners.variable.min_length_cm
        ) --TODO: use a PID controller
        print("target_length: " .. target_length .. "cm, actual_length: " .. state.manifold.runners.length .. "cm")
    end
    local c = 20.05 * math.sqrt(state.manifold.IAT) -- speed of sound in air [m/s]
    local v = engineMeasurements.displacement_cc * 1.0e-6 --[[cm^3 to m^3]] / engineMeasurements.num_cylinders
    local s = intakeMeasurements.runners.cross_section_area_cm2 * 1.0e-4 --[[cm^2 to m^2]]
    local l = state.manifold.runners.length * 1.0e-2 --[[cm to m]]
    local fn = (c / (2 * math.pi)) * math.sqrt(s / (l * v)) --[[Hz]]

    -- fn: runners natural frequency
    -- c: speed of sound
    -- s: cross section area of the runners
    -- l: length of the runners (actual parameter would be Leq (equivalent length) but circular runners are assumed so Leq = l)
    -- v: mean cylinder volume // cylinder volume for now

    local max_eff = 0.1
    local max_eff_rpm = fn * 60 --[[Hz to RPM]]
    local eff_range = 1000
    local r = 
            --   max_eff / 1.4 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 4000)^2) / (2 * (eff_range / 4000)^2))
            --[[+]] max_eff / 1.2 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 2000)^2) / (2 * (eff_range / 2000)^2))
            + max_eff     * math.exp(-((state.RPM / 1000 - max_eff_rpm / 1000)^2) / (2 * (eff_range / 1000)^2))
            -- + max_eff / 1.2 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 500 )^2) / (2 * (eff_range / 500 )^2))
            -- + max_eff / 1.4 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 250 )^2) / (2 * (eff_range / 250 )^2))

            - max_eff / 1.8 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 3000)^2) / (2 * (eff_range / 3000)^2))
            -- - max_eff / 1.4 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 1500)^2) / (2 * (eff_range / 1500)^2))

            -- - max_eff / 2 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 500 )^2) / (2 * (eff_range / 500 )^2))
            -- - max_eff / 4 * math.exp(-((state.RPM / 1000 - max_eff_rpm / 250 )^2) / (2 * (eff_range / 250 )^2))
    local runners_efficiency = r

    state.manifold.MAF = state.manifold.MAF * (1 + runners_efficiency)
    state.volumetric_efficiency = (state.volumetric_efficiency or 0) * (1 + runners_efficiency)
    state.manifold.runners.massAirflowIntoCylinder = state.manifold.MAF
    
    -- Fuel injection (port injection)
    if state.injectionType == "port" then
        injector.update(state, dt)
        local actual_fuel_mg_per_combustion = state.manifold.runners.injectors.fuel_mg_per_combustion

        --TODO: get actual data to model fuel condensation to the intake manifold
        if false and combustionEngine.thermals and not state.torqueCurveCreation then
            local coolantTemperature = combustionEngine.thermals.coolantTemperature
            local condensation_factor = 0
            if coolantTemperature < 0 then
                condensation_factor = 0.6 - (coolantTemperature / 150)
            else
                condensation_factor = -(math.log(coolantTemperature + 10 ^ 1.4) / math.log(10)) + 2
            end
            condensation_factor = math.max(math.min(condensation_factor, 0.95), 0)
            print("condensation_factor: " .. totalCondensedFuel_mg)
            -- local condensed_fuel = actual_fuel_mg_per_combustion * condensation_factor
            -- actual_fuel_mg_per_combustion = actual_fuel_mg_per_combustion * (1 - condensation_factor)
            local condensed_fuel_mg_per_combustion = actual_fuel_mg_per_combustion * condensation_factor --* state.combustionsPerSecond * dt
            totalCondensedFuel_mg = totalCondensedFuel_mg + (condensed_fuel_mg_per_combustion * state.combustionsPerSecond * dt)

            -- simulate condensed fuel dripping in the cylinder
            local drip_mg_per_combustion = 0
            if totalCondensedFuel_mg > 0 then
                -- drip factor depends on coolant temperature and total condensed fuel
                -- as the temperature increases, the drip factor increases
                -- as the total condensed fuel increases, the drip factor increases
                local drip_factor = 0
                if coolantTemperature < 0 then
                    drip_factor = 0.001
                else
                    drip_factor = 80 / coolantTemperature
                end

                drip_factor = drip_factor * (totalCondensedFuel_mg / 1000) * 0.1

                drip_factor = drip_factor * (math.random(100, 200) / 100)
                
                drip_mg_per_combustion = totalCondensedFuel_mg * drip_factor
                totalCondensedFuel_mg = totalCondensedFuel_mg - (drip_mg_per_combustion * state.combustionsPerSecond * dt)
            end

            actual_fuel_mg_per_combustion = actual_fuel_mg_per_combustion - condensed_fuel_mg_per_combustion + drip_mg_per_combustion

        end

        if combustionEngine.thermals and not state.torqueCurveCreation then
            local coolantTemperature = combustionEngine.thermals.coolantTemperature
            local condensation_factor = 0
            if coolantTemperature < 0 then
                condensation_factor = 0.6 - (coolantTemperature / 150)
            else
                condensation_factor = -(math.log(coolantTemperature + 10 ^ 1.4) / math.log(10)) + 2
            end
            condensation_factor = math.max(math.min(condensation_factor, 0.95), 0) * (1 + math.random(-0.2, 0.2))
            local condensed_fuel_mg_per_combustion = actual_fuel_mg_per_combustion * condensation_factor
            condensed_fuel_mg_per_combustion = math.max(condensed_fuel_mg_per_combustion, 0)
            --TODO: maybe the delay line gets too big after a while and slows the simulation down
            condensedFuelDelayLine:push(condensed_fuel_mg_per_combustion, condensation_factor)
            
            -- simulate condensed fuel dripping in the cylinder
            -- drip factor depends on coolant temperature and total condensed fuel
            -- as the temperature increases, the drip factor increases
            -- as the total condensed fuel increases, the drip factor increases
            local drip_factor = 0
            if coolantTemperature < 0 then
                drip_factor = 0.001
            else
                drip_factor = 80 / coolantTemperature
            end

            local drip_mg_per_combustion = (condensedFuelDelayLine:popSum(dt) or 0)
            drip_factor = drip_factor * (drip_mg_per_combustion / 500)
            drip_factor = drip_factor * (1 + math.random(-0.2, 0.2))

            drip_factor = math.max(math.min(drip_factor, 1), 0)

            drip_mg_per_combustion = drip_mg_per_combustion * drip_factor
            drip_mg_per_combustion = math.max(drip_mg_per_combustion, 0)
            
            --print("condensation_factor: " .. condensation_factor .. ", condensed_fuel_mg_per_combustion: " .. condensed_fuel_mg_per_combustion .. " drip_mg_per_combustion: " .. drip_mg_per_combustion .. " drip_factor: " .. drip_factor)

            actual_fuel_mg_per_combustion = math.max(actual_fuel_mg_per_combustion - condensed_fuel_mg_per_combustion + drip_mg_per_combustion, 0)
            -- calculate IAT temperature drop from fuel heat of vaporization 
            -- https://www.google.com/amp/s/www.engineeringtoolbox.com/amp/methanol-properties-d_1209.html
            local heat_of_vaporization = 305 --[[kJ/Kg]]
            local heat_of_vaporization_j_mg = heat_of_vaporization / 1000 --[[J/mg]]
            local required_energy = actual_fuel_mg_per_combustion * heat_of_vaporization_j_mg --[[J]]
            -- energy is subtracted from the intake air temperature
            local IAT_c = intakeMeasurements.IAT - 273.15 --[[ºK to ºC]]
            IAT_c = IAT_c + (
                - required_energy
            ) * 1005 --[[J/(kg*K)]] * dt
            
            state.manifold.runners.air_mass_temp_k = IAT_c + 273.15 
            --print("Runners_c: " .. state.manifold.runners.air_mass_temp_k - 273.15)
            
        end
        state.manifold.runners.air_fuel_ratio = state.manifold.runners.massAirflowIntoCylinder / actual_fuel_mg_per_combustion
        -- if state.manifold.runners.air_fuel_ratio < 9 or state.manifold.runners.air_fuel_ratio > 16 then
            -- state.manifold.runners.air_fuel_ratio = 12.8
        -- end
        --TODO: maybe it is possible to use a delay line to simulate the time it takes for the fuel to get from the injector to the cylinder
        -- and then simulate IVO/IVC/overlap injection with an injection angle map
    end
    --state.manifold.runners.air_fuel_ratio = 12.2
    --return state
end

local function reset()
end

M.init = init
M.update = update
M.reset = reset
return M