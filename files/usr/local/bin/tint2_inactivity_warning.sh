#!/bin/bash

WARNING_FILE="/tmp/tint2_inactivity_warning.txt"

# Skriv meddelande till tint2
echo -e "/usr/local/bin/icons/icons8-red-circle-32.png\nInactive session will terminate soon!" > "$WARNING_FILE"

# Vänta så idle_time hinner uppdateras
sleep 2

# Övervaka aktivitet
for i in {1..60}; do
    IDLE_TIME=$(xprintidle)
    if [[ $IDLE_TIME -lt 1000 ]]; then
        # Användaren aktiv, rensa meddelande
        echo -e "/usr/local/bin/icons/icons8-green-circle-32.png\n " > "$WARNING_FILE"
        exit 0
    fi
    sleep 1
done

exit 0
