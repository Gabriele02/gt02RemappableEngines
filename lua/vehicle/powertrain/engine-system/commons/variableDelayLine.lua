-- Based on delayLine.lua from BeamNG.drive

local push = function(self, payload, delay)
    table.insert(self.data, payload)
    table.insert(self.times, self.currentTime + delay)
    self.length = self.length + 1
  end
  
  local pop = function(self, dt)
    self.currentTime = self.currentTime + dt
    if self.length == 0 then return nil end
  
    local delayedData = {}
    local finishedKeysCount = 0
    for i = 1, self.length, 1 do
      if self.times[i] <= self.currentTime then
        table.insert(delayedData, self.data[i])
        finishedKeysCount = finishedKeysCount + 1
      end
    end
  
    for _ = 1, finishedKeysCount, 1 do
      table.remove(self.data, 1)
      table.remove(self.times, 1)
      self.length = self.length - 1
    end
  
    return delayedData
  end
  
  local popSum = function(self, dt)
    self.currentTime = self.currentTime + dt
    if self.length == 0 then return 0 end
  
    local dataSum = 0
    local finishedKeysCount = 0
    for i = 1, self.length, 1 do
      if self.times[i] <= self.currentTime then
        dataSum = dataSum + self.data[i]
        finishedKeysCount = finishedKeysCount + 1
      else
        break
      end
    end
  
    for _ = 1, finishedKeysCount, 1 do
      table.remove(self.data, 1)
      table.remove(self.times, 1)
      self.length = self.length - 1
    end
  
    return dataSum
  end
  
  local peek = function(self, dt)
    if self.length == 0 then return nil end
  
    local delayedData = {}
    for i = 1, self.length, 1 do
      if self.times[i] <= self.currentTime + dt then
        table.insert(delayedData, self.data[i])
      end
    end
  
    return delayedData
  end
  
  local function reset(self)
    self.length = 0
    self.currentTime = 0
    self.data = {}
    self.times = {}
  end
  
  local methods = {
    push = push,
    peek = peek,
    pop = pop,
    popSum = popSum,
    reset = reset,
  }
  
  local new = function()
    local r = {length = 0, currentTime = 0, data = {}, times = {}}
  
    return setmetatable(r, {__index = methods})
  end
  
  return {
    new = new,
  }
  