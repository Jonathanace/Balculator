-- command_handler.lua
local json = require("json") 
local CommandHandler = {} 

-- --- Private Helper Functions ---
local function sanitize_for_json(data)
    local already_seen = {}
    local MAX_DEPTH = 20
    local function recursive_sanitize(value, depth)
        if depth > MAX_DEPTH then return { _error = "Max recursion depth reached" } end
        local value_type = type(value)
        if value_type == "number" and value == math.huge then return "Infinity" end
        if value_type == "table" then
            if already_seen[value] then return { _circular_ref = true } end
            already_seen[value] = true
            local is_array = #value > 0 and value[1] ~= nil
            if is_array then
                local sanitized_array = {}
                for i = 1, #value do
                    sanitized_array[i] = recursive_sanitize(value[i], depth + 1)
                end
                already_seen[value] = nil; return sanitized_array
            else
                local sanitized_object = {}
                for k, v in pairs(value) do
                    sanitized_object[k] = recursive_sanitize(v, depth + 1)
                end
                already_seen[value] = nil; return sanitized_object
            end
        elseif value_type == "userdata" then
            local meta = getmetatable(value)
            if meta == Card then return { _type = "Card", id = value.base.id, edition = value.edition and value.edition.id or "None" }
            else return "userdata: " .. tostring(value) end
        elseif value_type == "function" then return nil
        else return value end
    end
    return recursive_sanitize(data, 1)
end

