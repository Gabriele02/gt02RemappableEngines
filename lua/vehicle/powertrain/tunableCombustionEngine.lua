
local M = {}

-- This function pulls a value from a 3D table given a target for X and Y coordinates.
-- It performs a 2D linear interpolation as described in: www.megamanual.com/v22manual/ve_tuner.pdf
local function get3DTableValue(table, x, y, p)
	-- dump(table)

	--[[
		y_top		Q11		R1	Q12

		y					P

		y_bottom	Q21		R2	Q22

					x_left	x	x_right
	]]



	local y_top = (math.floor((y + table['yStep']) / table['yStep'])) * table['yStep']
	local y_bottom = (math.floor(y / table['yStep'])) * table['yStep']
	local x_left = math.floor(x / table['xStep']) * table['xStep']
	local x_right = (math.floor(x / table['xStep']) + 1) * table['xStep']

	-- if(y_top / table['yStep'] > #table['values']) then
	-- 	y_top = #table['values'] * table['yStep']
	-- end
	-- print('y_top: ' .. y_top .. ', a: ' .. table['yMax'])
	if(y_bottom < 0) then
		y_bottom = 0
	end
	if y_top > table['yMax'] then
		y_top = table['yMax']
		y_bottom = table['yMax']
	end
	if(x_left < 0) then
		x_left = 0
	end

	-- if p then
	-- 	print('x_left: ' .. x_left .. ', x_right: ' .. x_right .. ', y_bottom: ' .. y_bottom .. ', y_top: ' .. y_top .. ', x: ' .. x .. ', y: '.. y)
	-- end
	local Q11 = table['values'][''..y_top][''..x_left]
	local Q12 = table['values'][''..y_top][''..x_right]
	local Q21 = table['values'][''..y_bottom][''..x_left]
	local Q22 = table['values'][''..y_bottom][''..x_right]
	-- print('y_top: ' .. y_top .. ', x_right: ' .. x_right)
	-- if p then
	-- 	print('Q11: ' .. Q11 .. ', Q12: ' .. Q12)
	-- 	print('Q21: ' .. Q21 .. ', Q22: ' .. Q22)
	-- end
	local R1 = (Q11 * ((x_right - x) / table['xStep'])) + (Q12 * ((x - x_left) / table['xStep']))
	local R2 = (Q21 * ((x_right - x) / table['xStep'])) + (Q22 * ((x - x_left) / table['xStep']))
	-- if p then
	-- 	print('R1: ' .. R1 .. ', R2: ' .. R2)
	-- end
	if y_bottom == y_top then
		return (R1  + R2) / 2
	else
		local v = (R1 * ((y_top - y) / table['yStep'])) + (R2 * ((y - y_bottom) / table['yStep']))
		-- print(v)
		-- dump(table['values'])
		-- dump(table['values']['' .. math.floor(y)])
		return v
	end
end

-- conversions
local conversions = {
	cm_to_feet = 0.0328084,
	cm_to_in = 0.393701,
	cm2_to_in2 = 0.1550003,
	cc_min_to_lb_h = 0.132277357,
	bar_to_psi = 14.7,
	inf = 1/0
}
local ecu = {
  throttleSmoother = newTemporalSmoothing(15, 10),
  tuneOutData = {
    lambda = 0,
		afr = 0,
		rpm = 0,
		load = 0,
		throttle = 0,
	}
}
local engineMeasurements = {
  compression_ratio =  0,
  stroke_cm =  0,
  bore_cm =  0,
  displacement_cc = 0,
  num_cylinders =  0,
  injector_cc_min =  0,
  thermal_efficiency =  0,
  volumetric_efficiency =  0,
  throttle_body_diameter_cm =  0,
}
-- local air_density = 1 -- should be based on temperature
-- local fuel_density = 1.3 -- ^^
local tick = 0
-- Air
local volumetric_efficiency_curve = nil

-- Fuel
local afr_power_curve = nil -- Times 10 to have integer indices
local fuel_burn_speed_curve = nil -- Times 10 to have integer indices
local misfire_probability = 0
local misfire_timer = 0

-- Maps
local maps = nil

local engine = nil
local config = nil
local engineFunctions = nil

local prev_data = {}
local ws = require('utils/simpleHttpServer')
local handlers = {
  {'/engineData.json', function()
    local s = jsonEncode(ecu.tuneOutData)
    return
    [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: keep-alive
Content-Length: ]] .. string.len(s) .. [[

Content-Type: application/json
Access-Control-Allow-Origin: *

]] .. s
  end},
  {'/js/gauge.min.js', function(_, path)
    local body = readFile('js/gauge.min.js')
 
  return [[
HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len(body) .. [[

Content-Type: text/javascript

]] .. body
  end
  },
  {'/', function()
    local body = readFile('tuner.html')
 
  return [[
HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len(body) .. [[

Content-Type: text/html

]] .. body
  end
  },
  }

local function resetWS()
  print('RESETTING')
	-- if engine ~= nil then
  --   return
  ws.stop()
	-- end
	local listenHost = '127.0.0.1'
  local httpListenPort = 42069
  ws.start(listenHost, httpListenPort, '/', handlers, function(req, path)
  return {
    httpPort = httpListenPort,
    wsPort = httpListenPort + 1,
    host = listenHost,
  }
  end)
end

local function reloadTuneFromFile()
	local tuneFilePath = "mods/yourTunes" .. v.config.partConfigFilename .. "/tune.json"
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
  ecu.tuneOutData.tuneFilePath = tuneFilePath
	maps = jsonDecode(tuneStr, 'tune-json-decode')
end

-- local function updateGFX(dt)
local function calculateTorque(dt)
  tick = tick +1
	--ihp =plank/33000

	-- p = mean absolute pressure (psi)

	-- l = stroke lenght (feet)

	-- a = piston area (pollici quadri)

	-- n = RPM / 2

	-- k = num cylinders

	local torque = 0

	local mean_compression_pressure = (engineMeasurements.compression_ratio + 1) / 2 -- manca VE
	-- print('displacement (cc): ' .. engineMeasurements.displacement_cc)
	-- print('displacement (L): ' .. (engineMeasurements.displacement_cc / 1000))
	-- local displacement_ci = engineMeasurements.displacement_cc / 16.387064

	local RPM = math.abs(engine.outputRPM)
	
	local throttle =  electrics.values[engine.electricsThrottleName]
	-- if engine.outputRPM > 0 and engine.outputRPM < 700 then
    local idleThrottle = math.min(1 / ((engine.outputRPM/600 + 1) ^2 ), 1)
		throttle = math.min(idleThrottle + throttle, 1)
	-- end
  -- print(throttle)
  throttle = ecu.throttleSmoother:getUncapped(throttle, dt)
	engine.throttle = 0

  if engine.ignitionCoef == 0 then
    throttle = 0
  end



	engineMeasurements.thermal_efficiency = 0.26 -- TODO create curve
	-- print(test_curve[RPM])
	engineMeasurements.volumetric_efficiency = volumetric_efficiency_curve[RPM] or 0
	if RPM > 7000 then
		engineMeasurements.volumetric_efficiency = volumetric_efficiency_curve[7500]
	end
	engineMeasurements.volumetric_efficiency = engineMeasurements.volumetric_efficiency --* engine.intakeAirDensityCoef+ (electrics.values.turboBoost / 14.7)
  --*engine.forcedInductionCoef--* engine.forcedInductionCoef-- * throttle
	-- AIR

	-- local teorical_airflow_CFM = RPM * displacement_ci / 3456
	-- local airflow_CFM = engineMeasurements.volumetric_efficiency * teorical_airflow_CFM
	local throttle_body_area = math.pi * (engineMeasurements.throttle_body_diameter_cm / 2) ^ 2
	local opening = throttle_body_area - (throttle_body_area * math.cos((math.pi / 2)* throttle)) -- FAKY WAKY
	local simulated_diameter = 2 * math.sqrt(opening / math.pi)
	-- print("opening: " .. opening .. ", diameter: " .. simulated_diameter)
	local simulated_diameter_in = simulated_diameter * conversions.cm_to_in
	local indicated_air_mass_flow = 100 * engine.intakeAirDensityCoef * (RPM / 2) * engineMeasurements.volumetric_efficiency * (engineMeasurements.displacement_cc / 1000) * (28.97 --[[MM Air]]) / (8.314--[[R]])
	-- --[[
	-- 	https://www.engineersedge.com/fluid_flow/flow_of_air_in_pipes_14029.htm
	-- 	https://esenssys.com/air-velocity-flow-rate-measurement/#:~:text=Mass%20Flow%20Rate%20(%E1%B9%81)%20%3D,rate%20of%204.703%20kg%2Fs.
	-- ]]
	-- local air_speed = indicated_air_mass_flow * 0.00006 / (60 * math.pi * (simulated_diameter * 0.01/2) ^ 2)
	-- --  / engine.intakeAirDensityCoef
	-- print('air_speed: ' .. air_speed .. ', indicated_air_mass_flow: ' .. indicated_air_mass_flow)
	-- local air_speed_ft_s = air_speed * 0.911344
	-- local pressure_drop = (2 * (air_speed_ft_s ^ 2))/(25000 * simulated_diameter_in + 1e-30)
	-- print("TEST: " .. (pressure_drop * 0.0625) .. ' PSI')

	local m3_of_air = 0.000773455 * indicated_air_mass_flow
	local air_speed_m_s = (m3_of_air / (1.225 * opening))
	-- print("velocity: " .. air_speed_m_s)
	local air_speed_ft_s = air_speed_m_s * 0.911344
	local pressure_drop = (2 * (air_speed_ft_s ^ 2))/(25000 * simulated_diameter_in + 1e-30)
	-- print("pressure_drop: " .. (pressure_drop * 0.0625))
  -- print(engine.forcedInductionCoef)
	-- local MAP = 100 * math.sqrt(throttle)-- Kpa
	local intake_air_pressure = 287.058 * (1.225 * (engine.intakeAirDensityCoef + ((electrics.values.turboBoost or 0) / 14.7)--[[* engine.forcedInductionCoef]])) * 293 / 1000
  -- if tick % 50 == 0 then
  -- 	-- print("intake_air_pressure: " .. intake_air_pressure)
  -- 	-- print("engine.forcedInductionCoef: " .. engine.forcedInductionCoef)
  -- end
	local MAP = math.max(intake_air_pressure - ((pressure_drop * 6894.76) / 1000), 0) -- Kpa
  
	local IAT = 293.15 -- Kelvin
	local IMAP = RPM * MAP / IAT / 2
	-- print('MAP: ' ..  MAP)
	-- where RPM is engine speed in revolutions per minute
	-- MAP (manifold absolute pressure) is measured in KPa
	-- IAT (intake air temperature) is measured in degrees Kelvin.

	local air_mass_flow = (IMAP / 60) * engineMeasurements.volumetric_efficiency * (engineMeasurements.displacement_cc / 1000) * (28.97 --[[MM Air]]) / (8.314--[[R]])
	-- (grams of air) = (IMAP/60)*(Vol Eff/100)*(Eng Disp)*(MM Air)/(R)
	-- where R is 8.314 J/°K/mole,
	-- the average molecular mass of air (MM) is 28.97 g/mole. Note that in the above formula the volumetric efficiency of the engine is measured in percent and the displacement is in liters.

	-- print('Airflow (t / actual) (CFM): ' .. teorical_airflow_CFM .. ' / ' .. airflow_CFM)
	-- print('Air mass flow: ' .. air_mass_flow)

	-- FUEL
	-- Varies with engine map
	-- print('got: ' .. get3DTableValue(maps['injector-table'], RPM, MAP, true))
	local injector_duty = get3DTableValue(maps['injector-table'], RPM, MAP, false) / 100
	-- math.max(0.02,  0.4 *RPM / 6000)

	-- local fuelflow_cfm = injector_lb_h * engineMeasurements.num_cylinders * injector_duty * 0.000266974

	local fuel_mass_flow = (engineMeasurements.injector_cc_min / 60 * engineMeasurements.num_cylinders * injector_duty --[[grams per second]]) / 1.335291761
	local air_fuel_ratio
	if fuel_mass_flow < 1e-30 or (fuel_mass_flow ~= fuel_mass_flow) then
		air_fuel_ratio = 0
	else
		air_fuel_ratio = air_mass_flow / fuel_mass_flow
	end
	if air_fuel_ratio ~= air_fuel_ratio then
		air_fuel_ratio = 0
	end

	if air_fuel_ratio > 15 or air_fuel_ratio < 9 and throttle > 0 then -- Should be engine load not throttle
		if air_fuel_ratio > 15 then
			misfire_probability = (air_fuel_ratio / 20) ^ 8 * engine.instantEngineLoad * dt
			misfire_timer = 2
			-- print("misfire_probability: " .. misfire_probability)
			-- if math.random() < ratio then
			-- 	-- engine:lockUp()
			-- 	if engine.outputTorqueState > 0.8 then
			-- 		engine:scaleOutputTorque(0.5)
			-- 		engine.instantAfterFireFuelDelay:push(1)
			-- 	end
			-- end
		end
		if air_fuel_ratio < 9 then -- Should be engine load not throttle
			misfire_probability = 4 / air_fuel_ratio * engine.instantEngineLoad * dt
			misfire_timer = 2
		end
	else
		misfire_timer = 0
		misfire_probability = 0
	end

	local lambda = air_fuel_ratio / 14.7 -- AFR / Stoichyometric
	-- print('fuel_mass_flow: ' .. fuel_mass_flow)
	-- print("throttle: " .. string.format("%.2f",throttle) .. ", afr: " .. string.format("%.2f",air_fuel_ratio))
	-- print("lambda: " .. lambda)
	-- print("injector_lb_h: " .. injector_lb_h)

	-- SPARK

	local ignition_advance_deg = get3DTableValue(maps['advance-table'], RPM, MAP, true)-- BTDC
	local piston_speed_ms = 2 * (engineMeasurements.stroke_cm / 100) * (RPM / 60)
	local flame_speed = 25
	local boh = 1 / 7000 * RPM
	-- dump(math.sqrt((0.01737)*(engineMeasurements.stroke_cm /2.54)*(RPM)/engineMeasurements.compression_ratio + 3))
	-- dump('iad: ' .. ignition_advance_deg)
	-- ignition_advance_deg = ignition_advance_deg + (2 * math.sqrt((0.01737)*(engineMeasurements.stroke_cm /2.54)*(RPM)/engineMeasurements.compression_ratio + 3))
	local fuel_burn_speed = math.max(fuel_burn_speed_curve[math.max(math.min(math.floor(air_fuel_ratio * 10), 270), 0)] or 1, 0)
	local fuel_burn_duration_deg
  local detonationFactor = 1
	local max_pressure_point_dATDC
	if fuel_burn_speed >= 0 then
		fuel_burn_duration_deg = ((20*(engineMeasurements.stroke_cm / 8.2) / (((MAP/100)^0.3))) * RPM / 3600) / fuel_burn_speed
    -- if tick % 50 == 0 then
    --   print((20 / ((engineMeasurements.volumetric_efficiency ^ 0.2) * (engine.forcedInductionCoef^0.2))))
    -- end
		local stroke_duration_s = 1 / (RPM * 2 / 60)
		max_pressure_point_dATDC = -ignition_advance_deg + fuel_burn_duration_deg
		-- print('ignition_advance: ' .. ignition_advance_deg)
		-- print('max_pressure_point_dATDC: ' .. max_pressure_point_dATDC)
		-- print('ignition_advance: ' .. ignition_advance_deg)
		-- print('burn duratoin degrees: ' .. fuel_burn_duration_deg)
		-- print('max_pressure_point_dATDC: ' .. max_pressure_point_dATDC)
		if max_pressure_point_dATDC < 0 then
      detonationFactor = math.min(math.max(1 - math.abs(max_pressure_point_dATDC / fuel_burn_duration_deg), 0),  1)
			-- print("KNOCK KNOCK")
			if math.random() < math.abs(max_pressure_point_dATDC / 20) ^ 5 then
				engine:lockUp()
			end
		end

		local combustion_pressure = engineMeasurements.compression_ratio * 9 * MAP/100 -- Manca VE (9 ~ perché si lol)
		if ignition_advance_deg > 0 then
			combustion_pressure = combustion_pressure + (ignition_advance_deg * 2)

			engine.sustainedAfterFireCoef = prev_data.sustainedAfterFireCoef or engine.sustainedAfterFireCoef
			engine.sustainedAfterFireFuelDelay = prev_data.sustainedAfterFireFuelDelay or engine.sustainedAfterFireFuelDelay
			engine.sustainedAfterFireTimer = prev_data.sustainedAfterFireTimer or engine.sustainedAfterFireTimer
			engine.instantAfterFireCoef = prev_data.instantAfterFireCoef or engine.instantAfterFireCoef
			engine.instantAfterFireFuelDelay = prev_data.instantAfterFireFuelDelay or engine.instantAfterFireFuelDelay
			engine.instantAfterFireTimer = prev_data.instantAfterFireTimer or engine.instantAfterFireTimer
			engine.slowIgnitionErrorChance = prev_data.slowIgnitionErrorChance or engine.slowIgnitionErrorChance
			engine.slowIgnitionErrorInterval = prev_data.slowIgnitionErrorInterval or engine.slowIgnitionErrorInterval
			prev_data.modified = false
		else
			combustion_pressure = combustion_pressure + (ignition_advance_deg * 4)
		end
		if prev_data.modified == false then
			prev_data.sustainedAfterFireCoef = engine.sustainedAfterFireCoef
			prev_data.sustainedAfterFireFuelDelay = engine.sustainedAfterFireFuelDelay
			prev_data.sustainedAfterFireTimer = engine.sustainedAfterFireTimer
			prev_data.instantAfterFireCoef = engine.instantAfterFireCoef
			prev_data.instantAfterFireFuelDelay = engine.instantAfterFireFuelDelay
			prev_data.instantAfterFireTimer = engine.instantAfterFireTimer
			prev_data.slowIgnitionErrorChance = engine.slowIgnitionErrorChance
			prev_data.slowIgnitionErrorInterval = engine.slowIgnitionErrorInterval
			prev_data.modified = false
		end
		if max_pressure_point_dATDC >= 30 and RPM > 2 * engine.idleRPM and not (max_pressure_point_dATDC == conversions.inf or max_pressure_point_dATDC == -conversions.inf) then
			-- engine.sustainedAfterFireCoef = 100
			-- engine.sustainedAfterFireFuelDelay:push(1000)
			-- engine.sustainedAfterFireTimer = 20
			local factor = math.min(max_pressure_point_dATDC / 90, 1)
			engine.instantAfterFireCoef = 100 * factor * math.random()
			engine.instantAfterFireFuelDelay:push(factor * math.random())
			engine.instantAfterFireTimer = factor * math.random()
			engine.slowIgnitionErrorChance = factor ^ 2
			engine.slowIgnitionErrorInterval = math.random(0.1, 1)
			prev_data.modified = true
			-- print("HEREEEEEEEEE")
		end
		local mean_exhaust_pressure = (combustion_pressure + 1) / 2
		local MEP_approx = ((-mean_compression_pressure * (9 * --[[Perché si lol]] (1-detonationFactor)) * 2) + combustion_pressure * detonationFactor + mean_exhaust_pressure * 2) / 5 * conversions.bar_to_psi
		-- print('cp: ' .. mean_compression_pressure .. ', cc' .. combustion_pressure .. ', iad' .. ignition_advance_deg )

		local p = MEP_approx

		-- PLANK
		local l = engineMeasurements.stroke_cm * conversions.cm_to_feet
		local radius_cm = engineMeasurements.bore_cm / 2
		local area_cm2 = math.pi * radius_cm * radius_cm
		local a = area_cm2 * conversions.cm2_to_in2

		local n = RPM / 2

		local k = engineMeasurements.num_cylinders

		local IHP = (p * l * a * n * k) / 33000

		local fuel_misfire = 1
		if math.random() < misfire_probability and misfire_timer > 0 then
			fuel_misfire = 0
			-- print("AFR MISFIRE: " .. air_fuel_ratio .. ', misfire_probability: ' .. misfire_probability)
		end
		misfire_timer = misfire_timer - dt

		local afr_power_factor = afr_power_curve[math.max(math.min(math.floor(air_fuel_ratio * 10), 270), 0)] or 0
		local SHP = IHP * engineMeasurements.thermal_efficiency * afr_power_factor-- * engine.forcedInductionCoef--* (engineMeasurements.volumetric_efficiency * MAP / 100)
		torque = (RPM < 100 or SHP < 0.5) and 0 or (math.min(((SHP * 5280 / (RPM + 1e-30)) * 1.3558), 10000000)) * engine.outputTorqueState * fuel_misfire
		-- print('RPM: ' .. RPM .. ', throttle: ' .. throttle .. ', SHP: ' .. SHP .. ', torque: ' .. torque .. ', air_fuel_ratio: ' .. air_fuel_ratio ..', afr_power_factor: ' .. afr_power_factor)
	end
	-- print('afr: ' .. air_fuel_ratio .. ', throttle: ' .. throttle)

	-- engine.sos = torque
	-- print('load: ' .. engine.instantEngineLoad)
	-- print('afr_power_factor: ' .. afr_power_factor)
	-- print('Simulated HP: ' .. SHP)
	-- ecu.tuneOutData = {
    ecu.tuneOutData.lambda = lambda
		ecu.tuneOutData.afr =  string.format("%.2f", air_fuel_ratio)
		ecu.tuneOutData.rpm =  string.format("%.2f", RPM)
		ecu.tuneOutData.throttle =  string.format("%.2f", throttle)
		ecu.tuneOutData.map =  string.format("%.2f", MAP)
		ecu.tuneOutData.max_pressure_point_dATDC =  string.format("%.2f", max_pressure_point_dATDC)
	-- }
	-- ws.update()
	return torque
end

-- local function updateWheelsIntermediate(dt)

-- end

local function init(localEngine, jbeamData)
	config = jbeamData
  print(v.config.partConfigFilename)
  -- local engineName = config.engineName or "mainEngine"
	-- engine = powertrain.getDevice(engineName)
	engine = localEngine
  engineMeasurements.compression_ratio = jbeamData.compression_ratio

  engineMeasurements.stroke_cm = jbeamData.stroke_cm
  engineMeasurements.bore_cm = jbeamData.bore_cm
  engineMeasurements.num_cylinders = jbeamData.num_cylinders
	engineMeasurements.displacement_cc = math.pi * (engineMeasurements.bore_cm / 2) * (engineMeasurements.bore_cm / 2) * engineMeasurements.stroke_cm * engineMeasurements.num_cylinders
  print("displacement_cc" .. engineMeasurements.displacement_cc)

  engineMeasurements.injector_cc_min = jbeamData.injector_cc_min
  engineMeasurements.thermal_efficiency = jbeamData.thermal_efficiency
  engineMeasurements.volumetric_efficiency = jbeamData.volumetric_efficiency
  engineMeasurements.throttle_body_diameter_cm = jbeamData.throttle_body_diameter_cm
	local points = table.new(3, 0)
	points[0] = {0, 0.5}
	points[1] = {1, 0.5}
	points[2] = {1000, 0.8}
	points[3] = {4000, 0.88}
	points[4] = {6000, 0.8}
	points[5] = {7500, 0.7}
	volumetric_efficiency_curve = createCurve(points, true)

	local afr_power_curve_points = {
		{30,	0},
		{40,	0},
		{50,	0},
		{60,	0.5},
		{90,	0.8},
		{115,	0.95},
		{122,	1},
		{133,	0.95},
		{147,	0.87},
		{155,	0.76},
		{165,	0.62},
		{180,	0.45},
		{220,	0.23},
		{250,	0},
		{260,	0},
		{270,	0},
	}
	afr_power_curve = createCurve(afr_power_curve_points, true)

	local fuel_burn_speed_points = {
		{30,	0},
		{40,	0},
		{50,	0},
		{6,		0.2},
		{7,		0.45},
		{8,		0.7},
		{9.5,	0.85},
		{10,	0.9},
		{110,	0.98},
		{115, 	1},
		{120,	0.97},
		{130,	0.83},
		{140,	0.74},
		{147,	0.68},
		{150,	0.65},
		{160,	0.59},
		{170,	0.53},
		{180,	0.5},
		{190,	0.45},
		{200,	0.4},
		{210,	0.35},
		{220,	0.28},
		{230,	0.15},
		{250,	0},
		{260,	0},
		{270,	0},
	}
	fuel_burn_speed_curve = createCurve(fuel_burn_speed_points, true)

	-- local tuneFle = readFile('data/tune.json')

	reloadTuneFromFile()
	resetWS(ecu)
    print('created http server')
end

-- local function initSecondStage()
   
-- end

local function resetECU()
  ecu.throttleSmoother:reset()
	ecu.tuneOutData.afr = 0
  ecu.tuneOutData.rpm = 0
  ecu.tuneOutData.throttle = 0
  ecu.tuneOutData.map = 0
  ecu.tuneOutData.max_pressure_point_dATDC = 0
  ecu.tuneOutData.lambda = 0
	resetWS()
	reloadTuneFromFile()
end

--------------------------------------------------------------------------
-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

-- local M = {}

M.outputPorts = {[1] = true} --set dynamically
M.deviceCategories = {engine = true}

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
      torqueCurve[k + 1] = v - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
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

  table.insert(curves, curveCounter, {torque = torqueCurve, power = powerCurve, name = "NA", priority = 10})

  if device.nitrousOxideInjection.isExisting then
    local torqueCurveNitrous = {}
    local powerCurveNitrous = {}
    nitrousTorques = device.nitrousOxideInjection.getAddedTorque()

    for k, v in pairs(device.torqueCurve) do
      if type(k) == "number" and k < maxRPM then
        torqueCurveNitrous[k + 1] = v + (nitrousTorques[k] or 0) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
        powerCurveNitrous[k + 1] = torqueCurveNitrous[k + 1] * k * torqueToPower
        if torqueCurveNitrous[k + 1] > maxTorque then
          maxTorque = torqueCurveNitrous[k + 1]
          maxTorqueRPM = k + 1
        end
        if powerCurveNitrous[k + 1] > maxPower then
          maxPower = powerCurveNitrous[k + 1]
          maxPowerRPM = k + 1
        end
      end
    end

    curveCounter = curveCounter + 1
    table.insert(curves, curveCounter, {torque = torqueCurveNitrous, power = powerCurveNitrous, name = "N2O", priority = 20})
  end

  if device.turbocharger.isExisting then
    local torqueCurveTurbo = {}
    local powerCurveTurbo = {}
    turboCoefs = device.turbocharger.getTorqueCoefs()

    for k, v in pairs(device.torqueCurve) do
      if type(k) == "number" and k < maxRPM then
        torqueCurveTurbo[k + 1] = (v * (turboCoefs[k] or 0)) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
        powerCurveTurbo[k + 1] = torqueCurveTurbo[k + 1] * k * torqueToPower
        if torqueCurveTurbo[k + 1] > maxTorque then
          maxTorque = torqueCurveTurbo[k + 1]
          maxTorqueRPM = k + 1
        end
        if powerCurveTurbo[k + 1] > maxPower then
          maxPower = powerCurveTurbo[k + 1]
          maxPowerRPM = k + 1
        end
      end
    end

    curveCounter = curveCounter + 1
    table.insert(curves, curveCounter, {torque = torqueCurveTurbo, power = powerCurveTurbo, name = "Turbo", priority = 30})
  end

  if device.supercharger.isExisting then
    local torqueCurveSupercharger = {}
    local powerCurveSupercharger = {}
    superchargerCoefs = device.supercharger.getTorqueCoefs()

    for k, v in pairs(device.torqueCurve) do
      if type(k) == "number" and k < maxRPM then
        torqueCurveSupercharger[k + 1] = (v * (superchargerCoefs[k] or 0)) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
        powerCurveSupercharger[k + 1] = torqueCurveSupercharger[k + 1] * k * torqueToPower
        if torqueCurveSupercharger[k + 1] > maxTorque then
          maxTorque = torqueCurveSupercharger[k + 1]
          maxTorqueRPM = k + 1
        end
        if powerCurveSupercharger[k + 1] > maxPower then
          maxPower = powerCurveSupercharger[k + 1]
          maxPowerRPM = k + 1
        end
      end
    end

    curveCounter = curveCounter + 1
    table.insert(curves, curveCounter, {torque = torqueCurveSupercharger, power = powerCurveSupercharger, name = "SC", priority = 40})
  end

  if device.turbocharger.isExisting and device.supercharger.isExisting then
    local torqueCurveFinal = {}
    local powerCurveFinal = {}

    for k, v in pairs(device.torqueCurve) do
      if type(k) == "number" and k < maxRPM then
        torqueCurveFinal[k + 1] = (v * (turboCoefs[k] or 0) * (superchargerCoefs[k] or 0)) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
        powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
        if torqueCurveFinal[k + 1] > maxTorque then
          maxTorque = torqueCurveFinal[k + 1]
          maxTorqueRPM = k + 1
        end
        if powerCurveFinal[k + 1] > maxPower then
          maxPower = powerCurveFinal[k + 1]
          maxPowerRPM = k + 1
        end
      end
    end

    curveCounter = curveCounter + 1
    table.insert(curves, curveCounter, {torque = torqueCurveFinal, power = powerCurveFinal, name = "Turbo + SC", priority = 50})
  end

  if device.turbocharger.isExisting and device.nitrousOxideInjection.isExisting then
    local torqueCurveFinal = {}
    local powerCurveFinal = {}

    for k, v in pairs(device.torqueCurve) do
      if type(k) == "number" and k < maxRPM then
        torqueCurveFinal[k + 1] = (v * (turboCoefs[k] or 0) + (nitrousTorques[k] or 0)) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
        powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
        if torqueCurveFinal[k + 1] > maxTorque then
          maxTorque = torqueCurveFinal[k + 1]
          maxTorqueRPM = k + 1
        end
        if powerCurveFinal[k + 1] > maxPower then
          maxPower = powerCurveFinal[k + 1]
          maxPowerRPM = k + 1
        end
      end
    end

    curveCounter = curveCounter + 1
    table.insert(curves, curveCounter, {torque = torqueCurveFinal, power = powerCurveFinal, name = "Turbo + N2O", priority = 60})
  end

  if device.supercharger.isExisting and device.nitrousOxideInjection.isExisting then
    local torqueCurveFinal = {}
    local powerCurveFinal = {}

    for k, v in pairs(device.torqueCurve) do
      if type(k) == "number" and k < maxRPM then
        torqueCurveFinal[k + 1] = (v * (superchargerCoefs[k] or 0) + (nitrousTorques[k] or 0)) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
        powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
        if torqueCurveFinal[k + 1] > maxTorque then
          maxTorque = torqueCurveFinal[k + 1]
          maxTorqueRPM = k + 1
        end
        if powerCurveFinal[k + 1] > maxPower then
          maxPower = powerCurveFinal[k + 1]
          maxPowerRPM = k + 1
        end
      end
    end

    curveCounter = curveCounter + 1
    table.insert(curves, curveCounter, {torque = torqueCurveFinal, power = powerCurveFinal, name = "SC + N2O", priority = 70})
  end

  if device.turbocharger.isExisting and device.supercharger.isExisting and device.nitrousOxideInjection.isExisting then
    local torqueCurveFinal = {}
    local powerCurveFinal = {}

    for k, v in pairs(device.torqueCurve) do
      if type(k) == "number" and k < maxRPM then
        torqueCurveFinal[k + 1] = (v * (turboCoefs[k] or 0) * (superchargerCoefs[k] or 0) + (nitrousTorques[k] or 0)) - device.friction * device.wearFrictionCoef * device.damageFrictionCoef - (device.dynamicFriction * device.wearDynamicFrictionCoef * device.damageDynamicFrictionCoef * k * rpmToAV)
        powerCurveFinal[k + 1] = torqueCurveFinal[k + 1] * k * torqueToPower
        if torqueCurveFinal[k + 1] > maxTorque then
          maxTorque = torqueCurveFinal[k + 1]
          maxTorqueRPM = k + 1
        end
        if powerCurveFinal[k + 1] > maxPower then
          maxPower = powerCurveFinal[k + 1]
          maxPowerRPM = k + 1
        end
      end
    end

    curveCounter = curveCounter + 1
    table.insert(curves, curveCounter, {torque = torqueCurveFinal, power = powerCurveFinal, name = "Turbo + SC + N2O", priority = 80})
  end

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

  local dashes = {nil, {10, 4}, {8, 3, 4, 3}, {6, 3, 2, 3}, {5, 3}}
  for k, v in ipairs(curves) do
    v.dash = dashes[k]
    v.width = 2
  end

  return {maxRPM = maxRPM, curves = curves, maxTorque = maxTorque, maxPower = maxPower, maxTorqueRPM = maxTorqueRPM, maxPowerRPM = maxPowerRPM, finalCurveName = 1, deviceName = device.name, vehicleID = obj:getId()}
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
      storage.storedEnergy = max(storage.storedEnergy - (device.spentEnergy * device.energyStorageRatios[storage.name]), 0)
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
  ws.update()
  engineFunctions.updateGFX(device, dt)
end

--velocity update is always nopped for engines

local function updateTorque(device, dt)
  local engineAV = device.outputAV1

  local throttle = (electrics.values[device.electricsThrottleName] or 0) * (electrics.values[device.electricsThrottleFactorName] or device.throttleFactor)
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
  local throttleMap = min(max(throttle + throttle * device.maxPowerThrottleMap / (torque * device.forcedInductionCoef * engineAV + 1e-30) * (1 - throttle), 0), 1)

  local ignitionCut = device.ignitionCutTime > 0
  torque = ((torque * device.forcedInductionCoef * throttleMap) + device.nitrousOxideTorque) * device.outputTorqueState * (ignitionCut and 0 or 1) * device.slowIgnitionErrorCoef * device.fastIgnitionErrorCoef

  local lastInstantEngineLoad = device.instantEngineLoad
  local instantLoad = min(max(torque / ((maxCurrentTorque + 1e-30) * device.outputTorqueState * device.forcedInductionCoef), 0), 1)
  device.instantEngineLoad = instantLoad
  device.engineLoad = device.loadSmoother:get(device.instantEngineLoad, dt)

  local absEngineAV = abs(engineAV)
  local dtT = dt * torque
  local dtTNitrousOxide = dt * device.nitrousOxideTorque

  local burnEnergy = dtT * (dtT * device.halfInvEngInertia + engineAV)
  local burnEnergyNitrousOxide = dtTNitrousOxide * (dtTNitrousOxide * device.halfInvEngInertia + engineAV)
  device.engineWorkPerUpdate = device.engineWorkPerUpdate + burnEnergy
  device.frictionLossPerUpdate = device.frictionLossPerUpdate + finalFriction * absEngineAV * dt
  device.pumpingLossPerUpdate = device.pumpingLossPerUpdate + finalDynamicFriction * engineAV * engineAV * dt
  local invBurnEfficiency = device.invBurnEfficiencyTable[floor(device.instantEngineLoad * 100)] * device.invBurnEfficiencyCoef
  device.spentEnergy = device.spentEnergy + burnEnergy * invBurnEfficiency
  device.spentEnergyNitrousOxide = device.spentEnergyNitrousOxide + burnEnergyNitrousOxide * invBurnEfficiency

  local frictionTorque = finalFriction + finalDynamicFriction * absEngineAV + device.engineBrakeTorque * (1 - instantLoad)
  --friction torque is limited for stability
  frictionTorque = min(frictionTorque, absEngineAV * device.inertia * 2000) * sign(engineAV)

  local starterTorque = device.starterEngagedCoef * device.starterTorque * min(max(1 - engineAV / device.starterMaxAV, -0.5), 1)

  --iterate over all connected clutches and sum their torqueDiff to know the final torque load on the engine
  local torqueDiffSum = 0
  for i = 1, device.numberOfOutputPorts do
    torqueDiffSum = torqueDiffSum + device.clutchChildren[i].torqueDiff
  end
  --calculate the AV based on all loads
  torque = calculateTorque(dt)
  local outputAV = (engineAV + dt * (torque - torqueDiffSum - frictionTorque + starterTorque) * device.invEngInertia) * device.outputAVState
  --set all output torques and AVs to the newly calculated values
  for i = 1, device.numberOfOutputPorts do
    device[device.outputTorqueNames[i]] = torqueDiffSum
    device[device.outputAVNames[i]] = outputAV
  end
  device.throttle = throttle
  device.combustionTorque = torque - frictionTorque
  device.frictionTorque = frictionTorque

  local inertialTorque = (device.outputAV1 - device.lastOutputAV1) * device.inertia / dt
  ffi.C.bng_applyTorqueAxisCouple(ffiObjPtr, inertialTorque, device.torqueReactionNodes[1], device.torqueReactionNodes[2], device.torqueReactionNodes[3])
  device.lastOutputAV1 = device.outputAV1

  local dLoad = min((device.instantEngineLoad - lastInstantEngineLoad) / dt, 0)
  local instantAfterFire = engineAV > device.idleAV * 2 and max(device.instantAfterFireCoef * -dLoad * lastInstantEngineLoad * absEngineAV, 0) or 0
  local sustainedAfterFire = (device.instantEngineLoad <= 0 and device.sustainedAfterFireTimer > 0) and max(engineAV * device.sustainedAfterFireCoef, 0) or 0

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
  resetECU()
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
  local correctedThrottle = -throttle * min(max(engineAV - limiterAV, 0), device.revLimiterMaxAVOvershoot) * device.invRevLimiterRange + throttle

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
  print("NEW CALLED ON CORRECT ENGINE")
  local dummyData = deepcopy(jbeamData)
  dummyData.numberOfOutputPorts = 0
  dummyData.name = "mainEngine"
  dummyData.type = "combustionEngine"
  engineFunctions  = require("powertrain/combustionEngine").new(dummyData)
  local device = {
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
    sendTorqueData = engineFunctions.sendTorqueData,
    getTorqueData = engineFunctions.getTorqueData,
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
--   device.name = "mainEngine"
--   dump(jbeamData)
  init(device, jbeamData)

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
    device.torqueReactionNodes = {-1, -1, -1}
  end

  device.waterDamageNodes = jbeamData.waterDamage and jbeamData.waterDamage._engineGroup_nodes or {}

  device.canFlood = device.waterDamageNodes and type(device.waterDamageNodes) == "table" and #device.waterDamageNodes > 0

  device.maxPhysicalAV = (jbeamData.maxPhysicalRPM or (jbeamData.maxRPM * 1.05)) * rpmToAV --what the engine is physically capable of

  if not jbeamData.torque then
    log("E", "combustionEngine.init", "Can't find torque table... Powertrain is going to break!")
  end

  local baseTorqueTable = tableFromHeaderTable(jbeamData.torque)
  local rawBasePoints = {}
  local maxAvailableRPM = 0
  for _, v in pairs(baseTorqueTable) do
    maxAvailableRPM = max(maxAvailableRPM, v.rpm)
    table.insert(rawBasePoints, {v.rpm, v.torque})
  end
  local rawBaseCurve = createCurve(rawBasePoints)

  local rawTorqueMultCurve = {}
  if jbeamData.torqueModMult then
    local multTorqueTable = tableFromHeaderTable(jbeamData.torqueModMult)
    local rawTorqueMultPoints = {}
    for _, v in pairs(multTorqueTable) do
      maxAvailableRPM = max(maxAvailableRPM, v.rpm)
      table.insert(rawTorqueMultPoints, {v.rpm, v.torque})
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
      table.insert(rawIntakePoints, {v.rpm, v.torque})
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
      table.insert(rawExhaustPoints, {v.rpm, v.torque})
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
    table.insert(combinedTorquePoints, {i, rawCombinedCurve[i] or 0})
  end

  --past redline we want to gracefully reduce the torque for a natural redline
  device.redlineTorqueDropOffRange = clamp(jbeamData.redlineTorqueDropOffRange or 500, 10, device.maxRPM)

  --last usable torque value for a smooth transition to past-maxRPM-drop-off
  local rawMaxRPMTorque = rawCombinedCurve[device.maxRPM] or 0

  --create the drop off past the max rpm for a natural redline
  table.insert(combinedTorquePoints, {device.maxRPM + device.redlineTorqueDropOffRange * 0.5, rawMaxRPMTorque * 0.7})
  table.insert(combinedTorquePoints, {device.maxRPM + device.redlineTorqueDropOffRange, rawMaxRPMTorque / 5})
  table.insert(combinedTorquePoints, {device.maxRPM + device.redlineTorqueDropOffRange * 2, 0})

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

  local tempBurnEfficiencyTable = nil
  if not jbeamData.burnEfficiency or type(jbeamData.burnEfficiency) == "number" then
    tempBurnEfficiencyTable = {{0, jbeamData.burnEfficiency or 1}, {1, jbeamData.burnEfficiency or 1}}
  elseif type(jbeamData.burnEfficiency) == "table" then
    tempBurnEfficiencyTable = deepcopy(jbeamData.burnEfficiency)
  end

  local copy = deepcopy(tempBurnEfficiencyTable)
  tempBurnEfficiencyTable = {}
  for k, v in pairs(copy) do
    if type(k) == "number" then
      table.insert(tempBurnEfficiencyTable, {v[1] * 100, v[2]})
    end
  end

  tempBurnEfficiencyTable = createCurve(tempBurnEfficiencyTable)
  device.invBurnEfficiencyTable = {}
  device.invBurnEfficiencyCoef = 1
  for k, v in pairs(tempBurnEfficiencyTable) do
    device.invBurnEfficiencyTable[k] = 1 / v
  end

  device.requiredEnergyType = jbeamData.requiredEnergyType or "gasoline"
  device.energyStorage = jbeamData.energyStorage

  if device.torqueReactionNodes and #device.torqueReactionNodes == 3 and device.torqueReactionNodes[1] >= 0 then
    local pos1 = vec3(v.data.nodes[device.torqueReactionNodes[1]].pos)
    local pos2 = vec3(v.data.nodes[device.torqueReactionNodes[2]].pos)
    local pos3 = vec3(v.data.nodes[device.torqueReactionNodes[3]].pos)
    local avgPos = (((pos1 + pos2) / 2) + pos3) / 2
    device.visualPosition = {x = avgPos.x, y = avgPos.y, z = avgPos.z}
  end

  device.engineNodeID = device.torqueReactionNodes and (device.torqueReactionNodes[1] or v.data.refNodes[0].ref) or v.data.refNodes[0].ref
  if device.engineNodeID < 0 then
    log("W", "combustionEngine.init", "Can't find suitable engine node, using ref node instead!")
    device.engineNodeID = v.data.refNodes[0].ref
  end

  device.engineBlockNodes = {}
  if jbeamData.engineBlock and jbeamData.engineBlock._engineGroup_nodes and #jbeamData.engineBlock._engineGroup_nodes >= 2 then
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
    device.turbocharger = {reset = nop, updateGFX = nop, updateFixedStep = nop, updateSounds = nop, initSounds = nop, resetSounds = nop, getPartCondition = nop, isExisting = false}
  end

  if jbeamData.supercharger and v.data[jbeamData.supercharger] then
    local superchargerFileName = jbeamData.superchargerLuaFileName or "powertrain/supercharger"
    device.supercharger = require(superchargerFileName)
    device.supercharger.init(device, v.data[jbeamData.supercharger])
  else
    device.supercharger = {reset = nop, updateGFX = nop, updateFixedStep = nop, updateSounds = nop, initSounds = nop, resetSounds = nop, getPartCondition = nop, isExisting = false}
  end

  if jbeamData.nitrousOxideInjection and v.data[jbeamData.nitrousOxideInjection] then
    local nitrousOxideFileName = jbeamData.nitrousOxideLuaFileName or "powertrain/nitrousOxideInjection"
    device.nitrousOxideInjection = require(nitrousOxideFileName)
    device.nitrousOxideInjection.init(device, v.data[jbeamData.nitrousOxideInjection])
  else
    device.nitrousOxideInjection = {reset = nop, updateGFX = nop, updateSounds = nop, initSounds = nop, resetSounds = nop, registerStorage = nop, getAddedTorque = nop, getPartCondition = nop, isExisting = false}
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