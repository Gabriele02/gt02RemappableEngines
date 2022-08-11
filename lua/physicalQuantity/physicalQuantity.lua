local M = {}
M.physicalQuantityType = "physicalquantity"
M.__moduleName__ = "PhysicalQuantity"
M.__author__ = "gt02"
M.__version__ = "0.0.1"

local UNITS = {}

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function pdump(o)
    print(dump(o))
end

local function findInTable(t, val)
    for index, v in ipairs(t) do
        if v == val then
            return index
        end
    end
    return nil
end

local function areUnitsEqual(a, b)
    local an = { table.unpack(a.numerator) }
    local ad = { table.unpack(a.denominator) }

    local bn = { table.unpack(b.numerator) }
    local bd = { table.unpack(b.denominator) }

    local occurrences = {n = {}, d = {}}
    for _index, unit in ipairs(an) do
        if occurrences.n[unit] == nil then
            occurrences.n[unit] = 0
        end
        occurrences.n[unit] = occurrences.n[unit] + 1
    end
    for _index, unit in ipairs(bn) do
        if occurrences.n[unit] == nil then
            occurrences.n[unit] = 0
        end
        occurrences.n[unit] = occurrences.n[unit] - 1
    end
    for _index, unit in ipairs(ad) do
        if occurrences.d[unit] == nil then
            occurrences.d[unit] = 0
        end
        occurrences.d[unit] = occurrences.d[unit] + 1
    end
    for _index, unit in ipairs(bd) do
        if occurrences.d[unit] == nil then
            occurrences.d[unit] = 0
        end
        occurrences.d[unit] = occurrences.d[unit] - 1
    end
    for unit, occ in pairs(occurrences.d) do
        if occ ~= 0 then
            return false
        end
    end
    for unit, occ in pairs(occurrences.n) do
        if occ ~= 0 then
            return false
        end
    end
    return true
end

