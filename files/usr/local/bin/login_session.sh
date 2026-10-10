#!/bin/bash
################################################
####                                        ####
####    Inloggning i Chromium (LOGIN_UI)    ####
####                                        ####
################################################
# Inloggningsskärmen visas som en webbsida i publicomtools i stället för i Electron.
# Körs som root:
#   login_session.sh prelogin   före varje session (guest.service ExecStartPre):
#                               hämtar en inloggningsbiljett, installerar inloggningspolicyn
#                               (bara inloggningssidan är tillåten) och startar login_agent.sh
#   login_session.sh unlock     när någon har loggat in (login_agent.sh): gästpolicyn tillbaka
#   login_session.sh cleanup    efter varje session (guest.service ExecStopPost)
# Går något fel i prelogin används Electron som vanligt (.xinitrc hittar då ingen inloggningsadress).

ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"
RUN_DIR="/run/publicom"
STATE_DIR="/var/lib/publicom"
POLICY="/var/snap/chromium/current/policies/managed/policies.json"
# Gästpolicyn sparas här medan inloggningspolicyn är installerad
GUEST_POLICY="$STATE_DIR/policies-guest.json"
LOGIN_POLICY_SUM="$STATE_DIR/policies-login.sha256"

source /usr/local/bin/config_lib.sh
load_config "$ENV_FILE"
load_config "$SECRET_FILE"

function log() {
    echo "$1"
    logger -t publicom-login "$1"
}

# Installera en policyfil atomiskt, så att Chromium aldrig läser en halvskriven fil
function install_policy() {
    local tmp
    tmp=$(mktemp "$POLICY.XXXXXX") || return 1
    if cp "$1" "$tmp" && chown root:root "$tmp" && chmod 644 "$tmp"; then
        mv -f "$tmp" "$POLICY"
    else
        rm -f "$tmp"
        return 1
    fi
}

# publicomtools i inloggningspolicyns URLAllowlist, t ex apps.lib.kth.se/publicomtools
TOOLS_ALLOW="${PUBLICOMTOOLS_URL#*://}"

# Är inloggningspolicyn installerad? Känns igen på kontrollsumman från när den installerades och på
# innehållet (allt blockerat utom publicomtools), så att den aldrig sparas som gästpolicy, inte ens om
# datorn stängdes av eller kraschade innan kontrollsumman hann skrivas till disk.
function login_policy_installed() {
    if [ -f "$LOGIN_POLICY_SUM" ] && [ "$(sha256sum < "$POLICY" | cut -d' ' -f1)" == "$(cat "$LOGIN_POLICY_SUM")" ]; then
        return 0
    fi
    [ -n "$TOOLS_ALLOW" ] && jq -e --arg tools "$TOOLS_ALLOW" \
        '.URLBlocklist == ["*"] and ((.URLAllowlist // []) | index($tools) != null)' "$POLICY" > /dev/null 2>&1
}

function restore_guest_policy() {
    if login_policy_installed && [ -f "$GUEST_POLICY" ]; then
        install_policy "$GUEST_POLICY" && log "Gästpolicyn installerad"
    fi
    rm -f "$LOGIN_POLICY_SUM"
    sync
}

# Adresser som får öppnas före inloggning: publicomtools och formuläret för att registrera konto
function login_allowlist() {
    local tools="$TOOLS_ALLOW" register=""
    if [ -n "$REGISTER_ACCOUNT_URL" ]; then
        register="${REGISTER_ACCOUNT_URL#*://}"
        register="${register%%\?*}"
        # Värd och första delen av sökvägen, t ex apps.lib.kth.se/formtools
        register=$(echo "$register" | cut -d/ -f1-2)
    fi
    jq -cn --arg tools "$tools" --arg register "$register" '[$tools, $register] | map(select(length > 0))'
}

