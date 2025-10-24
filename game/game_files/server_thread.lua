package.path = package.path .. ";lua_modules/share/lua/5.1/?.lua"
package.cpath = package.cpath .. ";lua_modules/lib/lua/5.1/?.dll"

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

function pack_int32_le(num)
    -- Extract the 4 bytes using bitwise operations
    -- Little-endian means the least significant byte comes first
    local b1 = bit.band(num, 0xFF)
    local b2 = bit.band(bit.rshift(num, 8), 0xFF)
    local b3 = bit.band(bit.rshift(num, 16), 0xFF)
    local b4 = bit.band(bit.rshift(num, 24), 0xFF)
    -- Convert the byte numbers into actual characters and join them
    return string.char(b1, b2, b3, b4)
end

while true do
    -- Wait for a client to connect for each new command cycle
    local client = server:accept()

    if client then
        -- Once a client is connected, handle one command-response cycle
        client:settimeout(5) -- Set a timeout to prevent hangs
        
        local command, err = client:receive()

        if command then
            -- 1. Trim whitespace and newlines from the command
            command = command:match("^%s*(.-)%s*$")

            -- 2. Send the clean command to the main game thread ONCE
            tx_channel:push({type = "command", payload = command})
            
            -- 3. Wait for a response from the main game thread
            local response_data = rx_channel:demand()
            
            -- 4. Check the type of response and handle it accordingly
            if response_data and response_data.type == "string" then
                local payload = response_data.payload
                print("Sending response to client:", response_data.payload)
                client:send(pack_int32_le(#payload))
                client:send(payload)
            elseif response_data and response_data.type == "json_blob" then
                local json_str = response_data.payload
                local response_size = #json_str
                
                -- Log the size for debugging
                tx_channel:push({type="log", payload="Server thread: Sending JSON blob of size: " .. tostring(response_size)})

                -- 1. Send the total size first, so Python knows what to expect
                client:send(pack_int32_le(response_size))

                -- 2. Send the actual data in small chunks to avoid blocking
                local chunk_size = 4096 -- Send 4KB at a time
                for i = 1, response_size, chunk_size do
                    client:send(string.sub(json_str, i, i + chunk_size - 1))
                end
            else
                local err_msg = "Error: Unknown or invalid response type from game."
                client:send(pack_int32_le(#err_msg))
                client:send(err_msg)
            end
        end

        -- Close the connection immediately after responding
        client:close()
    end
    
    -- Check for the quit signal
    if tx_channel:getCount() > 0 and tx_channel:peek() == "QUIT" then
        server:close()
        return
    end
end