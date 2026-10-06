#!/bin/bash
################################################
####                                        ####
####    Besök för användningsstatistiken    ####
####                                        ####
################################################
# Ett besök = från första mus- eller tangentbordsaktiviteten efter att datorn återställts till
# sista aktiviteten innan den återställs igen (inaktivitet i SESSION_IDLE minuter, utloggning,
# eller att tiden tar slut). Den inaktiva tiden på slutet räknas inte.
#
# Läser xprintidle i gästsessionen var 5:e sekund. Aktivitet = räknaren är lägre än förra läsningen
# plus tiden som gått, alltså har den nollställts (en ny X-session räknas inte, där börjar räknaren
# från noll utan att någon rört datorn). Ett besök kräver aktivitet i minst två läsningar: en ensam
# nollställning kan komma utan att någon rört datorn (skärmsläckaren startar, Chromium startas om
# efter inaktivitet, en skärm kopplas in) och räknas inte.
# Avslutade besök läggs i VISITS_FILE och skickas med nästa statusrapport (heartbeat.sh), som
# tar bort dem när publicomtools har tagit emot dem. Inga användare eller adresser, bara tider.
#
# Körs av visit-tracker.service som root. Gör ingenting på skyltar (COMPUTER_TYPE=signage).

ENV_FILE="/usr/local/bin/config/.config"
VISITS_FILE="/var/lib/publicom/visits.jsonl"
# Skrivs av logout_timer.sh (timeout) och logout_and_cancel.sh (logout) innan X avslutas
REASON_FILE="/tmp/publicom-end-reason"
MAX_QUEUED=500
POLL=5

source /usr/local/bin/config_lib.sh
load_config "$ENV_FILE"

if [ "$COMPUTER_TYPE" == "signage" ]; then
    # Inte Restart-loop: tjänsten står still tills nästa omstart (då läses profilen igen)
    exec sleep infinity
fi

# Besöket är slut efter lika lång inaktivitet som sessionen återställs efter (minst en minut)
idle_limit=$(( ${SESSION_IDLE:-5} > 0 ? ${SESSION_IDLE:-5} * 60 : 300 ))

mkdir -p "$(dirname "$VISITS_FILE")"

function idle_seconds() {
    local ms
    ms=$(sudo -u guest DISPLAY=:0 XAUTHORITY=/home/guest/.Xauthority xprintidle 2>/dev/null)
    [[ "$ms" =~ ^[0-9]+$ ]] && echo $((ms / 1000))
}

started=""
last_activity=""
# Läsningar med aktivitet under besöket
active_polls=0
previous=""
previous_at=""

function end_visit() {
    local reason="$1"
    [ -z "$started" ] && return
    if [ "$active_polls" -lt 2 ]; then
        echo "Ignorerade en ensam aktivitet $(date -d "@$started" '+%H:%M:%S') (inget besök)"
        started=""
        active_polls=0
        return
    fi
    if [ -s "$REASON_FILE" ]; then
        reason=$(head -c 20 "$REASON_FILE" | tr -dc 'a-z')
    fi
    rm -f "$REASON_FILE"
    (
        flock 9
        printf '{"start":%d,"end":%d,"reason":"%s"}\n' "$started" "$last_activity" "${reason:-end}" >> "$VISITS_FILE"
        # Utan nät i flera dagar: behåll bara de senaste
        if [ "$(wc -l < "$VISITS_FILE")" -gt "$MAX_QUEUED" ]; then
            tail -n "$MAX_QUEUED" "$VISITS_FILE" > "$VISITS_FILE.tmp" && mv "$VISITS_FILE.tmp" "$VISITS_FILE"
        fi
    ) 9> "$VISITS_FILE.lock"
    started=""
    active_polls=0
}

while true; do
    sleep "$POLL"
    now=$(date +%s)
    idle=$(idle_seconds)
    if [ -z "$idle" ]; then
        # Ingen X-session: sessionen har avslutats (utloggning, timeout eller inaktivitet)
        end_visit idle
        previous=""
        continue
    fi
    if [ -n "$previous" ] && [ $((idle + 1)) -lt $((previous + now - previous_at)) ]; then
        last_activity=$((now - idle))
        [ -z "$started" ] && started=$last_activity
        active_polls=$((active_polls + 1))
    fi
    previous=$idle
    previous_at=$now
    if [ -n "$started" ] && [ "$idle" -ge "$idle_limit" ]; then
        end_visit idle
    fi
done
