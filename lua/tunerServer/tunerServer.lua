local M = {}

local commonResponses = {
  _200 = [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close

]],
  _404 = [[HTTP/1.1 404 Not Found
Server: BeamNG.web/0.1.0
Connection: close

]],
  _500 = [[HTTP/1.1 500 Internal Server Error
Server: BeamNG.web/0.1.0
Connection: close

]],
}

local outData = {}
local tuneFileKey = nil
local db = nil
local listenHost = '127.0.0.1'
local httpListenPort = 9696

local tuneUpdated = false

local ws = require('lua.libs.int.simpleHttpServer')
--require('utils/simpleHttpServer')
local handlers = {
  {
    '/engineData.json',
    function()
      local s = jsonEncode(outData)
      return
        [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: keep-alive
Content-Length: ]] .. string.len(s) .. [[

Content-Type: application/json
Access-Control-Allow-Origin: *

]] .. s
    end
  },
  {
    '/js/gauge.min.js',
    function(_, path)
      local body = readFile('js/gauge.min.js')
      return [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len(body) .. [[

Content-Type: text/javascript

]] .. body
    end
  },
  {
    '/js/plotly.js',
    function(_, path)
      local body = readFile('js/plotly.js')
      return [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len(body) .. [[

Content-Type: text/javascript

]] .. body
    end
  },
  {
    '/command',
    function(req, path)
      local commands = split(req.uri.query, '&')
      for index, command in ipairs(commands) do
        local cmd = split(command, '=')
        if cmd[1] == 'RpmOverwrite' then
          RpmOverwrite = tonumber(cmd[2])
        end
        if cmd[1] == 'MapOverwrite' then
          MapOverwrite = tonumber(cmd[2])
        end
        if cmd[1] == 'TuningCheatOverwrite' then
          TuningCheatOverwrite = cmd[2] == 'true'
        end
      end
      return commonResponses._200
    end
  },
  --  add function to receive tune.json and overwrite current tune
  {
    '/saveTune',
    function(req, path)
      if db == nil or req.body == nil then
        return commonResponses._500
      end
      local body = req.body
      local tune = jsonDecode(body)
      print('tune = ' .. tostring(tune))
      if tuneFileKey == nil then
        local respnse = "No tune loaded"
        return [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len(respnse) .. [[

Content-Type: text/html

]] .. respnse
      end
      if tuneFileKey ~= nil then
        if db.tunes == nil then
          db.tunes = {}
        end
        db.tunes[tuneFileKey] = tune
        db:save()
        tuneUpdated = true
      end
      return [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len("body") .. [[

Content-Type: application/json

]] .. "body"
    end
  },
  -- function to return current tune in json format
  {
    '/getTune',
    function(req, path)
      if db == nil then
        return commonResponses._500
      end
      local tune = db.tunes[tuneFileKey]
      if tune == nil then
        return commonResponses._404
      end
      local res = {
        tune = tune,
        tuneFileKey = tuneFileKey,
      }
      local body = jsonEncode(res)
      return [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len(body) .. [[

Content-Type: application/json

]] .. body
    end
  },
  {'/',
    function()
      local body = readFile('tuner.html')
      return [[HTTP/1.1 200 OK
Server: BeamNG.web/0.1.0
Connection: close
Content-Length: ]] .. string.len(body) .. [[

Content-Type: text/html

]] .. body
    end
  },
}

local function reset()
  ws.stop()
  local configFilePath = "mods/yourTunes/tunerServerConfig.txt"
  local configFile = io.open(configFilePath, "r")

  if configFile ~= nil then
    io.input(configFile)
    local configStr = io.read()
    io.close(configFile)

    local config = split(configStr, ':')
    listenHost = config[1]
    httpListenPort = config[2]
  end
  -- dumpToFile("tunerServer.log", "Starting server with config = " .. listenHost .. ":" .. httpListenPort)
  ws.start(listenHost, httpListenPort, '/', handlers,
    function(req, path)
      return {
        httpPort = httpListenPort,
        wsPort = httpListenPort + 1,
        host = listenHost,
      }
    end
  )
end

local function setOutData(lOutData)
  outData = lOutData
end

local function update()
  ws.update()
end

-- public interface
M.reset = reset
M.setOutData = setOutData
M.update = update
M.setTuneFileKey = function(key)
  tuneFileKey = key
end
M.setDB = function(lDb)
  db = lDb
end
M.isTuneUpdated = function()
  local tmp = tuneUpdated
  tuneUpdated = false
  return tmp
end
return M