# send_command.py
import socket
import sys
from pprint import pprint
import rich
import json
import struct
import time
import os
import subprocess
from tqdm import tqdm
import subprocess
import re
import traceback

# --- Server Configuration ---
HOST = '127.0.0.1'  
PORT = 12345
# ---------------------

past_commands = []

def send_lua_command(command_name, **kwargs):
    """
    Builds the JSON payload and sends the command to the Lua server.

    Args:
        command_name (str): The name of the command (e.g., 'list_keys', 'call').
        **kwargs: Keyword arguments specific to the command.
                e.g., path="GAME.hands[1]", func_name="start_run", index=3
    """
    payload = {"command": command_name}

    # Automatically handle path parsing if 'path' is provided
    if "path" in kwargs:
        path_str = kwargs["path"]
        path_list = parse_lua_path(path_str)
        payload["path"] = path_list
        # Remove 'path' from kwargs so it's not added again below
        del kwargs["path"] 
        
    # Add any other keyword arguments directly to the payload
    # (e.g., func_name="start_run", index=1, text="PLAY")
    payload.update(kwargs)

    # Convert the payload to JSON
    try:
        json_payload_string = json.dumps(payload)
    except TypeError as e:
        print(f"ERROR: Could not serialize arguments to JSON: {e}")
        return

    # Call original function to send the JSON string
    print(f"Sending Payload: {json_payload_string}") # Optional: for debugging
    return send_command(json_payload_string) # Assuming send_command returns the response

def send_command(json_payload_string): 
    """Connects to the Lua server, sends a JSON command string, receives response."""
    # Ensure HOST and PORT constants are defined globally or passed in
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            print("ERROR: Connection refused. Is the Balatro game running?")
            return None # Return None on error
        except Exception as e:
            print(f"An unexpected connection error occurred: {e}")
            return None

        # Send the JSON payload string
        # print(f"Sending Raw: {json_payload_string}") # Debug if needed
        s.sendall(json_payload_string.encode('utf-8') + b'\n') # Ensure newline

        # --- Receive Response ---
        try:
            # 1. Read size prefix
            size_bytes = s.recv(4)
            if not size_bytes or len(size_bytes) < 4:
                print("Error: Did not receive a valid size prefix.")
                # Attempt to read remaining data as potential short string error
                remaining_data = s.recv(1024)
                print(f"Received data (maybe error): { (size_bytes + remaining_data).decode('utf-8', errors='ignore').strip() }")
                return None

            message_length = struct.unpack('<I', size_bytes)[0]

            # 2. Receive data with tqdm progress bar
            response_data = b''
            # Optional: Add tqdm back here if needed for large responses
            while len(response_data) < message_length:
                chunk = s.recv(min(message_length - len(response_data), 4096))
                if not chunk: raise ConnectionError("Server closed early.")
                response_data += chunk

            # 3. Decode and return (either parsed JSON or string)
            response_str = response_data.decode('utf-8').strip()
            try:
                # Try parsing as JSON first
                response_json = json.loads(response_str)
                print("Game's Response (JSON):")
                rich.print(response_json) # Use rich for pretty printing
                return response_json
            except json.JSONDecodeError:
                # If JSON fails, treat as a simple string
                print(f"Game's Response (String): {response_str}")
                return response_str # Return the string
            except NameError: # Handle if rich is not imported/available
                print(f"Game's Response (String): {response_str}")
                return response_str


        except (struct.error, ConnectionError, socket.timeout, Exception) as e:
            print(f"An error occurred while receiving response: {e}")
            # Attempt to decode any partial data received
            partial_str = response_data.decode('utf-8', errors='ignore').strip()
            if partial_str: print(f"Partial response: {partial_str}")
            return None

def run_command(command, cwd='.', wait=False):
    """
    Runs a command in a specified directory.

    Args:
        command (list): The command and its arguments as a list of strings.
        cwd (str): The directory to run the command in. Defaults to the current directory.
        wait (bool): If True, waits for the command to complete. 
        If False, runs it as a background process. Defaults to False.

    Returns:
        subprocess.CompletedProcess or subprocess.Popen: The result object or the process object.
    """
    print(f"Running command: '{' '.join(command)}' in '{cwd}'")
    try:
        if wait:
            # Use subprocess.run for blocking commands where you need the output
            return subprocess.run(
                command, 
                cwd=cwd, 
                check=True,  # Raises an exception if the command fails
                capture_output=True, 
                text=True
            )
        else:
            # Use subprocess.Popen for non-blocking commands (like starting a game)
            return subprocess.Popen(command, cwd=cwd)

    except FileNotFoundError:
        print(f"ERROR: The command '{command[0]}' was not found.")
        print("Please ensure it is installed and in your system's PATH.")
        return None
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Command failed with return code {e.returncode}")
        print(f"--- STDOUT ---\n{e.stdout}")
        print(f"--- STDERR ---\n{e.stderr}")
        return None
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        return None

def parse_lua_path(path_str):
    """Parses a Lua-style path string (e.g., 'GAME.hands[1].id') 
        into a list of keys/indices (e.g., ['GAME', 'hands', 1, 'id'])."""
    parts = []
    # Regex finds either words (keys) or numbers inside brackets (indices)
    for match in re.findall(r'(\w+)|\[(\d+)\]', path_str):
        key, index = match
        if index:
            parts.append(int(index)) # Convert index to integer
        elif key:
            parts.append(key)      # Keep key as string
    return parts

def start_game():
        game_directory = os.path.join('game', 'game_files')
        game_process = run_command(['love', '.'], cwd=game_directory, wait=False)
        
        if game_process:
            print(f"Successfully launched Balatro with process ID: {game_process.pid}")

past_commands = []

def start_script():
    """Launches the game and runs the main command loop."""
    start_game() 

    print("-" * 20)
    print("Balatro Command Client")
    print("Type your command and press Enter. Type 'quit' or 'exit' to close.")
    time.sleep(3) # Give game time to initialize
    
    while True:
        try:
            time.sleep(0.1) # Small delay for server readiness
            command_input = input("> ")

            if not command_input:
                continue # Skip empty input

            # Add command to history immediately
            past_commands.append(command_input)

            # --- Handle Local Python Commands FIRST ---
            if command_input.lower() == "list_commands":
                # Define or fetch your list of Lua commands
                lua_commands = ["list_keys <path>", "get_game_state <path>", "call <func_name>", 
                                "list_buttons", "click_card <index>", "click_by_text <text>", 
                                "click_by_func <func_name>"] 
                print("\nAvailable Lua commands:\n ", "\n  ".join(lua_commands))
                print("\nLocal commands: list_commands, history, quit, exit, restart")
                continue # Go to next input prompt

            elif command_input.lower() == "history":
                print("\nCommand History:")
                pprint(past_commands)
                continue # Go to next input prompt

            elif command_input.lower() in ["quit", "exit"]:
                print("Exiting.")
                break # Exit the loop

            # --- If not a local command, send the RAW command string to Lua ---
            send_command(command_input) 

        except KeyboardInterrupt:
            print("\nCtrl+C detected. Exiting.")
            break # Exit the loop
        except Exception as e:
            print(f"\nAn error occurred in the main loop: {e}")
            traceback.print_exc() # Print full error details

    print("Main loop finished.")

if __name__ == "__main__":
    start_script()