local skynet        = require "skynet"
local socket        = require "skynet.socket"
local httpd         = require "http.httpd"
local sockethelper  = require "http.sockethelper"
local urllib        = require "http.url"
local json          = require "cjson"
local util          = require "util"

local table = table
local string = string

local mode, server_path, port, preload = ...
local server = require(server_path) 
local port = tonumber(port)
local preload = preload and tonumber(preload) or 20

if mode == "agent" then

-- 如果是非字符串，server需要提供pack和unpack方法
server.pack = server.pack or function (_, data)
    return data
end
server.unpack = server.unpack or function (_, data)
    return data
end

function on_message(cmd, data)
    if server[cmd] then
        local ret = server[cmd](server, server:unpack(data))
        server:pack(ret or "")
    else
        return "error"
    end
end

local function response(id, ...)
    local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
    if not ok then
        -- if err == sockethelper.socket_error , that means socket closed.
        skynet.error(string.format("fd = %d, %s", id, err))
    end
end

skynet.start(function()
    skynet.dispatch("lua", function (_,_,id)
        socket.start(id)
        -- limit request body size to 8192 (you can pass nil to unlimit)
        local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8192)
        if code then
            if code ~= 200 then
                response(id, code)
            else
                local data 
                local path, query = urllib.parse(url)
                local cmd = string.match(path, "([^/]+)$")        
                if query then
                    data = urllib.parse_query(query)
                end

                response(id, code, on_message(cmd, data, body), {["Access-Control-Allow-Origin"] = "*"})
            end
        else
            if url == sockethelper.socket_error then
                skynet.error("socket closed")
            else
                skynet.error(url)
            end
        end
        socket.close(id)
    end)
end)

elseif mode == "gate" then

skynet.start(function()
    local agent = {}
    for i= 1, preload do
        agent[i] = skynet.newservice(SERVICE_NAME, "agent", server_path, port)
    end
    local balance = 1
    
    local id = socket.listen("0.0.0.0", port)
    socket.start(id , function(id, addr)
        --skynet.error(string.format("%s connected, pass it to agent :%08x", addr, agent[balance]))
        skynet.send(agent[balance], "lua", id)
        balance = balance + 1
        if balance > #agent then
            balance = 1
        end
    end)
end)

else
    assert(false, "mode error")
end
