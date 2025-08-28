#!/bin/bash

# requires sqlite3 to be installed
# sudo apt install sqlite3

sqlite3 -header -column /opt/intellioptics/edge/sqlite.db
# .help for help
# .quit or .exit 0 to exit
