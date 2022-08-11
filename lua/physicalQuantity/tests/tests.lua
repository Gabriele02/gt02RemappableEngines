-- physical quantity module tests
package.path = package.path .. ";..\\?.lua"
_PROMPT = ' physicalQuantityTests> '

local passed = 0
local failed = 0

local function reportPassedAndFailed()
    print("######################################")
    print("PASSED: " .. passed .. " / " .. (passed + failed))
    print("FAILED: " .. failed .. " / " .. (passed + failed))
    print("######################################")
end

local pq = require "..\\physicalQuantity"

local a = pq.new(1, { { "m" }, { "s" } })
local b = pq.new(1, { { "m" }, { "s" } })
local c = pq.new(1, { { "m" }, { "s", "s" } })
local d = pq.new(1, { { "kg", "m" }, { "s" } })

print("\n\nTESTING metamethods '__tostring' and '__concat'")
print(a .. " ok!")

local function testAreUnitsEqual(la, lb, expected)
    local result = pq.areUnitsEqual(la.units, lb.units)
    print(la .. " =[units]= " .. lb .. " => " .. (result and "true" or "false") .. ", expected: " .. (expected and "true" or "false"))
    local ok = result == expected
    passed = passed + (ok and 1 or 0)
    failed = failed + (ok and 0 or 1)
    print("TEST " .. (ok and "PASSED" or "############## FAILED ##############"))
end

print("\n\nTESTING function 'areUnitsEqual:'")
print("a")
testAreUnitsEqual(a, a, true)
testAreUnitsEqual(a, b, true)
testAreUnitsEqual(a, c, false)
testAreUnitsEqual(a, d, false)

print("b")
testAreUnitsEqual(b, a, true)
testAreUnitsEqual(b, b, true)
testAreUnitsEqual(b, c, false)
testAreUnitsEqual(b, d, false)

print("c")
testAreUnitsEqual(c, a, false)
testAreUnitsEqual(c, b, false)
testAreUnitsEqual(c, c, true)
testAreUnitsEqual(c, d, false)

print("d")
testAreUnitsEqual(d, a, false)
testAreUnitsEqual(d, b, false)
testAreUnitsEqual(d, c, false)
testAreUnitsEqual(d, d, true)


local function testMultiplication(la, lb, expected)
    local result = la * lb
    print(la .. " * " .. lb .. " => " .. (result or "nil") .. ", expected: " .. expected)
    local ok = result == expected
    passed = passed + (ok and 1 or 0)
    failed = failed + (ok and 0 or 1)
    print("TEST " .. (ok and "true" or "false") and "PASSED" or "############## FAILED ##############")
end

print("\n\nTESTING multiplication")
local e = pq.new(2, { { "kg", "m" }, { "s", "s" } })
local f = pq.new(3, { { "m" } })
local g = pq.new(6, { { "kg", "m", "m" }, { "s", "s" } })

testMultiplication(e, f, g)


local function testDivision(la, lb, expected)
    local result = la / lb
    print(la .. " / " .. lb .. " => " .. (result or "nil") .. ", expected: " .. expected)
    local ok = result == expected
    passed = passed + (ok and 1 or 0)
    failed = failed + (ok and 0 or 1)
    print("TEST " .. (ok and "PASSED" or "############## FAILED ##############"))
end

print("\n\nTESTING division")
local h = pq.new(6, { { "m" } })
local i = pq.new(2, { { "m" }, { "s" } })
local j = pq.new(3, { { "s" } })

testDivision(h, i, j)


local function testExplodeUnits(unitStr, expected)
    local result = pq.explodeUnit(unitStr)
    print(unitStr .. " => " .. (pq.unitsToString(result) or "nil") .. ", expected: " .. pq.unitsToString(expected))
    local ok = pq.areUnitsEqual(result, expected)
    passed = passed + (ok and 1 or 0)
    failed = failed + (ok and 0 or 1)
    print("TEST " .. (ok and "PASSED" or "############## FAILED ##############"))
end

print("\n\nTESTING explodeUnits")

testExplodeUnits("N", { numerator = { "kg", "m" }, denominator = { "s", "s" } })
testExplodeUnits("W", { numerator = { "kg", "m", "m" }, denominator = { "s", "s", "s" } })

local k = pq.new(5, "N")
local l = pq.new(5, { { "kg", "m" }, { "s", "s" } })
local m = pq.new(5, "W")
local n = pq.new(5, { { "kg", "m" }, { "s", "Pa" } })
local o = pq.new(5, "W")
local p = pq.new(5, "N")

testAreUnitsEqual(k, l, true)
testAreUnitsEqual(m, n, false)
testAreUnitsEqual(o, p, false)


-------------------------------------------------------
reportPassedAndFailed()