local function unitsToString(units)
    local str = ""
    for _index, unit in ipairs(units.numerator) do
        str = str .. unit .. "*"
    end
    str = str.sub(str, 1, #str - 1)
    if #units.numerator == 0 then
        str = str .. "1"
    end
    if #units.denominator == 0 then
        return str
    end

    str = str .. "/"
    for _index, unit in ipairs(units.denominator) do
        str = str .. unit .. "*"
    end
    str = str.sub(str, 1, #str - 1)
    return str
end

local function newUnit(name, symbol, numerator, denominator)
    if (numerator == nil and denominator == nil) then
        error("Both numerator and denominator are nil")
        return nil
    end
    return {
        name = name,
        symbol = symbol,
        numerator = numerator,
        denominator = denominator
    }
end

local function addUnit(name, symbol, numerator, denominator)
    -- TODO: check ifl symbol is unique
    if (UNITS[symbol] ~= nil) then
        error("Cannot overwrite units: unit " .. symbol .. " already exists!")
        return nil
    end
    UNITS[symbol] = newUnit(name, symbol, numerator, denominator)
end

local function simplifyUnits(u)
    local n = { table.unpack(u.numerator) }
    local d = { table.unpack(u.denominator) }
    local retUnits = {
        name = "", -- TODO: set
        symbol = "", -- TODO: set
        numerator = {},
        denominator = {}
    }
    local occurrences = {}
    for _index, unit in ipairs(n) do
        if occurrences[unit] == nil then
            occurrences[unit] = 0
        end
        occurrences[unit] = occurrences[unit] + 1
    end
    for _index, unit in ipairs(d) do
        if occurrences[unit] == nil then
            occurrences[unit] = 0
        end
        occurrences[unit] = occurrences[unit] - 1
    end
    for unit, occ in pairs(occurrences) do
        if occ > 0 then
            for i = 1, occ, 1 do
                table.insert(retUnits.numerator, unit)
            end
        elseif occ < 0 then
            for i = 1, -occ, 1 do
                table.insert(retUnits.denominator, unit)
            end
        end
    end
    return retUnits
end

local function explodeUnit(unitSymbol)
    if UNITS[unitSymbol] == nil then
        error("Unknown unit " .. unitSymbol)
        return nil
    end
    return UNITS[unitSymbol]
end

local function isPhysicalQuantity(toTest)
    return type(toTest) == "table" and toTest.type == M.physicalQuantityType
end

-- base units
-- time
addUnit("second", "s", { "s" })

-- length
-- addUnit("millimeters", {"mm"})
-- addUnit("centimeters", {"cm"})
-- addUnit("decimeters", {"dm"})
addUnit("metre", "m", { "m" })
-- addUnit("kilometers", {"km"})

-- mass
addUnit("kilogram", "kg", { "kg" })

-- temperature
addUnit("kelvin", "K", { "K" })

-- amount of substance
addUnit("mole", "mol", { "mol" })


-- Derived units
-- angle
addUnit("radiant", "rad", { "m" }, { "m" })

-- force, weight
addUnit("newton", "N", { "kg", "m" }, { "s", "s" })

-- pressure, stress
addUnit("pascal", "Pa", { "kg" }, { "m", "s", "s" })

-- energy, work, heat
addUnit("joule", "J", { "kg", "m", "m" }, { "s", "s" })

-- power
addUnit("watt", "W", { "kg", "m", "m" }, { "s", "s", "s" })

local function newPhysicalQuantity(val, unit)
    local n = {}
    local d = {}
    if type(unit) == "string" then
        local u = explodeUnit(unit)
        if u == nil then
            return nil
        end
        n = u.numerator
        d = u.denominator
    elseif type(unit) == "table" then
        if (unit[1] == nil) then
            unit[1] = {}
        end
        if (unit[2] == nil) then
            unit[2] = {}
        end
        n = { table.unpack(unit[1]) }
        for _index, value in ipairs(n) do
            if UNITS[value] == nil then
                error("Unknown unit: " .. value)
                return nil
            end
        end
        d = { table.unpack(unit[2]) }
        for _index, value in ipairs(d) do
            if UNITS[value] == nil then
                error("Unknown unit: " .. value)
                return nil
            end
        end
    end
    -- print(dump(n))
    -- print(dump(d))
    PhysicalQuantity = {}
    local physicalQuantity = {
        type = M.physicalQuantityType,
        value = val,
        units = {
            name = "", -- TODO: set
            symbol = "", -- TODO: set
            numerator = n,
            denominator = d
        }
    }
    PhysicalQuantity.mt = {
        __add      = function(lhs, rhs)
            if type(lhs) == "number" or type(rhs) == "number" then
                error("Cannot add a pure number to a Physical Quantity!")
                return nil
            end
            if areUnitsEqual(lhs.units, rhs.units) then
                return newPhysicalQuantity(lhs.value + rhs.value, lhs.units)
            else
                error("Incompatible units: " .. unitsToString(lhs.units) .. " and " .. unitsToString(rhs.units), 2)
            end
        end,
        __sub      = function(lhs, rhs)
            if type(lhs) == "number" or type(rhs) == "number" then
                error("Cannot subtract a pure number to a Physical Quantity!")
                return nil
            end
            if areUnitsEqual(lhs.units, rhs.units) then
                return newPhysicalQuantity(lhs.value - rhs.value, lhs.units)
            else
                error("Incompatible units: " .. unitsToString(lhs.units) .. " and " .. unitsToString(rhs.units), 2)
            end
        end,
        __mul      = function(lhs, rhs)
            if type(lhs) == "number" and isPhysicalQuantity(rhs) then
                return newPhysicalQuantity(lhs * rhs.value, { rhs.units.numerator, rhs.units.denominator })
            end
            if isPhysicalQuantity(lhs) and type(rhs) == "number" then
                return newPhysicalQuantity(lhs.value * rhs, { lhs.units.numerator, lhs.units.denominator })
            end
            if isPhysicalQuantity(lhs) and isPhysicalQuantity(rhs) then
                local retUnits = {
                    name = "", -- TODO: set
                    symbol = "", -- TODO: set
                    numerator = {},
                    denominator = {}
                }
                for _index, u in ipairs(lhs.units.numerator) do
                    table.insert(retUnits.numerator, u)
                end
                for _index, u in ipairs(rhs.units.numerator) do
                    table.insert(retUnits.numerator, u)
                end

                for _index, u in ipairs(lhs.units.denominator) do
                    table.insert(retUnits.denominator, u)
                end
                for _index, u in ipairs(rhs.units.denominator) do
                    table.insert(retUnits.denominator, u)
                end

                retUnits = simplifyUnits(retUnits)
                return newPhysicalQuantity(lhs.value * rhs.value, { retUnits.numerator, retUnits.denominator })
            end
            error("Incompatible types: " .. type(lhs) .. " and " .. type(rhs))
            return nil
        end,
        __div      = function(lhs, rhs)
            if type(lhs) == "number" and isPhysicalQuantity(rhs) then
                return newPhysicalQuantity(lhs / rhs.value, { rhs.units.numerator, rhs.units.denominator })
            end
            if isPhysicalQuantity(lhs) and type(rhs) == "number" then
                return newPhysicalQuantity(lhs.value / rhs, { lhs.units.numerator, lhs.units.denominator })
            end
            if isPhysicalQuantity(lhs) and isPhysicalQuantity(rhs) then
                local retUnits = {
                    name = "", -- TODO: set
                    symbol = "", -- TODO: set
                    numerator = {},
                    denominator = {}
                }
                for _index, u in ipairs(lhs.units.numerator) do
                    table.insert(retUnits.numerator, u)
                end
                for _index, u in ipairs(lhs.units.denominator) do
                    table.insert(retUnits.denominator, u)
                end

                for _index, u in ipairs(rhs.units.numerator) do
                    table.insert(retUnits.denominator, u)
                end
                for _index, u in ipairs(rhs.units.denominator) do
                    table.insert(retUnits.numerator, u)
                end

                retUnits = simplifyUnits(retUnits)
                return newPhysicalQuantity(lhs.value / rhs.value, { retUnits.numerator, retUnits.denominator })
            end
            error("Incompatible types: " .. type(lhs) .. " and " .. type(rhs))
            return nil
        end,
        __eq       = function(lhs, rhs)
            return isPhysicalQuantity(lhs) and isPhysicalQuantity(rhs) and areUnitsEqual(lhs.units, rhs.units) and lhs.value == rhs.value
        end,
        __tostring = function(pq)
            return pq.value .. '[' .. unitsToString(pq.units) .. ']'
        end,
        __concat   = function(lhs, rhs)
            if isPhysicalQuantity(lhs) and isPhysicalQuantity(rhs) then
                return PhysicalQuantity.mt.__tostring(lhs) .. PhysicalQuantity.mt.__tostring(rhs)
            end

            if isPhysicalQuantity(lhs) then
                return PhysicalQuantity.mt.__tostring(lhs) .. rhs
            end

            if isPhysicalQuantity(rhs) then
                return lhs .. PhysicalQuantity.mt.__tostring(rhs)
            end
        end

    }
    setmetatable(physicalQuantity, PhysicalQuantity.mt)
    return physicalQuantity
end

M.UNITS = UNITS
M.new = newPhysicalQuantity
M.areUnitsEqual = areUnitsEqual
M.explodeUnit = explodeUnit
M.unitsToString = unitsToString
return M
