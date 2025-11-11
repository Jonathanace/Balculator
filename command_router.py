
import json
import logging
import socket
import struct
import sys
import subprocess
import os

HOST = "127.0.0.1"
PORT = 12345

def call_safe_router(command, args_list=[]):
    lua_args = ["safe_command_router", command] + args_list
    send_lua_command("call", lua_args)

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
    if command_name in FUNCS:
        logging.info(f"Processing command: {command_name}")
        if not args:
            FUNCS[command_name]()
        else:
            FUNCS[command_name](args)
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

def call_lua_command(args):
    send_lua_command("call", args)

def lua_log(args):
    for arg in args:
        call_safe_router("log", [str(arg)])

def send_test_message():
    lua_log(["This is a test message!"])

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
    logging.info("Closing the game...")
    try:
        call_safe_router("quit", []) 
    except Exception as e:
        logging.error(f"An error occurred while sending the 'quit' command: {e}")

def select_blind():
    send_lua_command("call", ["select_blind"])

def play_highlighted_cards():
    send_lua_command("call", ["play_cards_from_highlighted"])

def start_new_run():
    call_safe_router("start_run")

def exit_script():
        logging.info("Exiting application.")
        close_game()
        sys.exit(0)

FUNCS = {
    "exit": exit_script,
    "quit": exit_script,
    "test": send_test_message,
    "send_test_message": send_test_message,
    "play_highlighted": play_highlighted_cards,
    "play_cards": play_highlighted_cards,
    "play": play_highlighted_cards,
    "select_blind": select_blind,
    "start_run": start_new_run,
    "call": call_lua_command,
    "send_test_message": send_test_message,
}