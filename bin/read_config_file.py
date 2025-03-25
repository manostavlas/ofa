#!/usr/bin/env python3

import yaml
import argparse
#import json

def read_yaml_param(file_path, param):
    """Reads a parameter from a YAML file and returns its value."""
    try:
        with open(file_path, 'r') as file:
            data = yaml.safe_load(file)

        # Handle nested keys using dot notation (e.g., "database.host")
        keys = param.split('.')
        value = data
        for key in keys:
            value = value.get(key)
            if value is None:
                raise KeyError(f"Parameter '{param}' not found in YAML file.")

        return value

    except FileNotFoundError:
        print(f"Error: File '{file_path}' not found.")
        exit(1)
    except yaml.YAMLError as e:
        print(f"Error: Invalid YAML file format - {e}")
        exit(1)
    except KeyError as e:
        print(f"Error: {e}")
        exit(1)

# Setup CLI argument parsing with a detailed help message
parser = argparse.ArgumentParser(
    description="Read a parameter from a YAML file.",
    epilog="""\
Examples:
  python read_yaml_cli.py -a read -p database.host -f config.yaml
  python read_yaml_cli.py -a read -p api_key -f config.yaml

Supports dot notation for nested keys (e.g., 'database.host').
"""
, formatter_class=argparse.RawDescriptionHelpFormatter)

parser.add_argument("-a", "--action", choices=["read"], required=True, help="Action to perform (only 'read' is supported).")
parser.add_argument("-p", "--parameter", required=True, help="Parameter to retrieve (supports dot notation for nested keys).")
parser.add_argument("-f", "--file", required=True, help="Path to the YAML file.")

args = parser.parse_args()

# Execute the read action
if args.action == "read":
    value = read_yaml_param(args.file, args.parameter)
    print(value)
    #print(json.dumps(value, indent=2))
