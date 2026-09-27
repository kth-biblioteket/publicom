#!/bin/bash
################################################
####                                        ####
####    Väntar på inloggning (LOGIN_UI=web) ####
####                                        ####
################################################
# Startas av login_session.sh prelogin (publicom-login-agent.service, som root).
# Frågar publicomtools varannan sekund om någon har loggat in på inloggningssidan.
# När det har skett installeras gästpolicyn och bokningen skrivs till /run/publicom/session.json,
# som .xinitrc väntar på. Bara root kan skriva filen, så gästen kan inte låsa upp webbläsaren själv.

ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"
RUN_DIR="/run/publicom"
# Svarar inte publicomtools på så här många försök (2 s mellan) startas sessionen om (och Electron används då)
MAX_FAILURES=15

source /usr/local/bin/config_lib.sh
load_config "$ENV_FILE"
load_config "$SECRET_FILE"

ticket=$(cat "$RUN_DIR/login-ticket" 2>/dev/null)
[ -z "$ticket" ] && exit 0

HEADER_FILE=$(mktemp)
trap 'rm -f "$HEADER_FILE"' EXIT
echo "Authorization: Bearer ${PUBLICOM_DEVICE_TOKEN:-$HEARTBEAT_TOKEN}" > "$HEADER_FILE"

# Be .xinitrc avsluta sessionen, så att guest.service startar en ny (med ny biljett, eller Electron om
# publicomtools inte svarar). En omstart av guest.service härifrån startar bara om den här tjänsten (PartOf).
function restart_session() {
    logger -t publicom-login "$1, startar om sessionen"
    touch "$RUN_DIR/restart"
    exit 0
}

failures=0
while true; do
    response=$(curl -sS --max-time 10 -H @"$HEADER_FILE" "$PUBLICOMTOOLS_URL/api/device/session?ticket=$ticket")
    status=$(echo "$response" | jq -r '.status // empty' 2>/dev/null)
    case "$status" in
        active)
            tmp=$(mktemp "$RUN_DIR/session.XXXXXX")
            if echo "$response" | jq -c '{booking_data: .booking_data}' > "$tmp"; then
                # Gästpolicyn först, så att den gäller när .xinitrc startar Chromium för sessionen
                /usr/local/bin/login_session.sh unlock
                chmod 644 "$tmp"
                mv -f "$tmp" "$RUN_DIR/session.json"
                logger -t publicom-login "Inloggad, sessionen startar"
                exit 0
            fi
            rm -f "$tmp"
            ;;
        pending|working)
            failures=0
            ;;
        expired|superseded|ended|unknown)
            restart_session "Inloggningsbiljetten gäller inte längre ($status)"
            ;;
        *)
            failures=$((failures + 1))
            [ "$failures" -ge "$MAX_FAILURES" ] && restart_session "publicomtools svarar inte"
            ;;
    esac
    sleep 2
done
