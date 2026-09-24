#!/bin/bash

LOG_FILE="/tmp/logout_timer.log"

function log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if [ -n "$1" ]; then
    TIMEOUT_SECONDS=$1
    log_message "Received timeout duration: $TIMEOUT_SECONDS seconds"
else
    LOGOUT_AFTER_MINUTES=60
    TIMEOUT_SECONDS=$((LOGOUT_AFTER_MINUTES * 60))
    log_message "Using default timeout duration: $TIMEOUT_SECONDS seconds"
fi

TIME_FILE="/tmp/logout_timer.txt"

REMAINING_TIME_FILE="/tmp/remaining_time.txt"

# Spara starttiden för sessionen i en fil
if [ ! -f "$TIME_FILE" ]; then
    date +%s > "$TIME_FILE"
fi

START_TIME=$(cat "$TIME_FILE")

# Loop för att uppdatera hur lång tid som är kvar och avsluta sessionen när tiden är slut
# Kvarvarande tid i minuter och sekunder sparas till fil som kan läsas och visas för användaren
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    REMAINING_TIME=$((TIMEOUT_SECONDS - ELAPSED_TIME))

    if [ $REMAINING_TIME -le 0 ]; then
        echo "00:00" > "$REMAINING_TIME_FILE"
        # rm -f "$TIME_FILE"
        # Avsluta X-sessionen för användaren(guest.service startar då om hela sessionen för användaren så att electron-appen för login startar igen)
        /usr/local/bin/clean-up.sh
        pkill X
        exit
    else
        REMAINING_MINUTES=$((REMAINING_TIME / 60))
        REMAINING_SECONDS=$((REMAINING_TIME % 60))
        FORMATTED_TIME=$(printf "%02d:%02d" $REMAINING_MINUTES $REMAINING_SECONDS)
        # Visa varning är det är x minuter kvar av tiden
        if [ $REMAINING_TIME -le 60 ]; then
            echo -e "/usr/share/icons/Humanity/actions/32/gtk-cancel.svg\nYour session will end soon $FORMATTED_TIME" > "$REMAINING_TIME_FILE"
        else
            echo -e "/usr/share/icons/Humanity/apps/32/clock.svg\nRemaning time: $FORMATTED_TIME" > "$REMAINING_TIME_FILE"
        fi
    fi
    sleep 1
done
