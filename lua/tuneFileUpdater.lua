local M = {}
local updatesLookup = {
    nilTo01 = function (oldTune)
        local newTune = deepcopy(oldTune)
        newTune.version = 0.1
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
    end
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

    local lookupValue = (tune.version or 'nil') .. "To" .. (tostring(updateToVersion):gsub('%.', ''))
    local newTune = updatesLookup[lookupValue](tune)

    local newTuneFile = io.open(tuneFilePath, "w")
    io.output(newTuneFile)
    io.write(jsonEncode(newTune))
    io.close(newTuneFile)

end

M.updateTuneFile = updateTuneFile
return M