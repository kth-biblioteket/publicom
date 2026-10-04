#!/bin/bash
################################################
####                                        ####
####    Heartbeat till publicomtools        ####
####                                        ####
################################################
# Skickar datorns status till statussidan (publicomtools) var 5:e minut.
# Körs av heartbeat.timer. Gör ingenting om HEARTBEAT_URL (config) eller
# PUBLICOM_DEVICE_TOKEN (.secrets) saknas.

ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"
DEPLOYED_FILE="/var/lib/publicom/deployed"
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
        configVersion: $configVersion
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

# Knappar i publicomtools: "Starta om datorn" (reboot) och "Hämta nya inställningar nu" (reload).
# --no-block: väntar inte på att datorn blir ledig. Körs tjänsten redan (väntar) gör start ingenting.
if [ "$(echo "$response" | jq -r '.reboot // false' 2>/dev/null)" == "true" ]; then
    systemctl start --no-block publicom-reboot.service
elif [ "$(echo "$response" | jq -r '.reload // false' 2>/dev/null)" == "true" ]; then
    systemctl start --no-block publicom-reload.service
fi
exit 0
