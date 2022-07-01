-- physical quantity module tests
package.path = package.path .. ";..\\?.lua"
_PROMPT=' physicalQuantityTests> '

local pq = require "..\\physicalQuantity"

local a = pq.new(1, {{"m"}, {"s"}})
local b = pq.new(1, {{"m"}, {"s"}})
local c = pq.new(1, {{"m"}, {"s", "s"}})
local d = pq.new(1, {{"kg", "m"}, {"s"}})

print("TESTING metamethods '__tostring' and '__concat'")
print(a .. " ok!")

local function testAreUnitsEqual(la, lb, expected)
    local result = pq.areUnitsEqual(la.units, lb.units)
    print(la .. " =[units]= " .. lb .. " => " .. (result and "true" or "false") .. ", expected: " .. (expected and "true" or "false"))
    print("TEST " .. (result == expected and "PASSED" or "############## FAILED ##############"))
end

print("TESTING function 'areUnitsEqual:'")
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


