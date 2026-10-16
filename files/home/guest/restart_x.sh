#!/bin/bash
# Anropas av xautolock efter SESSION_IDLE minuter utan inmatning, och sedan om och om igen så länge ingen rör datorn.
# Hoppa över återställningen om ingen inmatning skett sedan förra: det finns ingen session att städa.
# Saknas tiden (last-input eller last-reset) görs återställningen som förut.
LAST_INPUT=/run/publicom-guest/last-input   # epoch-sekunder, skrivs av visit_tracker.py
LAST_RESET=/run/publicom-guest/last-reset   # epoch-sekunder för förra återställningen

input=$(cat "$LAST_INPUT" 2>/dev/null)
reset=$(cat "$LAST_RESET" 2>/dev/null)
if [[ "$input" =~ ^[0-9]+$ && "$reset" =~ ^[0-9]+$ ]] && [ "$input" -le "$reset" ]; then
    exit 0
fi

logger -t publicom-idle "Återställning efter inaktivitet"
date +%s > "$LAST_RESET"
/usr/local/bin/clean-up.sh
pkill -f chromium-browser
sleep 1
