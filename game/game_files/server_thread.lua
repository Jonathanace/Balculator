-- Add these lines to the VERY TOP of the thread script
package.path = package.path .. ";lua_modules/share/lua/5.1/?.lua"
package.cpath = package.cpath .. ";lua_modules/lib/lua/5.1/?.dll"

-- Now, require the libraries
local socket = require("socket")
local love = require("love")

-- --- Configuration ---
local TX_CHANNEL_NAME = "server_tx_commands"
local RX_CHANNEL_NAME = "server_rx_response"
local PORT = 12345
-- ---------------------

local server = assert(socket.bind("*", PORT))
local tx_channel = love.thread.getChannel(TX_CHANNEL_NAME)
local rx_channel = love.thread.getChannel(RX_CHANNEL_NAME)

-- Push a success message to the main thread's log
tx_channel:push({type="log", payload="--- LuaSocket server thread is running on port " .. PORT .. " ---"})

server:settimeout(0.1)

while true do
    if tx_channel:getCount() > 0 and tx_channel:peek() == "QUIT" then
        server:close()
        return
    end

    local client = server:accept()

    if client then
        client:settimeout(nil)
        while true do
            local command, err = client:receive()
            if not command then break end
            
            tx_channel:push({type = "command", payload = command})
            local response_data = rx_channel:demand()
            local response_str = "Error: Game did not respond."
            
            if response_data and response_data.response then
                response_str = response_data.response
            end

            client:send(response_str .. "\n")
        end
        client:close()
    end
end