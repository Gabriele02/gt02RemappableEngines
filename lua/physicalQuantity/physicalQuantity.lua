local M = {}
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
    -- pdump(a)
    -- pdump(b)
    if #a.numerator ~= #b.numerator or #a.denominator ~= #b.denominator then
        return false
    end
    for _index, unit in ipairs(a.numerator) do
        if findInTable(b.numerator, unit) == nil then
            return false
        end
    end
    for _index, unit in ipairs(a.denominator) do
        if findInTable(b.denominator, unit) == nil then
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
    if (UNITS[name] ~= nil) then
        error("Cannot overwrite units: unit " .. name .. " already exists!")
        return nil
    end
    UNITS[name] = newUnit(name, symbol, numerator, denominator)
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
-- print(dump(unit))
    local n = { table.unpack(unit[1]) }
    local d = { table.unpack(unit[2]) }
    -- print(dump(n))
    -- print(dump(d))
    PhysicalQuantity = {}
    local physicalQuantity = {
        type = "physicalQuantity",
        value = val,
        units = {
            numerator = n,
            denominator = d
        },
    }
    PhysicalQuantity.mt = {
        __add      = function(lhs, rhs)
            if areUnitsEqual(lhs.units, rhs.units) then
                local ret = {
                    value = lhs.value + rhs.value,
                    units = {
                        numerator = lhs.units.numerator,
                        denominator = lhs.units.denominator
                    }
                }
                setmetatable(ret, PhysicalQuantity.mt)
                return ret
            else
                error("Incompatible units: " .. lhs.units.numerator .. "/" .. lhs.units.denominator .. " and " .. rhs.units.numerator .. "/" .. rhs.units.denominator, 2)
            end
        end,
        __sub      = function(lhs, rhs)
            if lhs.units.numerator == rhs.units.numerator and lhs.units.denominator == rhs.units.denominator then
                local ret = {
                    value = lhs.value - rhs.value,
                    units = {
                        numerator = lhs.units.numerator,
                        denominator = lhs.units.denominator
                    }
                }
                setmetatable(ret, PhysicalQuantity.mt)
                return ret
            else
                error("Incompatible units: " .. lhs.units.numerator .. "/" .. lhs.units.denominator .. " and " .. rhs.units.numerator .. "/" .. rhs.units.denominator, 2)
            end
        end,
        __mul      = function(lhs, rhs)
            local ret = {
                value = lhs.value + rhs.value,
                units = {
                    numerator = lhs.units.numerator + rhs.units.numerator,
                    denominator = lhs.units.denominator + lhs.units.denominator
                }
            }
            setmetatable(ret, PhysicalQuantity.mt)
            return ret
        end,
        __tostring = function(val)
            return val.value .. '[' .. unitsToString(val.units) .. ']'
        end,
        __concat   = function(lhs, rhs)
            if lhs.type == "physicalQuantity" and rhs.type == "physicalQuantity" then
                return PhysicalQuantity.mt.__tostring(lhs) .. PhysicalQuantity.mt.__tostring(rhs)
            end

            if lhs.type == "physicalQuantity" then
                return PhysicalQuantity.mt.__tostring(lhs) .. rhs
            end

            if rhs.type == "physicalQuantity" then
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

return M
