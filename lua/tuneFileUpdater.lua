local M = {}
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
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
    end
}
local multipleUpdatesLookup = {
    --#region To 0.2
    _nilTo02 = function(oldTune)
        local tune01 = updatesLookup['_nilTo01'](oldTune)
        local tune02 = updatesLookup['_01To02'](tune01)
        return tune02
    end,
    --#endregion To 0.2


    --#region To 0.21
    _nilTo021 = function(oldTune)
        local tune01 = updatesLookup['_nilTo01'](oldTune)

        local tune02 = updatesLookup['_01To02'](tune01)

        local tune021 = updatesLookup['_02To021'](tune02)

        return tune021
    end,
    _01To021 = function(oldTune)
        local tune02 = updatesLookup['_01To02'](oldTune)
        local tune021 = updatesLookup['_02To021'](tune02)
        return tune021
    end,
    --#endregion To 0.21
}

local function updateTuneFile(tuneFilePath, updateToVersion)
    if tuneFilePath == nil or updateToVersion == nil then
        return nil
    end

    print("Updating " .. tuneFilePath .. " to version " .. updateToVersion)
    local tuneFile = io.open(tuneFilePath, "r")
    assert(tuneFile)

    io.input(tuneFile)
    local tuneStr = io.read()
    io.close(tuneFile)
    local tune = jsonDecode(tuneStr, 'tune-json-decode')

    -- Backup the old file in case something goes wrong
    local backupFile = io.open(tuneFilePath:sub(1, -(string.len(".json"))) .. "_" .. os.time() .. ".json", "w")
    assert(backupFile)

    io.output(backupFile)
    io.write(tuneStr)
    io.close(backupFile)

    local lookupValue = '_' ..
        (tostring(tune.version):gsub('%.', '') or 'nil') .. "To" .. tostring(updateToVersion):gsub('%.', '')
    local updateFunc = updatesLookup[lookupValue]
    local newTune = nil
    print("Updating :" .. lookupValue)
    if updateFunc == nil then
        newTune = multipleUpdatesLookup[lookupValue](tune)
    else
        newTune = updateFunc(tune)
    end

    local newTuneFile = io.open(tuneFilePath, "w")
    io.output(newTuneFile)
    io.write(jsonEncode(newTune))
    io.close(newTuneFile)

end

M.updateTuneFile = updateTuneFile
return M
