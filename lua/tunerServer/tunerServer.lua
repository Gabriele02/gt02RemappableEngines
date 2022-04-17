local M = {}

local outData = {}

local ws = require('utils/simpleHttpServer')
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
  local listenHost = '127.0.0.1'
  local httpListenPort = 42069
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
return M