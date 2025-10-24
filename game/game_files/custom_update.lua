local CommandHandler = require "command_handler"

local CustomUpdate = {}

function CustomUpdate.update(dt)

    -- Server command handling
    if G.SERVER_TX_CHANNEL then
        local command_data = G.SERVER_TX_CHANNEL:pop()
        if command_data and command_data.type == "command" then
            local command = command_data.payload
            print("Received command from server thread: " .. command)

            local response = CommandHandler.process(command)
            
            G.SERVER_RX_CHANNEL:push(response)
        end
    end
end

return CustomUpdate