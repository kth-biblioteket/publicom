#!/bin/bash
################################################
####                                        ####
####    Heartbeat till publicomtools        ####
####                                        ####
################################################
# Skickar datorns status till statussidan (publicomtools) var 5:e minut, eller med
# intervallet i HEARTBEAT_INTERVAL (heartbeat.timer, satt av init.sh).
# Körs av heartbeat.timer. Gör ingenting om HEARTBEAT_URL (config) eller
# PUBLICOM_DEVICE_TOKEN (.secrets) saknas.

ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"
DEPLOYED_FILE="/var/lib/publicom/deployed"
# Avslutade besök från visit_tracker.sh, en JSON-rad per besök
VISITS_FILE="/var/lib/publicom/visits.jsonl"
CLIENT_VERSION=1

source /usr/local/bin/config_lib.sh
load_config "$ENV_FILE"
load_config "$SECRET_FILE"

# PUBLICOM_DEVICE_TOKEN används för alla anrop till publicomtools (HEARTBEAT_TOKEN är det äldre namnet)
HEARTBEAT_TOKEN="${PUBLICOM_DEVICE_TOKEN:-$HEARTBEAT_TOKEN}"
if [ -z "$HEARTBEAT_URL" ] || [ -z "$HEARTBEAT_TOKEN" ]; then
    exit 0
fi

# Tid i ISO 8601, eller tomt om värdet saknas eller inte går att tolka
function iso_time() {
    [ -n "$1" ] && date -d "$1" -Iseconds 2>/dev/null
}

function deployed() {
    grep -m1 "^$1=" "$DEPLOYED_FILE" 2>/dev/null | cut -d= -f2-
}

session_started=$(systemctl show guest.service -p ActiveEnterTimestamp --value)
failed_units=$(systemctl list-units --state=failed --plain --no-legend 2>/dev/null | awk '{print $1}')
disk_used=$(df --output=pcent / | tail -n1 | tr -dc '0-9')
os_name=$(. /etc/os-release && echo "$PRETTY_NAME")
# Versionen av inställningarna som gästsessionen startade med (sparas av login_session.sh prelogin)
config_version=$(head -c 64 /var/lib/publicom/config-version 2>/dev/null | tr -dc 'a-zA-Z0-9')
# Intervallet som heartbeat.timer faktiskt har (init.sh skriver det när datorn hämtat inställningarna),
# inte bara det som står i config. Utan override gäller 5 minuter från heartbeat.timer.
interval=$(grep -oE '^OnUnitActiveSec=[0-9]+min' /etc/systemd/system/heartbeat.timer.d/interval.conf 2>/dev/null | tail -n1 | tr -dc '0-9')
# Besöken som väntar. Bara de som finns nu skickas och tas bort efter svaret; besök som avslutas
# under tiden ligger kvar till nästa rapport.
visits_sent=0
visits="null"
if [ -s "$VISITS_FILE" ]; then
    visits_sent=$(wc -l < "$VISITS_FILE")
    visits=$(head -n "$visits_sent" "$VISITS_FILE" | jq -sc '[.[] | select(type == "object")]' 2>/dev/null) || visits="null"
fi

payload=$(jq -n \
    --argjson clientVersion "$CLIENT_VERSION" \
    --arg host "${PUBLICOM_HOST:-$(hostname)}" \
    --arg hostname "$(hostname)" \
    --arg profile "$PUBLICOM_PROFILE" \
    --arg computerType "$COMPUTER_TYPE" \
    --arg computerName "$COMPUTER_NAME" \
    --arg branch "$(deployed branch)" \
    --arg deployedAt "$(iso_time "$(deployed date)")" \
    --arg deployFilesChanged "$(deployed files_changed)" \
    --arg uptimeSeconds "$(cut -d. -f1 /proc/uptime)" \
    --arg os "$os_name" \
    --arg kernel "$(uname -r)" \
    --arg guestService "$(systemctl is-active guest.service)" \
    --arg sessionStartedAt "$(iso_time "$session_started")" \
    --arg guestRestarts "$(systemctl show guest.service -p NRestarts --value)" \
    --arg failedUnits "$failed_units" \
    --argjson rebootRequired "$([ -f /var/run/reboot-required ] && echo true || echo false)" \
    --arg diskUsed "$disk_used" \
    --arg configVersion "$config_version" \
    --argjson intervalMinutes "${interval:-5}" \
    --argjson visits "${visits:-null}" \
    '{
        clientVersion: $clientVersion,
        host: $host,
        hostname: $hostname,
        profile: $profile,
        computerType: $computerType,
        computerName: $computerName,
        branch: $branch,
        deployedAt: $deployedAt,
        deployFilesChanged: ($deployFilesChanged | tonumber? // null),
        uptimeSeconds: ($uptimeSeconds | tonumber),
        os: $os,
        kernel: $kernel,
        guestService: $guestService,
        sessionStartedAt: $sessionStartedAt,
        guestRestarts: ($guestRestarts | tonumber? // null),
        failedUnits: ($failedUnits | split("\n") | map(select(length > 0))),
        rebootRequired: $rebootRequired,
        diskFreePercent: (if $diskUsed == "" then null else 100 - ($diskUsed | tonumber) end),
        configVersion: $configVersion,
        intervalMinutes: $intervalMinutes,
        visits: $visits
    } | with_entries(select(.value != null and .value != ""))')

if [ -z "$payload" ]; then
    echo "Error: kunde inte skapa heartbeat" 1>&2
    exit 0
fi

# Token i en fil i stället för på kommandoraden, så att den inte syns i processlistan
HEADER_FILE=$(mktemp)
trap 'rm -f "$HEADER_FILE"' EXIT
echo "Authorization: Bearer $HEARTBEAT_TOKEN" > "$HEADER_FILE"

# Avslutar med 0 även vid fel, så att tillfälliga nätverksfel inte
# markerar tjänsten som kraschad
if ! response=$(echo "$payload" | curl -fsS --max-time 20 -X POST \
    -H "Content-Type: application/json" -H @"$HEADER_FILE" \
    --data-binary @- "$HEARTBEAT_URL"); then
    echo "Error: heartbeat till $HEARTBEAT_URL misslyckades" 1>&2
    exit 0
fi

# publicomtools har sparat besöken: ta bort de som skickades (visit_tracker.sh kan ha lagt till fler)
if [ "$visits_sent" -gt 0 ] && [ "$(echo "$response" | jq -r '.visitsAck // false' 2>/dev/null)" == "true" ]; then
    (
        flock 9
        sed -i "1,${visits_sent}d" "$VISITS_FILE"
    ) 9> "$VISITS_FILE.lock"
fi

# Knappar i publicomtools: "Starta om datorn" (reboot) och "Hämta nya inställningar nu" (reload).
# --no-block: väntar inte på att datorn blir ledig. Körs tjänsten redan (väntar) gör start ingenting.
if [ "$(echo "$response" | jq -r '.reboot // false' 2>/dev/null)" == "true" ]; then
    systemctl start --no-block publicom-reboot.service
elif [ "$(echo "$response" | jq -r '.reload // false' 2>/dev/null)" == "true" ]; then
    systemctl start --no-block publicom-reload.service
fi
exit 0
