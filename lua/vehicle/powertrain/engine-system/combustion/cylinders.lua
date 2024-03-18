local M = {}

local prob = require("vehicle.powertrain.engine-system.commons.probability")

local afr_power_curve_points = nil
local afr_power_curve = nil

local fuel_burn_speed_points = nil
local fuel_burn_speed_curve = nil

local map_factor_points = nil
local map_factor_curve = nil

local engineMeasurements = nil
local combustionEngine = nil

local conversions = {
    cm_to_feet = 0.0328084,
    cm_to_in = 0.393701,
    cm2_to_in2 = 0.1550003,
    cc_min_to_lb_h = 0.132277357,
    bar_to_psi = 14.7,
    bar_to_pa = 100000,
    inf = 1 / 0
}

local timing = {
    base_adv_deg = 0, -- calc

    quench_adv_deg = 22, -- 33 open chamber / 28 2 valve closed chamber w optimized quench / 22 3-4 valve w shirl and tumble
    fuel_adv_deg = 0, -- -2 87oct / -1 91-92 oct / 0 94+oct / 2 E85
    compression_ratio_adv_deg = 1, -- 2 cr < 9.0 / 1 9.1 < cr < 10.0 / 0 10.1 < cr < 11.5 / -2 cr > 11.6
    per_kpa_adv_deg = -0.3
}
local initialAfterfire = {
    sustainedAfterFireCoef = 0,
    sustainedAfterFireFuelDelay = 0,
    sustainedAfterFireTimer = 0,
    instantAfterFireCoef = 0,
    instantAfterFireFuelDelay = 0,
    instantAfterFireTimer = 0,
}

local misfire_probability = 0
local misfire_timer = 0
local fuel_misfire = 0

local function init(data, state)
    
    engineMeasurements = data.engineMeasurements
    combustionEngine = data.combustionEngine

    afr_power_curve_points = {
        { 30, 0 },
        { 40, 0 },
        { 50, 0 },
        { 60, 0.5 },
        { 90, 0.8 },
        { 115, 0.95 },
        { 122, 1 },
        { 133, 0.95 },
        { 147, 0.87 },
        { 155, 0.76 },
        { 165, 0.62 },
        { 180, 0.45 },
        { 220, 0.23 },
        { 250, 0 },
        { 260, 0 },
        { 270, 0 },
    }
    afr_power_curve = createCurve(afr_power_curve_points, true)

    fuel_burn_speed_points = {
        { 30, 0 },
        { 40, 0 },
        { 50, 0 },
        { 60, 0.025 },
        { 70, 0.05 },
        { 80, 0.1 },
        { 95, 0.35 },
        { 102, 0.529411764705882 },
        { 117, 0.741176470588235 },
        { 132, 0.882352941176471 },
        { 147, 1 },
        { 161, 1.03529411764706 },
        { 176, 0.988235294117647 },
        { 191, 0.870588235294118 },
        { 200, 0.8 },
        { 210, 0.69 },
        { 220, 0.51 },
        { 230, 0.3 },
        { 250, 0.05 },
        { 260, 0.025 },
        { 270, 0 },
    }
    fuel_burn_speed_curve = createCurve(fuel_burn_speed_points, true)

    map_factor_points = {
        {0, 0},
        {20, 0.08},
        {30, 0.18},
        {40, 0.32},
        {50, 0.5},
        {60, 0.6},
        {70, 0.7},
        {80, 0.8},
        {90, 0.9},
        {100, 1},
    }
    map_factor_curve = createCurve(map_factor_points, true)

    initialAfterfire.sustainedAfterFireCoef = combustionEngine.sustainedAfterFireCoef
    initialAfterfire.sustainedAfterFireFuelDelay = combustionEngine.sustainedAfterFireFuelDelay
    initialAfterfire.sustainedAfterFireTimer = combustionEngine.sustainedAfterFireTimer
    initialAfterfire.instantAfterFireCoef = combustionEngine.instantAfterFireCoef
    initialAfterfire.instantAfterFireFuelDelay = combustionEngine.instantAfterFireFuelDelay
    initialAfterfire.instantAfterFireTimer = combustionEngine.instantAfterFireTimer
    return state
