#!/bin/bash
################################################
####                                        ####
####    Hämta nya inställningar nu          ####
####                                        ####
################################################
# Startas av heartbeat.sh (via publicom-reload.service) när någon i publicomtools har
# klickat "Hämta nya inställningar nu". Väntar tills ingen använder datorn och gör sedan
# samma sak som en omstart, utan att starta om datorn: hämtar inställningar och kod
# (init.service), bygger om webbläsarens regler (allowlist_from_ezproxy.service) och
# startar en ny gästsession (guest.service).

STATE_DIR="/var/lib/publicom"
STAMP="$STATE_DIR/last-reload"
IDLE_MS=120000          # ingen aktivitet på 2 minuter räknas som ledig
CHECK_EVERY=30          # sekunder mellan kontrollerna
GIVE_UP_AFTER=$((8 * 3600))
MIN_INTERVAL=$((15 * 60))

log() { echo "$*"; logger -t publicom-reload "$*"; }

mkdir -p "$STATE_DIR"

# Skydd mot upprepning: kan datorn inte hämta sina inställningar fortsätter publicomtools att
# be om det vid varje heartbeat. Gör det då högst en gång per kvart.
if [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -lt "$MIN_INTERVAL" ]; then
    log "Hämtade inställningar för mindre än 15 min sedan, väntar"
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
        log "Datorn har använts i 8 timmar, hämtar inställningarna ändå"
        break
    fi
    [ "$waited" -eq 0 ] && log "Datorn används, väntar tills den är ledig"
    sleep "$CHECK_EVERY"
    waited=$((waited + CHECK_EVERY))
done

touch "$STAMP"
log "Hämtar nya inställningar"
systemctl restart init.service || log "Error: init.service misslyckades"
systemctl restart allowlist_from_ezproxy.service || log "Error: allowlist_from_ezproxy.service misslyckades"
systemctl restart guest.service
log "Klart, ny gästsession startad"
