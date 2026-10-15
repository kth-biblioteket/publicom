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

# COMPUTER_TYPE (skyltar används aldrig: ingen sitter vid en skylt, och en film som spelas kan hålla X:s inaktivitetsräknare nere)
COMPUTER_TYPE=""
# shellcheck disable=SC1091
source /usr/local/bin/config_lib.sh
load_config /usr/local/bin/config/.config 2>/dev/null || true

mkdir -p "$STATE_DIR"

# Skydd mot upprepning: lyckas det inte fortsätter publicomtools att be om det vid varje
# heartbeat. Gör det då högst var 5:e minut (omstart: en gång per halvtimme).
if [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -lt "$MIN_INTERVAL" ]; then
    log "Gjorde $MODE för mindre än $((MIN_INTERVAL / 60)) min sedan, väntar"
    # Statusrapporten visar att begäran väntar på skyddet (filen gäller bara en stund: heartbeat.sh ignorerar en gammal)
    mkdir -p /run/publicom
    jq -n --arg mode "$MODE" --arg since "$(date +%Y-%m-%dT%H:%M:%S%:z)" '{mode: $mode, since: $since, reason: "interval"}' > /run/publicom/pending-action 2>/dev/null
    exit 0
fi

# Någon är inloggad (bokning pågår: Electron och webbinloggning)
function logged_in() {
    [ -s /tmp/current_booking_id.txt ] || [ -s /run/publicom/session.json ]
}

# Millisekunder sedan senaste riktiga mus-, tangentbords- eller pekaktivitet, eller tomt. Tiden kommer från visit_tracker.py,
# som läser kärnans inmatningsenheter: en film, skärmsläckaren eller en VNC-klient nollställer inte den, men X:s räknare (xprintidle) gör det.
# Går besöksräknaren inte används xprintidle.
function idle_ms() {
    if systemctl is-active --quiet visit-tracker.service; then
        local ts
        ts=$(cat /run/publicom/last-input 2>/dev/null)
        if [[ "$ts" =~ ^[0-9]+$ ]]; then
            echo $(( ($(date +%s) - ts) * 1000 ))
            return
        fi
    fi
    sudo -u guest DISPLAY=:0 XAUTHORITY=/home/guest/.Xauthority xprintidle 2>/dev/null
}

# Vad som väntar och varför, för statusrapporten (heartbeat.sh läser filen)
PENDING_FILE="/run/publicom/pending-action"
function write_pending() {
    local reason="$1" idle="$2"
    mkdir -p /run/publicom
    jq -n --arg mode "$MODE" --arg since "$(date -d "@$WAIT_START" +%Y-%m-%dT%H:%M:%S%:z)" --arg reason "$reason" --arg idle "${idle:-}" \
        '{mode: $mode, since: $since, reason: $reason, idleSeconds: ($idle | tonumber? // null)} | with_entries(select(.value != null))' \
        > "$PENDING_FILE.tmp" 2>/dev/null && mv -f "$PENDING_FILE.tmp" "$PENDING_FILE"
}
trap 'rm -f "$PENDING_FILE" "$PENDING_FILE.tmp"' EXIT

function in_use() {
    # En skylt har ingen besökare vid skärmen: hämta och starta om direkt (skyddet mot upprepning ovan gäller fortfarande)
    [ "$COMPUTER_TYPE" == "signage" ] && return 1
    if logged_in; then
        write_pending "logged_in" ""
        return 0
    fi
    local idle
    idle=$(idle_ms)
    # Ingen X-session (t ex gästsessionen står still) räknas som ledig
    if [ -n "$idle" ] && [ "$idle" -lt "$IDLE_MS" ]; then
        write_pending "in_use" "$((idle / 1000))"
        return 0
    fi
    return 1
}

WAIT_START=$(date +%s)
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