end
local tick = 0	
local function update(state, dt) -- -> modifyed state 
    tick = tick + 1   
    if tick > 100000 then
        tick = 0
    end	
    local air_fuel_ratio = state.manifold.runners.air_fuel_ratio
    local fuel_burn_speed = math.max(fuel_burn_speed_curve[math.max(math.min(math.floor(air_fuel_ratio * 10), 270), 0)] or 1, 0)
    local fuel_burn_duration_deg
    local detonationFactor = 1
    local torque = 0
    local max_pressure_point_dATDC
    if fuel_burn_speed >= 0 then
        -- simulate misfire
        if (air_fuel_ratio > 17 or air_fuel_ratio < 9 or state.RPM < 700) and not state.torqueCurveCreation then
            if air_fuel_ratio > 17 then
                misfire_probability = (air_fuel_ratio / 23) * (state.manifold.MAP / 100) * dt
                local damage_probability = (air_fuel_ratio / 25) ^ 9 * (state.manifold.MAP / 1000) * dt
                if air_fuel_ratio < 25 and math.random() < damage_probability then
                    combustionEngine:scaleOutputTorque(1 - (damage_probability * 100000))
                    --misfire_timer = 0.8 * math.random()
                    combustionEngine.instantAfterFireFuelDelay:push(10000000000000)
                    if combustionEngine.outputTorqueState < 0.2 then
                        combustionEngine:lockUp()
                    end
                end
            end
            if air_fuel_ratio < 9 then
                misfire_probability = 4 / air_fuel_ratio * state.instantEngineLoad * dt
            end
            if state.RPM < 300 then
                misfire_probability = 0.8
            elseif state.RPM < 400 then
                misfire_probability = 0.5
            elseif state.RPM < 500 then
                misfire_probability = 0.35
            elseif state.RPM < 600 then
                misfire_probability = 0.25--misfire_probability * (2 + (1250 - state.RPM) / 1250)
            end
            misfire_probability = math.max(math.min(misfire_probability, 1), 0)
        else
            -- misfire_timer = 0
            misfire_probability = 0.0001
        end

        --old
        -- fuel_burn_duration_deg = ((20 * (engineMeasurements.stroke_cm / 8.2) / ((((state.manifold.MAP + 103) / 100) ^ 0.4))) *
        --     ((state.RPM + 1800) / 3600) ^ 0.8) / fuel_burn_speed

        --new
        local total_adv = (engineMeasurements.bore_cm * 2.54 --[[cm to in]] / 4.000)
        total_adv = total_adv * 6.0;
        total_adv = total_adv + timing.quench_adv_deg + timing.fuel_adv_deg + timing.compression_ratio_adv_deg
        local total_adv_at_100kpa = total_adv

        total_adv = math.max(total_adv + timing.per_kpa_adv_deg * (state.manifold.MAP - 100), 0.5 * total_adv_at_100kpa)
        total_adv = math.min(total_adv, 1.25 * total_adv_at_100kpa) --TODO: FIX

        timing.base_adv_deg = total_adv

        fuel_burn_duration_deg =   
            total_adv
            -- * math.max(((100 - (100 - state.manifold.MAP ) * (-0.1)) / 100), 0.5)
            * ((7200 - (7200 - state.RPM ) * (0.3)) / 7200)
        -- https://www.researchgate.net/publication/281456259_Flame_Propagation_of_Bio-Ethanol_in_a_Constant_Volume_Combustion_Chamber
        -- TODO: forse è meglio usare il metodo indicato al link sopra
        -- if state.manifold.IAT > (50 + 273.15) then
        --     fuel_burn_duration_deg = fuel_burn_duration_deg * math.min(1, (50 + 273.15) / (state.manifold.IAT ^ 2))
        --     print("IAT: " .. state.manifold.IAT .. " fuel_burn_duration_deg: " .. fuel_burn_duration_deg)
        -- end
        max_pressure_point_dATDC = -state.ADV + fuel_burn_duration_deg
        state.max_pressure_point_dATDC = max_pressure_point_dATDC
        -- simulate knock damage
        if max_pressure_point_dATDC < 0 or state.manifold.runners.air_mass_temp_k > (50 + 273.15) then
            local IATdetonationFactor = math.min(0.33 * (state.manifold.runners.air_mass_temp_k / (100 + 273.15)) ^ 4 + 0.64 * (-(max_pressure_point_dATDC / 12) + 1) , 1)
            --print((0.5 * (state.manifold.runners.air_mass_temp_k / (100 + 273.15)) ^ 4) .. ", "..(0.5 * (-(max_pressure_point_dATDC / 12) + 1)))
            if math.random() < IATdetonationFactor and not state.torqueCurveCreation then
                -- combustionEngine:lockUp()
                max_pressure_point_dATDC = -10 * IATdetonationFactor
                print("IATdetonationFactor: " .. IATdetonationFactor .. " max_pressure_point_dATDC: " .. max_pressure_point_dATDC)
            end
            -- print("KNOCK KNOCK")
            --TODO: spostare in rotating-assembly
            if max_pressure_point_dATDC < 0 then
                detonationFactor = math.min(math.max(1 - math.abs(max_pressure_point_dATDC / fuel_burn_duration_deg), 0), 1)
                print("detonationFactor: " .. detonationFactor)
                if math.random() < math.abs(max_pressure_point_dATDC / 20) ^ 5 and not state.torqueCurveCreation then
                    combustionEngine:lockUp()
                    print("IATdetonationFactor: " .. IATdetonationFactor .. " max_pressure_point_dATDC: " .. max_pressure_point_dATDC)
                end
            else
                detonationFactor = 1
            end
        end
        state.knockSensor = max_pressure_point_dATDC < 0 -- TODO: impostare con sensibilità del sensore di detonazione

        local map_factor = state.manifold.MAP / 100
        if state.manifold.MAP > 0 and state.manifold.MAP < 100 then
            map_factor = map_factor_curve[math.max(math.min(math.floor(state.manifold.MAP), 100), 0)] or 0
        end

        local combustion_pressure = engineMeasurements.compression_ratio * (5 * map_factor * (combustionEngine.ignitionCutTime > 0 and 0 or 1))  --[[5 is to simulate combustion gasses volume expansion]]

        -- Simulate effect of combustion timing
        
        --[[combustion_pressure = combustion_pressure + max_pressure_point_dATDC * (
        -2
        + 3 / (1 + math.exp(-max_pressure_point_dATDC)) -- too soon --> knock and less power
        + 2 / (1 + math.exp(-(max_pressure_point_dATDC - 10))) -- sooner than optimal: less power
        - 2 / (1 + math.exp(-(max_pressure_point_dATDC - 30))) -- just right ;)
        - 1 / (1 + math.exp(-(max_pressure_point_dATDC - 45))) -- too late: less power
        )]]
        if max_pressure_point_dATDC >= 15 then
            combustion_pressure = combustion_pressure * math.max(math.min((-(0.025 * max_pressure_point_dATDC - 0.375) ^ 2 + 1), 1), 0)
        else    
            combustion_pressure = combustion_pressure * math.max(math.min((-(0.05 * max_pressure_point_dATDC - 0.75) ^ 2 + 1), 1), -1)
        end

        if max_pressure_point_dATDC >= 30 and state.RPM > 2 * combustionEngine.idleRPM and not (max_pressure_point_dATDC == conversions.inf or max_pressure_point_dATDC == -conversions.inf) then
            combustionEngine.sustainedAfterFireCoef = 100 * max_pressure_point_dATDC
            combustionEngine.sustainedAfterFireTimer = 10 * max_pressure_point_dATDC
            local factor = 1--math.min(max_pressure_point_dATDC / 90, 1)
            combustionEngine.instantAfterFireCoef = 10000 * factor --* math.random()
            local fuel_to_push = math.max(state.manifold.runners.injectors.fuel_mg_per_combustion - (state.manifold.MAF / 14.7), 0)
            --print("AFTERFIRE: " .. fuel_to_push)
            combustionEngine.instantAfterFireFuelDelay:push(fuel_to_push * 10000) -- math.random())

            combustionEngine.instantAfterFireTimer = factor *1000 --* math.random()
        else
            combustionEngine.sustainedAfterFireCoef = initialAfterfire.sustainedAfterFireCoef
            combustionEngine.sustainedAfterFireFuelDelay = initialAfterfire.sustainedAfterFireFuelDelay
            combustionEngine.sustainedAfterFireTimer = initialAfterfire.sustainedAfterFireTimer
            combustionEngine.instantAfterFireCoef = initialAfterfire.instantAfterFireCoef
            combustionEngine.instantAfterFireFuelDelay = initialAfterfire.instantAfterFireFuelDelay
            combustionEngine.instantAfterFireTimer = initialAfterfire.instantAfterFireTimer
        end
        
        if misfire_timer <= 0 and math.random() < misfire_probability and not state.torqueCurveCreation then
            misfire_timer = (1 / (state.RPM / 60)) / engineMeasurements.num_cylinders
            -- limit misfire timer
            misfire_timer = math.min(misfire_timer, 0.05) -- 1 second	
        --   misfire_timer = 0.25 * misfire_probability / dt
          -- print("MISFIRE: " .. air_fuel_ratio .. ', misfire_probability: ' .. (misfire_probability / dt))
        end
    
        if misfire_timer > 0 and state.RPM > 0 and not state.torqueCurveCreation then
          fuel_misfire = math.random(1, engineMeasurements.num_cylinders) / engineMeasurements.num_cylinders * (1 + misfire_probability)
          fuel_misfire = math.max(math.min(fuel_misfire, 1), 0)
          misfire_timer = misfire_timer - dt
          ffi.C.bng_applyTorqueAxisCouple(
                ffiObjPtr,
                --math.random(-500, 500) * 10,
                (prob.gaussian(0, 1 * (1 + state.engineLoad))) / dt, 
                combustionEngine.torqueReactionNodes[1],
                combustionEngine.torqueReactionNodes[2],
                combustionEngine.torqueReactionNodes[3]
            )
        else
            fuel_misfire = 0
        end
        if fuel_misfire > 0 then
            combustion_pressure = combustion_pressure * (1 - fuel_misfire)
            -- print(
            --     "MISFIRE: " .. misfire_probability
            --     .. ', fuel_misfire: ' .. fuel_misfire
            --     .. ', misfire_timer: ' .. misfire_timer
            --     .. ', air_fuel_ratio: ' .. air_fuel_ratio
            -- )
        end

        local afr_power_factor = afr_power_curve[math.max(math.min(math.floor(state.manifold.runners.air_fuel_ratio * 10), 270), 0)] or 0
        state.afr_power_factor = afr_power_factor
        combustion_pressure = combustion_pressure * afr_power_factor
        
        local mean_compression_pressure = (engineMeasurements.compression_ratio + 1) / 9
        local mean_exhaust_pressure = (combustion_pressure / 50 + 1) / 2
        -- local mean_exhaust_pressure = (combustion_pressure + 1) / 2
        -- local MEP_approx = (
        --     (-mean_compression_pressure * (9 * --[[Perché si lol]] (1 - detonationFactor))) --[[* 2]] +
        --         combustion_pressure * detonationFactor - mean_exhaust_pressure --[[* 2]]) / --[[5]]3 * conversions.bar_to_psi
        local MEP_approx = 
            (
                combustion_pressure * detonationFactor
                - mean_compression_pressure * (1 - detonationFactor) * 2.5
                - mean_exhaust_pressure * 2.5
            ) / 6 * state.volumetric_efficiency
        -- if tick % 50 == 0 then
        --     print('MEP_approx: ' .. MEP_approx .. ", combustion_pressure: " .. combustion_pressure .. ", mean_compression_pressure: " .. mean_compression_pressure .. ", mean_exhaust_pressure: " .. mean_exhaust_pressure)
        --     print("state.thermal_efficiency: " .. state.thermal_efficiency)
        -- end

        state.MEP_approx = MEP_approx

        -- TODO: MEP is wayyy to large for the HP it produces
        -- PLANK (imperial)
        -- local p = MEP_approx * conversions.bar_to_psi
        -- local l = engineMeasurements.stroke_cm * conversions.cm_to_feet
        -- local radius_cm = engineMeasurements.bore_cm / 2
        -- local area_cm2 = math.pi * radius_cm * radius_cm
        -- local a = area_cm2 * conversions.cm2_to_in2

        -- local n = state.RPM / 2

        -- local k = engineMeasurements.num_cylinders

        -- local IHP = (p * l * a * n * k) / 33000
        -- https://www.calculatoratoz.com/en/indicated-power-of-four-stroke-engine-calculator/Calc-31818
        local p = MEP_approx * conversions.bar_to_pa
        local l = engineMeasurements.stroke_cm / 100 --[[cm to m]]
        
        local radius_cm = engineMeasurements.bore_cm / 2
        local area_cm2 = math.pi * radius_cm * radius_cm
        local a = area_cm2 / 10000 --[[cm2 to m2]]

        local n = state.AV

        local k = engineMeasurements.num_cylinders

        local IHP_W = (p * l * a * n * k) / 2
        local IHP = IHP_W / 745.7 --[[W to HP]]

        local SHP = IHP * state.thermal_efficiency
        state.SHP = SHP

        torque = (SHP * 5280 / (state.RPM + 1e-30)) * 1.3558 * combustionEngine.outputTorqueState
        torque = math.min(math.max(torque, -1000), 100000)
            -- (state.RPM < 100 or SHP < 0.5) and 0 or
            -- (math.min(((SHP * 5280 / (state.RPM + 1e-30)) * 1.3558), 10000000)) * combustionEngine.outputTorqueState
        -- state.torque_comb = torque
        -- if debug and tick % 50 == 0 then
        --     print('state.RPM: ' ..
        --         state.RPM ..
        --         ', throttle: ' ..
        --         state.TPS ..
        --         ', SHP: ' ..
        --         SHP ..
        --         ', torque: ' ..
        --         torque .. ', air_fuel_ratio: ' .. air_fuel_ratio .. ', afr_power_factor: ' .. afr_power_factor)
        -- end
        if fuel_misfire > 0 then
            -- print("MISFIRE POWER: " .. torque)
        end
        -- TODO: calculate lambda based on combustion completeness
        local lambda = state.manifold.runners.air_fuel_ratio / 14.7 -- AFR / Stoichyometric
        state.lambda = lambda
    end

    state.combustionTorque = torque
    --return state
end

M.init = init
M.update = update
return M