function prelogin() {
    mkdir -p "$RUN_DIR" "$STATE_DIR"
    chmod 755 "$RUN_DIR"
    rm -f "$RUN_DIR/session.json" "$RUN_DIR/login-ticket" "$RUN_DIR/login-url" "$RUN_DIR/restart"
    # Om föregående session avbröts med inloggningspolicyn kvar
    restore_guest_policy

    # Versionen av inställningarna som den här sessionen kör (PUBLICOM_CONFIG_VERSION från
    # publicomtools). heartbeat.sh skickar den, så admin ser om datorn kör det admin visar.
    # Skicka en statusrapport direkt, så att admin uppdateras utan att vänta upp till 5 minuter.
    printf '%s\n' "$PUBLICOM_CONFIG_VERSION" > "$STATE_DIR/config-version"
    systemctl start --no-block heartbeat.service 2>/dev/null

    if [ "$LOGIN_UI" != "web" ] || [ "$ALMA_LOGIN" != "true" ]; then
        return 0
    fi
    # Sökdatorer, skyltar och kiosker visar ingen inloggningsskärm (.xinitrc). Inloggningspolicyn skulle då
    # ligga kvar och spärra allt, eftersom ingen någonsin loggar in.
    if [ "$COMPUTER_TYPE" == "searchcomputer" ] || [ "$COMPUTER_TYPE" == "signage" ] || [ "$COMPUTER_TYPE" == "kiosk" ]; then
        log "ALMA_LOGIN=true men COMPUTER_TYPE=$COMPUTER_TYPE, ingen inloggning"
        return 0
    fi
    local token="${PUBLICOM_DEVICE_TOKEN:-$HEARTBEAT_TOKEN}"
    if [ -z "$PUBLICOMTOOLS_URL" ] || [ -z "$token" ]; then
        log "LOGIN_UI=web men PUBLICOMTOOLS_URL eller PUBLICOM_DEVICE_TOKEN saknas, Electron används"
        return 0
    fi

    local header response ticket path
    header=$(mktemp)
    echo "Authorization: Bearer $token" > "$header"
    response=$(jq -cn \
        --arg host "${PUBLICOM_HOST:-$(hostname)}" \
        --arg resourceId "$RESOURCE_ID" \
        --argjson defaultHours "${DEFAULT_BOOKING_TIME:-2}" \
        --arg loginType "${LOGINTYPE:-password}" \
        --arg bookingType "${BOOKING_TYPE:-dropin}" \
        '{host: $host, resourceId: $resourceId, defaultHours: $defaultHours, loginType: $loginType, bookingType: $bookingType}' |
        curl -fsS --max-time 10 -X POST -H "Content-Type: application/json" -H @"$header" \
            --data-binary @- "$PUBLICOMTOOLS_URL/api/device/login-ticket")
    local curl_status=$?
    rm -f "$header"
    ticket=$(echo "$response" | jq -r '.ticket // empty' 2>/dev/null)
    path=$(echo "$response" | jq -r '.loginPath // empty' 2>/dev/null)
    if [ $curl_status -ne 0 ] || [ -z "$ticket" ] || [ -z "$path" ]; then
        log "Kunde inte hämta inloggningsbiljett från $PUBLICOMTOOLS_URL, Electron används"
        return 0
    fi

    # Gick gästpolicyn inte att återställa (ingen sparad kopia) används Electron
    if login_policy_installed; then
        log "Inloggningspolicyn är installerad men ingen gästpolicy finns sparad, Electron används"
        return 0
    fi

    # Inloggningspolicyn: gästpolicyn, men bara inloggningssidan är tillåten, utan bokmärkesrad (Downloads),
    # autofyll, nedladdningar och dialogrutor för filer (Ctrl+S/Ctrl+O öppnar annars en filhanterare). Inkognito behålls: då öppnar Ctrl+N inget nytt fönster med adressfält. En ny flik
    # (Ctrl+T) visar Chromiums tomma inkognitoflik, där inget kan öppnas; Ctrl+W går tillbaka.
    local login_policy
    login_policy=$(mktemp)
    cp "$POLICY" "$GUEST_POLICY"
    if ! jq --argjson allow "$(login_allowlist)" \
        '. + {URLBlocklist: ["*"], URLAllowlist: $allow, BookmarkBarEnabled: false,
            AutofillAddressEnabled: false, AutofillCreditCardEnabled: false,
            AllowFileSelectionDialogs: false, DownloadRestrictions: 3} | del(.ManagedBookmarks)' \
        "$GUEST_POLICY" > "$login_policy"; then
        rm -f "$login_policy"
        log "Kunde inte skapa inloggningspolicyn, Electron används"
        return 0
    fi
    # Gästpolicyn och kontrollsumman på disk innan inloggningspolicyn installeras
    sha256sum < "$login_policy" | cut -d' ' -f1 > "$LOGIN_POLICY_SUM"
    sync
    if ! install_policy "$login_policy"; then
        rm -f "$login_policy" "$LOGIN_POLICY_SUM"
        log "Kunde inte installera inloggningspolicyn, Electron används"
        return 0
    fi
    rm -f "$login_policy"
    sync

    # Biljetten för login_agent.sh (bara root) och adressen för Chromium (bara guest)
    (umask 077 && echo "$ticket" > "$RUN_DIR/login-ticket")
    (umask 077 && echo "$PUBLICOMTOOLS_URL$path" > "$RUN_DIR/login-url")
    chown guest:guest "$RUN_DIR/login-url"
    systemctl start --no-block publicom-login-agent.service
    log "Inloggningsskärm i Chromium startad"
}

case "$1" in
    prelogin)
        prelogin
        ;;
    unlock)
        restore_guest_policy
        ;;
    cleanup)
        systemctl stop --no-block publicom-login-agent.service 2>/dev/null
        rm -f "$RUN_DIR/session.json" "$RUN_DIR/login-ticket" "$RUN_DIR/login-url" "$RUN_DIR/restart"
        restore_guest_policy
        ;;
    *)
        echo "Användning: $0 prelogin|unlock|cleanup" 1>&2
        exit 2
        ;;
esac
# Sessionen ska starta även om något här misslyckas
exit 0
