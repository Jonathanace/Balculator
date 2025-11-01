








def send_lua_command(command_name, args):
    """
    Builds the JSON payload and sends the command to the Lua server.

    Args:
        command_name (str): The name of the command (e.g., 'list_keys', 'call').
    """
    payload = {
        "command": command_name,
        "args": args
    }
    