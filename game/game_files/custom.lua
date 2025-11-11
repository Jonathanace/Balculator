-- custom.lua
local json = require "json"

-------------------------------------------------
-- API WRAPPER FUNCTIONS (Local)
-------------------------------------------------
local function api_click_button(args)
    local button_id = args[1] -- "Small", "Big", or "Boss"
    if not button_id then
        return { status = "error", message = "No button ID provided" }
    end
    local button_object = G.blind_select_opts[string.lower(button_id)]
    if not button_object then
        return { status = "error", message = "Could not find button: " .. button_id }
    end
    local clickable_part = button_object:get_UIE_by_ID('select_blind_button')
    if not clickable_part then
        clickable_part = button_object
    end
    if clickable_part and clickable_part.on_click then
        clickable_part:on_click(clickable_part)
    elseif clickable_part and clickable_part.on_press then
        clickable_part:on_press(clickable_part)
    else
        return { status = "error", message = "Found button, but it has no click handler: " .. button_id }
    end
    return { status = "success", clicked = button_id }
end

local function api_start_run(args)
    G.FUNCS.start_setup_run(nil)
    return { status = "success", message = "New run started" }
end

local function api_log(args)
    if args and args[1] then
        print("LUA LOG:", tostring(args[1]))
        return { status = "success", message = "Logged: " .. tostring(args[1]) }
    else
        return { status = "error", message = "api_log received no arguments" }
    end
end

local function api_quit(args)
    love.event.quit(0)
    return { status = "success", message = "Game is quitting." }
end

-------------------------------------------------
-- DISPATCH TABLE
-------------------------------------------------
local LUA_DISPATCH_TABLE = {
    ["click"] = api_click_button,
    ["start_run"] = api_start_run,
    ["quit"] = api_quit,
    ["log"] = api_log
}

-------------------------------------------------
-- GLOBAL ROUTER FUNCTION
-------------------------------------------------
function safe_command_router(...)
    local args = { ... }

    local func_name = args[1] -- This is the *real* command, e.g., "log"
    table.remove(args, 1)     -- Remove func_name, leaving just the real args

    local func_to_call = LUA_DISPATCH_TABLE[func_name]

    if func_to_call then
        return func_to_call(args)
    else
        return { status = "error", message = "Unknown command: " .. tostring(func_name) }
    end
end

-------------------------------------------------
-- PUBLIC UPDATE FUNCTION
-------------------------------------------------
local Custom = {}

function Custom.update(dt)
    if G.SERVER_TX_CHANNEL then
        local wrapper_table = G.SERVER_TX_CHANNEL:pop()

        -- Only proceed if we received a table AND it's a command
        if wrapper_table and type(wrapper_table) == "table" and wrapper_table.type == "command" then
            local response_table -- This will be the table we send back

            -- We know it's a command, so get the payload
            if wrapper_table.payload then
                -- Decode the JSON string
                local command_str = wrapper_table.payload
                local ok, payload = pcall(json.decode, command_str)

                if not ok or not payload then
                    response_table = { status = "error", message = "Invalid JSON payload: " .. tostring(payload) }
                else
                    -- We have a valid payload, so process it
                    local call_args = {}

                    if payload.args and type(payload.args) == 'table' then
                        local keys = {}
                        for k in pairs(payload.args) do table.insert(keys, k) end
                        table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
                        for _, k in ipairs(keys) do
                            table.insert(call_args, payload.args[k])
                        end
                    end

                    if payload.command == "call" then
                        local func_name = call_args[1] -- "safe_command_router"
                        table.remove(call_args, 1)

                        if func_name and _G[func_name] and type(_G[func_name]) == "function" then
                            local status, result = pcall(_G[func_name], unpack(call_args))
                            response_table = status and result or
                                { status = "error", message = "Error during call: " .. tostring(result) }
                        else
                            response_table = {
                                status = "error",
                                message = "Global function not found: " ..
                                    tostring(func_name)
                            }
                        end
                    else
                        response_table = {
                            status = "error",
                            message = "Unknown server command: " ..
                                tostring(payload.command)
                        }
                    end
                end
            else
                -- The wrapper table was missing the payload
                response_table = { status = "error", message = "Command table missing 'payload' field" }
            end

            -- Send the response
            G.SERVER_RX_CHANNEL:push({ type = "string", payload = json.encode(response_table) })

            -- If it's not a 'command' table (e.g., it's the "log" message),
            -- we now silently ignore it and do nothing.
        end
    end
end

return Custom
