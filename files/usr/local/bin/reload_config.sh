#!/bin/bash
################################################
####                                        ####
####    Hämta nya inställningar / starta om ####
####                                        ####
################################################
# Startas av heartbeat.sh när någon i publicomtools har klickat på en knapp:
#   reload_config.sh          "Hämta nya inställningar nu" (publicom-reload.service): gör samma
#                             sak som en omstart, utan att starta om datorn: hämtar inställningar
#                             och kod (init.service), bygger om webbläsarens regler
#                             (allowlist_from_ezproxy.service) och startar en ny gästsession.
#   reload_config.sh reboot   "Starta om datorn" (publicom-reboot.service).
# Väntar i båda fallen tills ingen använder datorn.

MODE="${1:-reload}"
STATE_DIR="/var/lib/publicom"
STAMP="$STATE_DIR/last-$MODE"
IDLE_MS=120000          # ingen aktivitet på 2 minuter räknas som ledig
CHECK_EVERY=30          # sekunder mellan kontrollerna
GIVE_UP_AFTER=$((8 * 3600))
MIN_INTERVAL=$((5 * 60))
[ "$MODE" == "reboot" ] && MIN_INTERVAL=$((30 * 60))

log() { echo "$*"; logger -t publicom-reload "$*"; }

mkdir -p "$STATE_DIR"

# Skydd mot upprepning: lyckas det inte fortsätter publicomtools att be om det vid varje
# heartbeat. Gör det då högst var 5:e minut (omstart: en gång per halvtimme).
if [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -lt "$MIN_INTERVAL" ]; then
    log "Gjorde $MODE för mindre än $((MIN_INTERVAL / 60)) min sedan, väntar"
    exit 0
fi

# Någon är inloggad (bokning pågår: Electron och webbinloggning)
function logged_in() {
    [ -s /tmp/current_booking_id.txt ] || [ -s /run/publicom/session.json ]
}

# Millisekunder sedan senaste mus- eller tangentbordsaktivitet i gästsessionen, eller tomt
function idle_ms() {
    sudo -u guest DISPLAY=:0 XAUTHORITY=/home/guest/.Xauthority xprintidle 2>/dev/null
}

function in_use() {
    logged_in && return 0
    local idle
    idle=$(idle_ms)
    # Ingen X-session (t ex gästsessionen står still) räknas som ledig
    [ -n "$idle" ] && [ "$idle" -lt "$IDLE_MS" ]
}

waited=0
while in_use; do
    if [ "$waited" -ge "$GIVE_UP_AFTER" ]; then
        log "Datorn har använts i 8 timmar, gör $MODE ändå"
        break
    fi
    [ "$waited" -eq 0 ] && log "Datorn används, väntar tills den är ledig"
    sleep "$CHECK_EVERY"
    waited=$((waited + CHECK_EVERY))
done

touch "$STAMP"
if [ "$MODE" == "reboot" ]; then
    log "Startar om datorn (begärt från publicomtools)"
    systemctl reboot
    exit 0
fi
log "Hämtar nya inställningar"
systemctl restart init.service || log "Error: init.service misslyckades"
systemctl restart allowlist_from_ezproxy.service || log "Error: allowlist_from_ezproxy.service misslyckades"
systemctl restart guest.service
log "Klart, ny gästsession startad"
