import logging
import os
import subprocess
import time

DISPATCH_TABLE = {
    ""
}

def main():
    logging.info("Application is starting up...")
    launch_game()
    time.sleep(0.1)
    start_main_loop()

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

def start_main_loop():
    command_history = []
    while True:
        try:
            # Main command processing loop
            command_input = input(">")

            if not command_input: # Skip empty inputs
                continue
            
            command_history.append(command_input)
            logging.info(f"Received command: {command_input}")

            command_parts = command_input.strip().split()
            command_name = command_parts[0].lower()
            args = command_parts [1:]
            continue_status = process_command(command_name, args, command_history)
            
            if continue_status is False:
                break

        except KeyboardInterrupt:
            logging.info("Received KeyboardInterrupt, exiting.")
            break

        except Exception as e:
            logging.error(f"An error occurred in the main loop: {e}")
            
    logging.debug("Exiting main loop.")
    # FIXME: call quit here

def process_command(command_name, args, command_history):
    if command_name == "exit":
        close_game()
        return False
    elif command_name == "history":
        for idx, cmd in enumerate(command_history[-10:]):
            print(f"{10-idx}: {cmd}")
    else:
        logging.warning(f"Unknown command: {command_name}")



def close_game():
    # FIXME
    # send_lua_command("call", func_name="quit")
    return

if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
    main()