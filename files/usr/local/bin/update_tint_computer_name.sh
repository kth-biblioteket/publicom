#!/bin/bash

# Ladda variabler från .config
source /usr/local/bin/config_lib.sh
load_config /usr/local/bin/config/.config

# Skriv ut variabeln
echo "$COMPUTER_NAME"
