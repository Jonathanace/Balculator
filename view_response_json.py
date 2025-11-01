import json
import traceback

def print_structure(data, indent=""):
    """
    Recursively prints the keys and data types of a nested dictionary or list.
    """
    if isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, (dict, list)):
                print(f"{indent}- {key}: ({type(value).__name__})")
                print_structure(value, indent + "  ")
            else:
                print(f"{indent}- {key}: ({type(value).__name__})")
    elif isinstance(data, list):
        if data: # Only process the first item if the list is not empty
            print(f"{indent}[list of {len(data)} items, first item is a {type(data[0]).__name__}]")
            print_structure(data[0], indent + "  ")
        else:
            print(f"{indent}[empty list]")

# --- Main script execution (no longer wrapped in if __name__ == "__main__") ---
file_path = 'response.json'
try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        if not content:
            print("ERROR: 'response.json' is empty.")
        else:
            game_state = json.loads(content)
            print(f"--- Structure of {file_path} ---")
            print_structure(game_state)

except FileNotFoundError:
    print(f"ERROR: The file '{file_path}' was not found.")
except json.JSONDecodeError as e:
    print(f"ERROR: 'response.json' is not valid JSON. The file may be corrupted.")
    print(f"--> Specific error: {e}")
except Exception as e:
    print(f"An unexpected error occurred:")
    traceback.print_exc()

# This line will pause the script and keep the console window open
input("\nPress Enter to exit...")