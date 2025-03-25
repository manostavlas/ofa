import os
import argparse
import re
import shutil

"""
  Script to change the tnsnames.ora and the listener.ora
  to put all entries on one sinlge line
"""

def process_tnsnames(input_file):

  path, full_name = os.path.split(input_file)
  name, extension = os.path.splitext(full_name)
  backup_file = f"{path}/{name}_convert_one_line{extension}"

  tmp_file = "/tmp/tmp_net_files.txt"

  if not os.path.isfile(input_file):
      raise FileNotFoundError(f"The file '{input_file}' does not exist.")
  
  shutil.copy(input_file, backup_file)
  print(f"Backup file is: {backup_file}")

  with open(input_file, 'r') as infile, open(tmp_file, 'w') as outfile:
        entry = ""
        open_parens = 0
        # patter to match an already treated line
        pattern = r'^[a-zA-Z0-9_]*=\([a-zA-Z0-9].*\)\)\)'

        for line in infile:
            stripped_line = line.strip().replace(" ", "")
            if not stripped_line or stripped_line.startswith('#'):
                continue
            if re.match(pattern, stripped_line):
              outfile.write(stripped_line + "\n") 
              continue
            if "ADR_BASE_LISTENER_" in stripped_line or \
                "LOGGING_LISTENER" in stripped_line or \
                "USE_SID_AS_SERVICE_LISTENER" in stripped_line:
                    entry += "\n" + stripped_line + "\n"
                    continue

            if stripped_line.endswith('=') and not stripped_line.startswith('('):
                open_parens = 0
                entry = stripped_line
            else:
                open_parens += stripped_line.count('(')
                open_parens -= stripped_line.count(')')
                entry += stripped_line
                if open_parens == 0:
                  outfile.write(entry + "\n")
  shutil.copy(tmp_file, input_file)
  print(f"Processed file saved as {backup_file}")



# Setup CLI argument parsing with a detailed help message
parser = argparse.ArgumentParser(
    description="Reformat a tnsnames.ora or an listener.ora files putting all files on one line",
    epilog="""\
Examples:
  python3 fix_net_files.py -f input_file

"""
, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("-f", "--file", required=True, help="Path to the tnsnames.ora or listener.ora file .")
args = parser.parse_args()

process_tnsnames(args.file)