local function string_split_path(str)
    local result = {}
    local current_pos = 1
    while current_pos <= #str do
        local next_dot = str:find("%.", current_pos, true) or (#str + 1)
        local next_bracket = str:find("%[", current_pos, true) or (#str + 1)
        local next_sep_pos
        if dot_pos and bracket_pos then next_sep_pos = math.min(dot_pos, bracket_pos)
        elseif dot_pos then next_sep_pos = dot_pos
        elseif bracket_pos then next_sep_pos = bracket_pos
        else next_sep_pos = #str + 1 end
        local part = str:sub(current_pos, next_sep_pos - 1)
        if #part > 0 then table.insert(result, part) end
        if next_sep_pos > #str then break end
        local sep = str:sub(next_sep_pos, next_sep_pos)
        if sep == "." then current_pos = next_sep_pos + 1
        elseif sep == "[" then
            local end_bracket = str:find("%]", next_sep_pos + 1, true)
            if not end_bracket then error("Mismatched brackets: " .. str) end
            local index_part = tonumber(str:sub(next_sep_pos + 1, end_bracket - 1))
            table.insert(result, index_part)
            current_pos = end_bracket + 1
            if str:sub(current_pos, current_pos) == "." then current_pos = current_pos + 1 end
        end
    end
    return result
end

local function find_table_by_path(root, path_str)
    local target = root
    if not path_str or path_str == "" or path_str == "G" then return target end
    local path_parts = string_split_path(path_str) -- Calls splitter
    for i, key in ipairs(path_parts) do
        local current_type = type(target)
        if current_type ~= "table" then
            return nil, string.format("Path segment '%s' is not a table.", tostring(path_parts[i-1] or "G"))
        end
        local next_target = rawget(target, key)
        if next_target == nil then
            next_target = target[key]
            if next_target == nil then
                local error_path = ""
                for j=1, i do error_path = error_path .. (type(path_parts[j])=='number' and '['..path_parts[j]..']' or '.'..path_parts[j]) end
                return nil, string.format("Path not found: Key/Index '%s' in path %s", tostring(key), error_path:gsub("^%.",""))
            end
        end
        target = next_target
    end
    return target
end

local function find_clickable_elements(node, path_prefix, clickable_list, found_items)
    found_items = found_items or {}
    if not node or type(node) ~= 'table' then return end
    if getmetatable(node) == UIElement and node.states and node.states.click.can and node.states.visible then
        if node.config and node.config.text then
            local identifier = node.config.text
            if not found_items[identifier] then
                table.insert(clickable_list, identifier)
                found_items[identifier] = true
            end
        -- Also check for FUNC: style if no text
        elseif node.config and node.config.button then
            local identifier = "FUNC:" .. node.config.button
            if not found_items[identifier] then
                table.insert(clickable_list, identifier)
                found_items[identifier] = true
            end
        end
    end
    if node.children and type(node.children) == 'table' then
        for key, child in pairs(node.children) do
            local key_str = type(key) == 'number' and '['..tostring(key)..']' or '.'..tostring(key)
            local new_path = path_prefix .. ".children" .. key_str
            find_clickable_elements(child, new_path, clickable_list, found_items)
        end
    elseif type(node) == 'table' then
        if node == G then return end
        for key, value in pairs(node) do
            local key_str = type(key) == 'number' and '['..tostring(key)..']' or '.'..tostring(key)
            local new_path = path_prefix == "" and key_str:gsub("^%.","") or path_prefix .. key_str
            find_clickable_elements(value, new_path, clickable_list, found_items)
        end
    end
end

local function find_element_by_func(node, target_func_name)
    -- Use original_print or file logging for debug messages
    local function debug_log(...) print("[find_by_func]", ...) end

    if not node or type(node) ~= 'table' then return nil end

    local meta = getmetatable(node) -- Check metatable only once
    if meta == UIElement then
        -- Check if config and button exist first
        if node.config and node.config.button then
            -- Check if the function name matches
            if node.config.button == target_func_name then
                debug_log("Found element with matching func:", target_func_name, "Path hint:", node.path_prefix) -- Add path if available
                -- Now check the states
                if node.states and node.states.click.can and node.states.visible then
                    debug_log(">>> Found MATCHING, VISIBLE, CLICKABLE element.")
                    return node -- Perfect match!
                else
                    -- Log exactly why it failed the state check
                    debug_log("!!! Found matching func, but state invalid. Visible:", tostring(node.states and node.states.visible), "Clickable:", tostring(node.states and node.states.click.can))
                end
            end
        end
    end

    -- Recursively search children (same as before)
    if node.children and type(node.children) == 'table' then
        for _, child in pairs(node.children) do
            local found = find_element_by_func(child, target_func_name)
            if found then return found end
        end
    -- Recursively search other table elements (same as before)
    elseif type(node) == 'table' then
         if node == G then return nil end
         for _, value in pairs(node) do
             local found = find_element_by_func(value, target_func_name)
             if found then return found end
         end
    end

    return nil -- Not found
end

-- --- Private Command Handlers (Expecting String Arguments) ---
local function handle_call(command)
    local args = {}
    for word in command:gmatch("%S+") do table.insert(args, word) end
    local func_name = args[2]
    local call_args = {select(3, unpack(args))}
    if func_name and G.FUNCS[func_name] then
        print("Dynamically calling function:", func_name, "with", #call_args, "arguments")
        local success, err
        if func_name == 'select_blind' and #call_args == 0 then
            success, err = pcall(G.FUNCS[func_name], {})
        else
            success, err = pcall(G.FUNCS[func_name], unpack(call_args))
        end
        if success then return {type="string", payload="Successfully called " .. func_name}
        else return {type="string", payload="LUA_ERROR (runtime call "..func_name.."): " .. tostring(err)} end
    else
        return {type="string", payload=string.format("Error: Function '%s' not found.", func_name or "nil")}
    end
end

local function handle_get_game_state(command)
    local path_str = command:match("^get_game_state%s+(.*)$")
    if not path_str then return {type="string", payload="LUA_ERROR: No path provided."} end
    local target_value, err = find_table_by_path(G, path_str)
    if err and not target_value then
        if not string.find(err, "Path not found") then return {type="string", payload="LUA_ERROR: " .. err} end
        target_value = nil
    end
    local success, result = pcall(function() return json.encode(sanitize_for_json(target_value)) end)
    if success then return {type="json_blob", payload=result}
    else return {type="string", payload="LUA_ERROR (sanitize/encode): " .. tostring(result)} end
end

local function handle_list_keys(command)
    local path_str = command:match("^list_keys%s*(.*)$")
    local target_table, err = find_table_by_path(G, path_str)
    if not target_table then return {type="string", payload="LUA_ERROR: " .. (err or "Target not found.")} end
    if type(target_table) ~= "table" then return {type="string", payload="LUA_ERROR: Path does not point to a table."} end
    local keys_and_types = {}
    local key = nil
    while true do key = next(target_table, key); if key == nil then break end; keys_and_types[key] = type(rawget(target_table, key)) end
    local success, json_str = pcall(json.encode, keys_and_types)
    if success then return {type="json_blob", payload=json_str}
    else return {type="string", payload="LUA_ERROR (json): " .. tostring(json_str)} end
end

local function handle_list_clickable(command)
    local clickable_elements = {}
    find_clickable_elements(G.STAGE_OBJECTS, "STAGE_OBJECTS", clickable_elements)
    find_clickable_elements(G.HUD, "HUD", clickable_elements)
    if G.buttons then find_clickable_elements(G.buttons, "buttons", clickable_elements) end
    if G.UI then find_clickable_elements(G.UI, "UI", clickable_elements) end
    if G.OVERLAY_MENU then find_clickable_elements(G.OVERLAY_MENU, "OVERLAY_MENU", clickable_elements) end
    local success, json_str = pcall(json.encode, clickable_elements)
    if success then return {type="json_blob", payload=json_str}
    else return {type="string", payload="LUA_ERROR (json): " .. tostring(json_str)} end
end

local function handle_click_by_func(payload) -- Signature changed to accept payload table
    -- 1. Get the function name directly from the payload table
    local target_func_name = payload.func_name 
    
    -- 2. Check if the function name exists in the payload
    if not target_func_name or type(target_func_name) ~= "string" then
        return {type="string", payload="LUA_ERROR: 'func_name' (string) missing or invalid in click_by_func payload."}
    end

    -- 3. Search for the element using the function name (No changes needed here)
    local target_element = find_element_by_func(G.STAGE_OBJECTS, target_func_name)
    if not target_element then target_element = find_element_by_func(G.HUD, target_func_name) end
    if not target_element then target_element = find_element_by_func(G.buttons, target_func_name) end 
    if not target_element then target_element = find_element_by_func(G.UI, target_func_name) end 
    if not target_element then target_element = find_element_by_func(G.OVERLAY_MENU, target_func_name) end 

    if not target_element then
        return {type="string", payload="LUA_ERROR: Clickable element with function '" .. target_func_name .. "' not found."}
    end

    -- 4. Check if it has a click method (No changes needed here)
    if type(target_element.click) ~= "function" then
        return {type="string", payload="LUA_ERROR: Found element for func '" .. target_func_name .. "', but it has no .click() method."}
    end

    -- 5. Call the element's click method safely (No changes needed here)
    local success, err = pcall(target_element.click, target_element) 
    if success then
        return {type="string", payload="Successfully clicked element with func: '" .. target_func_name .. "'"}
    else
        return {type="string", payload="LUA_ERROR (runtime clicking by func): " .. tostring(err)}
    end
end

local function handle_unknown(command)
    local response_str = string.format("Error: Unknown command '%s'", command or "nil")
    return {type="string", payload=response_str}
end

function CommandHandler.process(command_json_string) -- Argument is the JSON string
    -- 1. Decode JSON safely
    local success, payload = pcall(json.decode, command_json_string)
    if not success then
        local err_msg = "LUA_ERROR: Invalid JSON. Error: " .. tostring(payload) .. ". Original: " .. tostring(command_json_string)
        return {type="string", payload=err_msg}
    end

    -- 2. Validate payload structure
    if type(payload) ~= "table" then
        return {type="string", payload="LUA_ERROR: Decoded JSON payload is not a table."}
    end

    -- 3. Get command_name AND CHECK IF IT EXISTS
    local command_name = payload.command
    if not command_name or type(command_name) ~= "string" then
        return {type="string", payload="LUA_ERROR: Payload missing 'command' field or it's not a string."}
    end

    -- 4. Route based on the command_name from the payload
    if command_name == "call" then       -- Use == for exact match
        return handle_call(payload)      -- Pass the payload table
    elseif command_name == "get_game_state" then
        return handle_get_game_state(payload)
    elseif command_name == "list_keys" then
        return handle_list_keys(payload)
    elseif command_name == "list_buttons" then
        return handle_list_clickable(payload)
    elseif command_name == "click_by_func" then
        return handle_click_by_func(payload)
    elseif command_name == "click_by_text" then
        return handle_click_by_text(payload)
    elseif command_name == "click_card" then
        return handle_click_card(payload)
    -- Add other specific command names here
    else
        return handle_unknown(command_name) -- Pass just the name for the error
    end
end

return CommandHandler