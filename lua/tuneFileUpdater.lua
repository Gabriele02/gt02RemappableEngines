local M = {}
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end
local function fillTable3D(map, value)
    local values = {}
    for _, yVal in ipairs(map.yValues) do
        values["" .. yVal] = {}
        for _, xVal in ipairs(map.xValues) do
            -- if value is a function, call it
            if type(value) == "function" then
                values["" .. yVal]["" .. xVal] = value(xVal, yVal)
            else
                values["" .. yVal]["" .. xVal] = value
            end
        end
    end
    return values
end

local function fillTable2D(map, value)
    local values = {}
    for _, xVal in ipairs(map.xValues) do
        -- if value is a function, call it
        if type(value) == "function" then
            values["" .. xVal] = value(xVal)
        else
            values["" .. xVal] = value
        end
    end
    return values
end

local updatesLookup = {
    _nilTo01 = function(oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.1
        for mapName, map in pairs(oldTune) do
            newTune[mapName].type = '3D'
            if mapName == "advance-table" then
                newTune[mapName].sectionName = "ignition"
                newTune[mapName].displayName = "Ignition Advance Table"
                newTune[mapName].unit = "Degº"
            elseif mapName == "injector-table" then
                newTune[mapName].sectionName = "injector"
                newTune[mapName].displayName = "Injector Duty Table"
                newTune[mapName].unit = "%"
            end
        end

        newTune.options = {}
        newTune.options['RPM-limit'] = {
            value = 0,
            unit = "RPM",
            displayName = "RPM limit",
            sectionName = "options",
            optionName = "RPM-limit",
            optionType = "number",
            step = "1",
            minimum = 0,
            maximum = 20000,
            redValue = 10000,
        }
        newTune.options['knock-correction'] = {
            value = false,
            unit = "---",
            displayName = "Knock correction",
            sectionName = "options",
            optionName = "knock-correction",
            optionType = "checkbox",
        }
        return newTune
    end,
    _01To02 = function(oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.2
        for mapName, map in pairs(oldTune) do
            if type(map) == "table" and map.type == '3D' then
                newTune[mapName].xValues = {}
                for i = map.xMin, map.xMax, map.xStep do
                    -- newTune[mapName].xValues[#newTune[mapName].xValues] = i
                    table.insert(newTune[mapName].xValues, i)
                end
                newTune[mapName].yValues = {}
                for i = map.yMin, map.yMax, map.yStep do
                    -- newTune[mapName].yValues[#newTune[mapName].yValues] = i
                    table.insert(newTune[mapName].yValues, i)
                end
                newTune[mapName].xMin  = nil
                newTune[mapName].xMax  = nil
                newTune[mapName].xStep = nil
                newTune[mapName].yMin  = nil
                newTune[mapName].yMax  = nil
                newTune[mapName].yStep = nil
                if #newTune[mapName].xValues > 30 then
                    for i = 30, #newTune[mapName].xValues, 1 do
                        -- newTune[mapName].xValues[i] = 0
                        table.insert(newTune[mapName].xValues, 0)
                    end
                end
                if #newTune[mapName].yValues > 15 then
                    for i = 15, #newTune[mapName].yValues, 1 do
                        -- newTune[mapName].yValues[i] = 0
                        table.insert(newTune[mapName].yValues, 0)
                    end
                end
                if #newTune[mapName].xValues < 30 then
                    local val = newTune[mapName].xValues[#newTune[mapName].xValues]
                    for i = #newTune[mapName].xValues, 29, 1 do
                        -- newTune[mapName].xValues[i] = val
                        table.insert(newTune[mapName].xValues, i, val + i)
                    end
                end
                if #newTune[mapName].yValues < 15 then
                    local val = newTune[mapName].yValues[#newTune[mapName].yValues]
                    for i = #newTune[mapName].yValues, 14, 1 do
                        -- newTune[mapName].yValues[i] = val
                        table.insert(newTune[mapName].yValues, i, val + i)
                        --newTune[mapName].values["" .. (val + i)] = {}
                        --for _, xVal in ipairs(newTune[mapName].xValues) do
                        --    -- newTune[mapName].xValues[i] = val
                        --    newTune[mapName].values["" .. (val + i)]["" .. xVal] = 0
                        --end
                    end
                end
            end
        end
        return newTune
    end,
    _02To021 = function (oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.21
        for mapName, map in pairs(oldTune) do
            if type(map) == "table" and map.type == '3D' then
                print("Updating map: " .. mapName)
                dump(newTune[mapName].yValues)
                print("---")
                for _, yVal in pairs(newTune[mapName].yValues) do
                    if newTune[mapName].values["" .. yVal] == nil or tablelength(newTune[mapName].values["" .. yVal]) < 30 then
                        dump(newTune[mapName].values["" .. yVal])
                        print("len: " .. (tablelength(newTune[mapName].values["" .. yVal])))
                        if newTune[mapName].values["" .. yVal] == nil then
                            newTune[mapName].values["" .. yVal] = {}
                        end
                        local c = 0
                        for _, xVal in ipairs(newTune[mapName].xValues) do
                            newTune[mapName].values["" .. yVal]["" .. xVal] = 0
                            c = c + 1
                        end
                        print(c)
                    end
                end
            end
        end
        return newTune
    end,
    _021To022 = function (oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.22
        -- add vlr-table
        newTune['vlr-table'] = {
            type = '2D',
            displayName = 'Variable Length Runners Table',
            sectionName = 'PWM',
            unit = '%',
            xName = 'RPM',
            xValues = {400, 500, 600, 700, 800, 1000, 1200, 1500, 1800, 2000, 2200, 2400, 2600, 2800, 3100, 3400, 3700, 4000, 4300, 4700, 5100, 5500, 5900, 6200, 6700, 7200, 7700, 8200, 8700, 9200},
            values = {},
            cellsMin = 0,
            cellsMax = 100,
            cellsRedValue = 100,
        }
        for _, xVal in ipairs(newTune['vlr-table'].xValues) do
            newTune['vlr-table'].values["" .. xVal] = 0
        end
        return newTune
    end,
    _022To03 = function (oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.3
        -- add boost-table
        --[[
            createTable3D(
                'Boost Table', 'PSI', 'boost', 'boost-table',
                'RPM', [600, 1200, 1800, 2400, 2800, 3400, 4000, 4700, 5500, 6200, 7200, 8200].sort((a, b) => a - b),
                'TPS', [100, 90, 75, 60, 45, 20, 10, 0].sort((a, b) => b - a),
                0, 255, 40
            );
        ]]
        newTune['boost-table'] = {
            type = '3D',
            displayName = 'Boost Table',
            sectionName = 'boost',
            unit = 'PSI',
            xName = 'RPM',
            xValues = {600, 1200, 1800, 2400, 2800, 3400, 4000, 4700, 5500, 6200, 7200, 8200},
            yName = 'TPS',
            yValues = {100, 90, 75, 60, 45, 20, 10, 0},
            values = {},
            cellsMin = 0,
            cellsMax = 255,
            cellsRedValue = 40,
        }
        -- fill all values to 0
        for _, yVal in ipairs(newTune['boost-table'].yValues) do
            newTune['boost-table'].values["" .. yVal] = {}
            for _, xVal in ipairs(newTune['boost-table'].xValues) do
                newTune['boost-table'].values["" .. yVal]["" .. xVal] = 0
            end
        end
        return newTune
    end,
    _03To031 = function(oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.31
        --createOption('Drive-by-Wire Idle Throttle Opening', '%', 'options', 'dbw-idle-throttle', 'number', 0.1, 0, 25, 5);
        newTune.options['dbw-idle-throttle'] = {
            value = 5,
            unit = "%",
            displayName = "Drive-by-Wire Idle Throttle Opening",
            sectionName = "options",
            optionName = "dbw-idle-throttle",
            optionType = "number",
            step = "0.1",
            minimum = 0,
            maximum = 25,
            redValue = 10,
        }
        return newTune
    end,
    _031To04 = function(oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.4
        -- ADD accelerator position table
        --[[
            createTable3D(
                'Accelerator Position', '%', 'PWM', 'accelerator-position-table',
                'RPM', [400, 500, 600, 700, 800, 1000, 1200, 1500, 1800, 2000, 2200, 2400, 2600, 2800, 3100, 3400, 3700, 4000, 4300, 4700, 5100, 5500, 5900, 6200, 6700, 7200, 7700, 8200, 8700, 9200].sort((a, b) => a - b),
                'TPS', [100, 93, 86, 79, 72, 65, 58, 51, 44, 37, 30, 23, 16, 9, 2].sort((a, b) => b - a),
                0, 100, 100
            );
        ]]
        newTune['accelerator-position-table'] = {
            type = '3D',
            displayName = 'Accelerator Position',
            sectionName = 'accelerator',
            unit = '%',
            xName = 'RPM',
            xValues = {600, 1200, 1800, 2400, 2800, 3400, 4000, 4700, 5500, 6200, 7200, 8200},
            yName = 'TPS',
            yValues = {100, 90, 75, 60, 45, 20, 10, 0},
            values = {},
            cellsMin = 0,
            cellsMax = 100,
            cellsRedValue = 100,
        }

        -- fill all values by row to the same value as the TPS
        newTune['accelerator-position-table'].values = fillTable3D(newTune['accelerator-position-table'], function(_, yVal) return yVal end)

        -- add after start enrichment 2d table
        --[[
            createTable2D(
                'After Start Enrichment', '%', 'injector', 'after-start-enrichment-table',
                'Coolant ºC', [-20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 140],
                1, 3, 2
            );
        ]]
        newTune['after-start-enrichment-table'] = {
            type = '2D',
            displayName = 'After Start Enrichment',
            sectionName = 'injector',
            unit = '%',
            xName = 'Coolant ºC',
            xValues = {-20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 140}, --TODO: testare il lookup su valori negativi
            values = {},
            cellsMin = 1,
            cellsMax = 3,
            cellsRedValue = 2,
        }

        -- fill newTune['after-start-enrichment-table'].values
        newTune['after-start-enrichment-table'].values["-20"] = 3
        newTune['after-start-enrichment-table'].values["-10"] = 2
        newTune['after-start-enrichment-table'].values["0"] = 1.9
        newTune['after-start-enrichment-table'].values["10"] = 1.9
        newTune['after-start-enrichment-table'].values["20"] = 1.75
        newTune['after-start-enrichment-table'].values["30"] = 1.65
        newTune['after-start-enrichment-table'].values["40"] = 1.55
        newTune['after-start-enrichment-table'].values["50"] = 1.35
        newTune['after-start-enrichment-table'].values["60"] = 1.2
        newTune['after-start-enrichment-table'].values["70"] = 1.1
        newTune['after-start-enrichment-table'].values["80"] = 1
        newTune['after-start-enrichment-table'].values["140"] = 1


        --  Add IAT temperature compensation table
        --[[
            createTable2D(
                'IAT Temperature Compensation', 'ºC', 'injector', 'iat-injection-compensation-table',
                'IAT ºC', [-20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 140],
                0.5, 1.5, 1
            );
        ]]

        newTune['iat-injection-compensation-table'] = {
            type = '2D',
            displayName = 'IAT Temperature Compensation',
            sectionName = 'injector',
            unit = 'ºC',
            xName = 'IAT ºC',
            xValues = {-20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 140},
            values = {},
            cellsMin = 0.5,
            cellsMax = 1.5,
            cellsRedValue = 1,
        }

        -- fill newTune['iat-temperature-compensation-table'].values to 1
        newTune['iat-injection-compensation-table'].values = fillTable2D(newTune['iat-injection-compensation-table'], 1)
        -- add iat timing compensation 
        --[[
            createTable2D(
                'IAT Timing Compensation', 'ºC', 'ignition', 'iat-timing-compensation-table',
                'IAT ºC', [-20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 140],
                -15, 15, 5
            );
        ]]
        newTune['iat-timing-compensation-table'] = {
            type = '2D',
            displayName = 'IAT Timing Compensation',
            sectionName = 'ignition',
            unit = 'º',
            xName = 'IAT ºC',
            xValues = {-20, -10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 140},
            values = {},
            cellsMin = -15,
            cellsMax = 15,
            cellsRedValue = 5,
        }
        -- fill to 0
        newTune['iat-timing-compensation-table'].values = fillTable2D(newTune['iat-timing-compensation-table'], 0)

        -- add boost cut option
        --[[
            createOption('Boost Cut', 'PSI', 'options', 'boost-cut', 'number', 0, 0, 255, 30);
        ]]

        newTune.options['boost-cut'] = {
            value = 0,
            unit = "PSI",
            displayName = "Boost Cut",
            sectionName = "options",
            optionName = "boost-cut",
            optionType = "number",
            step = "1",
            minimum = 0,
            maximum = 255,
            redValue = 30,
        }

        -- add knock sensor sensitivity option
        --[[
            createOption('Knock Sensor Sensitivity', '%', 'options', 'knock-sensitivity', 'number', 0, 0, 100, 10);
        ]]
        newTune.options['knock-sensitivity'] = {
            value = 20,
            unit = "%",
            displayName = "Knock Sensor Sensitivity",
            sectionName = "options",
            optionName = "knock-sensitivity",
            optionType = "number",
            step = "1",
            minimum = 0,
            maximum = 100,
            redValue = 30,
        }

        -- add knock autoadaptation option
        --[[
            createOption('Knock Autoadaptation Speed', '%', 'options', 'knock-autoadaptation', 'number', 0, 0, 100, 10);
        ]]
        -- newTune.options['knock-autoadaptation-speed'] = {
        --     value = 100,
        --     unit = "%",
        --     displayName = "Knock Autoadaptation Speed",
        --     sectionName = "options",
        --     optionName = "knock-autoadaptation",
        --     optionType = "number",
        --     step = "1",
        --     minimum = 0,
        --     maximum = 100,
        --     redValue = 1000,
        -- }

        -- add knock autoadaptation maximum retard option
        --[[
            createOption('Knock Max Retard', 'º', 'options', 'knock-max-retard', 'number', 0, 0, 40, 10);
        ]]

        newTune.options['knock-max-retard'] = {
            value = 10,
            unit = "º",
            displayName = "Knock Max Retard",
            sectionName = "options",
            optionName = "knock-max-retard",
            optionType = "number",
            step = "1",
            minimum = 0,
            maximum = 40,
            redValue = 10,
        }

        -- add knock autoadaptation 3d table based on MAP and RPM
        --[[
            createTable3D(
                'Knock Autoadaptation', '%', 'autoadapt', 'knock-autoadaptation-table',
                'RPM', [600, 1200, 1800, 2400, 2800, 3400, 4000, 4700, 5500, 6200, 7200, 8200].sort((a, b) => a - b),
                'MAP', [100, 90, 75, 60, 45, 20, 10, 0].sort((a, b) => b - a),
                0, 100, 100
            );
        ]]

        newTune['knock-autoadaptation-table'] = {
            type = '3D',
            displayName = 'Knock Autoadaptation',
            sectionName = 'autoadapt',
            unit = '%',
            xName = 'RPM',
            xValues = {600, 1200, 1800, 2400, 2800, 3400, 4000, 4700, 5500, 6200, 7200, 8200},
            yName = 'MAP',
            yValues = {100, 90, 75, 60, 45, 20, 10, 0},
            values = {},
            cellsMin = 0,
            cellsMax = 100,
            cellsRedValue = 100,
        }

        -- fill all values to 0
        newTune['knock-autoadaptation-table'].values = fillTable3D(newTune['knock-autoadaptation-table'], 0)

        -- add max timing 2D map with knock count as x axis
        --[[
            createTable2D(
                'Max Timing Retard', 'º', 'ignition', 'max-knk-timing-retard-table',
                'Knock Count', [0, 5, 10, 20, 40, 80, 100, 150, 200, 300, 400],
                0, 30, 12
            );
        ]]
        newTune['max-knk-timing-retard-table'] = {
            type = '2D',
            displayName = 'Max Timing Retard',
            sectionName = 'autoadapt',
            unit = 'º',
            xName = 'Knock Count',
            xValues = {0, 5, 10, 20, 40, 80, 100, 150, 200, 300, 400},
            values = {},
            cellsMin = 0,
            cellsMax = 30,
            cellsRedValue = 12,
        }
        -- fill to 0
        newTune['max-knk-timing-retard-table'].values = fillTable2D(newTune['max-knk-timing-retard-table'], 0)
        return newTune
    end,
}

local versionsHistory = {nil, 0.1, 0.2, 0.21, 0.22, 0.3, 0.31, 0.4}

local function updateTuneFile(db, tuneKey, updateToVersion)
    if db == nil or tuneKey == nil or db.tunes == nil or db.tunes[tuneKey] == nil or updateToVersion == nil then
        return nil
    end

    print("Updating " .. tuneKey .. " to version " .. updateToVersion)
    local tune = db.tunes[tuneKey]

    -- Backup the old file in case something goes wrong
    local backupTuneKey = tuneKey .. "_" .. os.time() .. "_backup"
    db.tunes[backupTuneKey] = deepcopy(tune)
    assert(db.tunes[backupTuneKey])

    local newTune = tune
    local currentIndex = 1
    local currentVersion = tune.version or nil
    -- find the index of the current version
    for i, version in pairs(versionsHistory) do
        print("Comparing " .. version .. " to " .. currentVersion)	
        if version == currentVersion or ("" .. version) == ("" .. currentVersion) then
            currentIndex = i
            break
        end
    end

    print("Updating " .. tuneKey .. " from version " .. currentVersion .. " to version " .. updateToVersion)
    while ("" .. currentVersion) ~= ("" .. updateToVersion) do
        local lookupValue = '_' ..
            (tostring(currentVersion):gsub('%.', '') or 'nil') .. "To" .. tostring(versionsHistory[currentIndex + 1]):gsub('%.', '')

        print("Updating from " .. currentVersion .. " to " .. versionsHistory[currentIndex + 1] .. " using " .. lookupValue)
        print("Current index: " .. currentIndex .. " of " .. #versionsHistory .. " versions")
        local updateFunc = updatesLookup[lookupValue]
        if updateFunc == nil then
            print("Failed to find update function for " .. lookupValue)
            return nil
        end

        newTune = updateFunc(newTune)
        if tune == nil then
            print("Failed to update " .. tuneKey .. " to version " .. versionsHistory[currentIndex + 1])
            return nil
        end
        currentIndex = currentIndex + 1

        currentVersion = versionsHistory[currentIndex]
    end

    if newTune == nil then
        print("Failed to update " .. tuneKey .. " to version " .. updateToVersion)
        return nil
    end

    print("Updated " .. tuneKey .. " to version " .. updateToVersion .. " successfully")

    return newTune
end

M.updateTuneFile = updateTuneFile
return M
