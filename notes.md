


> start_run 
    > go_to_menu
    > select_blind
    > play_cards_from_highlighted
> quit

commands:
    - list_keys hand.highlighted
    - get_game_state ["hand.highlighted"]
    - G.hand.highlighted


# Adding a new Func
1. Look for the func in button_callbacks.lua, or just search the game files.
2. Create a custom API that calls that func in `custom.lua`, for example:
    ```lua
    local function api_start_run(args)
        G.FUNCS.start_setup_run(nil)
        return { status = "success", message = "New run started" }
    end
    ```
    or 
    ```lua
    local function api_quit(args)
        love.event.quit(0)
        return { status = "success", message = "Game is quitting." }
    end
    ```
3. Add the func to the `LUA_DISPATCH_TABLE` in `custom.lua` with a given alias. 
4. Create a new function in `command_router.py` such as:
    ```python
    def start_new_run():
        call_safe_router("start_run")
    ```
5. Add the new function to the `FUNCS` table in `command_router.py` with an alias. 
6. Call your new function with `process_command("your_python_alias")`, or if passed as an argument to the main function, `partial(process_command, "your_python_alias")`.