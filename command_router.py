
import json
import logging
import socket
import struct
import sys
import subprocess
import os

HOST = "127.0.0.1"
PORT = 12345

def run_command(command, cwd=".", wait=False):
    logging.info(f"Running command: {command}")
    try:
        if wait:
            # Use for blocking commands
            return subprocess.run(
                command,
                cwd=cwd,
                check=True,
                capture_output=True,
                text=True
            )
        else:
            # Use for non-blocking commands
            return subprocess.Popen(command, cwd=cwd)
    except FileNotFoundError as e:
        logging.error(f"ERROR: The command {command[0]} was not found: {e}")
        return None
    except subprocess.CalledProcessError as e:
        logging.error(f"ERROR: Command failed with return code {e.returncode}")
        logging.error(f"--- STDOUT ---\n{e.stdout}")
        logging.error(f"--- STDERR ---\n{e.stderr}")
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}")
        return None

def process_command(command_name, args=None, command_history=None):
    if command_name in DISPATCH_TABLE:
        logging.info(f"Processing command: {command_name} with args: {args}")
        try:
            if not args:
                result = DISPATCH_TABLE[command_name]()
            else:
                result = DISPATCH_TABLE[command_name](args)
            if result is not None:
                logging.info(f"Command '{command_name}' executed with result: {result}")
                return result
        except Exception as e: 
            logging.error(f"Error executing command '{command_name}': {e} from lua router.")
    else:
        logging.error("Invalid command entered")

def send_lua_command(command_name, args):
    logging.debug(f"Preparing to send command: {command_name} with args: {args}")
    payload = {
        "command": command_name,
        "args": args
    }
    json_payload_str = json.dumps(payload)

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            s.sendall(json_payload_str.encode('utf-8') + b"\n")

            size_bytes = s.recv(4)
            if not size_bytes:
                logging.error("ERROR: Did not receive valid size prefix from server.")
                return None
            message_length = struct.unpack("<I", size_bytes)[0]
            response_data = b""
            while len(response_data) < message_length:
                chunk = s.recv(min(message_length - len(response_data), 4096))
                if not chunk:
                    raise ConnectionError("Connection closed before full message was received.")
                response_data += chunk
            response_str = response_data.decode('utf-8').strip()
            try:
                response_json = json.loads(response_str)
                logging.info(f"Received Response: {response_json}") 
                return response_json
            except json.JSONDecodeError as e:
                logging.error(f"ERROR: Could not decode JSON response: {e}")
                return None
    except Exception as e:
        logging.error(f"ERROR: Could not connect/send/receive to Lua server at {HOST}:{PORT}: {e}")
        return None

def lua_print(args):
    for arg in args:
        send_lua_command("call", ["print", str(arg)])

def send_test_message():
    lua_print(["This is a test message!"])

def launch_game(headless=False):
    logging.debug("Launching the game")
    if headless:
        # TODO: Implement headless mode
        pass 

    game_dir = os.path.join("game", "game_files")
    game_process = run_command(['love', '.'], cwd=game_dir, wait=False)
    if game_process:
        logging.info(f"Successfully launched Balatro with process ID: {game_process.pid}")
    else:
        logging.error("Failed to launch the game.")

def close_game():
    try:
        send_lua_command("call", ["quit"])
    except OSError as e:
        if getattr(e, 'errno', None) == 10038:  # Transport endpoint is not connected
            logging.info("Lua server already closed the connection.")
        else:
            logging.error(f"An unexpected OSError occurred: {e}")
            return
    except Exception as e:
        logging.error(f"An unexpected error occurred while closing the game: {e}")
    return

def exit_script():
        logging.info("Exiting application.")
        close_game()
        sys.exit(0)

DISPATCH_TABLE = {
    "exit": exit_script,
    "quit": exit_script,
    "test": send_test_message,
    "send_test_message": send_test_message,
    "call": send_lua_command
}