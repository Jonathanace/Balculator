import logging
import os
import subprocess
import time
import command_router
import sys
from functools import partial
from tqdm import tqdm
import time
from command_router import process_command

def main(commands=None, startup_wait_time=5):
    if commands is None:
        commands = []
    logging.info("Application is starting up...")
    command_router.launch_game()

    for _ in tqdm(range(startup_wait_time), desc="Waiting for game to launch"):
        time.sleep(1)

    # Execute all passed commands
    for command in commands:
        func_name = command.func.__name__
        args = command.args
        kwargs = command.keywords
        logging.info(f"LOG: Running {func_name} with args={args}, kwargs={kwargs}")
        command()
    start_main_loop()

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
            continue_status = command_router.process_command(command_name, args, command_history) 
            
            if continue_status is False:
                break

        except KeyboardInterrupt:
            logging.info("Received KeyboardInterrupt, exiting.")
            break
        except SystemExit:
            logging.info("Received SystemExit, exiting.")
            break

        except Exception as e:
            logging.error(f"An error occurred in the main loop: {e}")
            
    logging.debug("Exiting main loop.")
    try:
        process_command("quit")
    except Exception as e:
        logging.error(f"Error when closing game: {e}")

if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
    commands = [
        # partial(lua_funcs["send_test_message"]),
        # partial(command_router.call_lua_command, ["test_add", 10, 15]),
        partial(process_command, "send_test_message"),
        partial(process_command, "start_run"),
        # partial(time.sleep, 5),
        # partial(command_router.select_blind),
        # partial(time.sleep, 3),
        # partial(command_router.call_lua_command, ["play_cards_from_highlighted"])

    ]
    main(commands, startup_wait_time=5)
