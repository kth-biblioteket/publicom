#!/bin/bash

ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"

if [ ! -f "$ENV_FILE" ]; then
    echo "Fel: $ENV_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    source /usr/local/bin/config_lib.sh
    load_config "$ENV_FILE"
    echo "Hittade $ENV_FILE"
fi

if [ ! -f "$SECRET_FILE" ]; then
    echo "Fel: $SECRET_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    load_config "$SECRET_FILE"
    echo "Hittade $SECRET_FILE"
fi

# Ladda ner till temporärfil, validera och ersätt målfilen först när allt är ok.
# Vid fel (t ex 404 eller nätverksfel) behålls den befintliga filen.
# $3 = valideringstyp: env, json eller any
#
# env kontrollerar formatet som load_config läser: varje rad är tom, en kommentar eller NYCKEL=värde.
# Inte bash -n: filen körs aldrig, och bash -n underkände hela filen för ett värde med t ex ett
# udda antal " eller $( i en text, så att datorn startade med sina gamla inställningar.
function env_format_ok() {
    ! grep -qvE '^[[:space:]]*(#.*)?$|^[A-Za-z_][A-Za-z0-9_]*=' "$1"
}

function safe_download() {
    local url="$1" dest="$2" type="$3" token="$4" tmp
    tmp=$(mktemp "${dest}.XXXXXX") || return 1
    local auth=()
    # Device-token för config från publicomtools (endpointen kräver det). Git-råfiler
    # ignorerar headern, så det är ofarligt för datorer som fortfarande hämtar från GitHub.
    [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
    if ! curl -fsSL --max-time 30 "${auth[@]}" -o "$tmp" "$url"; then
        echo "Error downloading $url, keeping existing $dest"
        rm -f "$tmp"
        return 1
    fi
    case "$type" in
        env)  env_format_ok "$tmp" && grep -q '^REMOTE_CONFIG_URL=' "$tmp" ;;
        json) jq empty "$tmp" ;;
        *)    [ -s "$tmp" ] ;;
    esac
    if [ $? -ne 0 ]; then
        echo "Error: $url failed validation, keeping existing $dest"
        rm -f "$tmp"
        return 1
    fi
    chmod 644 "$tmp"
    mv -f "$tmp" "$dest"
    echo "Successfully downloaded $url"
}

# Hämta configfil (GitHub-råfil eller publicomtools device-endpoint) och spara lokalt.
# Skicka device-token om den finns — krävs av publicomtools, ignoreras av GitHub.
safe_download "$REMOTE_CONFIG_URL" /usr/local/bin/config/.config env "${PUBLICOM_DEVICE_TOKEN:-$HEARTBEAT_TOKEN}"
# Nollställ så att värdet från den gamla filen inte ligger kvar om den nya saknar det.
# load_config (inte source) så att den nyss hämtade filen inte kan köra kod som root.
unset PUBLICOM_BRANCH HEARTBEAT_INTERVAL
load_config "$ENV_FILE"

# Branch som filerna hämtas från (äldre configfiler saknar PUBLICOM_BRANCH)
RAW_BASE="https://raw.githubusercontent.com/kth-biblioteket/publicom/${PUBLICOM_BRANCH:-main}"

# Uppdatera skript och konfigurationsfiler enligt files.manifest.
# Ändringar gäller från och med den här uppstarten eftersom guest.service startar efter init.service.
# Byter deploy ut init.sh själv startas den nya versionen direkt (utan ny deploy), så att resten av
# det här skriptet också följer den nya koden. Annars skulle den gälla först vid nästa hämtning.
if [ -x /usr/local/bin/deploy.sh ] && [ -n "$PUBLICOM_BRANCH" ] && [ -z "$PUBLICOM_INIT_RESTARTED" ]; then
    init_before=$(sha256sum /usr/local/bin/init.sh 2>/dev/null)
    /usr/local/bin/deploy.sh || echo "Error: deploy misslyckades"
    if [ "$(sha256sum /usr/local/bin/init.sh 2>/dev/null)" != "$init_before" ] && bash -n /usr/local/bin/init.sh; then
        echo "init.sh uppdaterades, startar den nya versionen"
        export PUBLICOM_INIT_RESTARTED=1
        exec /usr/local/bin/init.sh
    fi
fi

# Intervall för statusrapporterna (HEARTBEAT_INTERVAL, minuter) som en override till heartbeat.timer.
# config_lib.sh läses in igen eftersom deploy kan ha installerat en nyare version.
# systemd laddas bara om när intervallet ändrats.
source /usr/local/bin/config_lib.sh
HEARTBEAT_DROPIN=/etc/systemd/system/heartbeat.timer.d/interval.conf
heartbeat_conf=$(printf '[Timer]\nOnUnitActiveSec=\nOnUnitActiveSec=%smin' "$(heartbeat_interval)")
if [ "$(cat "$HEARTBEAT_DROPIN" 2>/dev/null)" != "$heartbeat_conf" ]; then
    mkdir -p "$(dirname "$HEARTBEAT_DROPIN")"
    printf '%s\n' "$heartbeat_conf" > "$HEARTBEAT_DROPIN"
    systemctl daemon-reload
    systemctl restart heartbeat.timer
    echo "Statusrapport var $(heartbeat_interval):e minut"
fi

# Skärmsläckarfiler
# Bilderna följer med koden (files.manifest) och kopieras därifrån; en bild som inte finns lokalt
# (äldre installation, eller en ny bild som inte rullats ut) hämtas från GitHub som förut.
# Allt samlas i en separat katalog och byts ut först om alla filer kom fram.
SCREENSAVER_LOCAL_DIR=/usr/local/share/publicom/screensaver
SCREENSAVER_TMP=$(mktemp -d)
SCREENSAVER_OK=true
IFS=',' read -ra FILE_ARRAY <<< "$SCREENSAVER_FILES"
for file in "${FILE_ARRAY[@]}"; do
    file="${file// /}"
    [ -z "$file" ] && continue
    if [[ ! "$file" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Error: ogiltigt filnamn i SCREENSAVER_FILES: $file"
        SCREENSAVER_OK=false
    elif [ -f "$SCREENSAVER_LOCAL_DIR/$file" ]; then
        cp "$SCREENSAVER_LOCAL_DIR/$file" "$SCREENSAVER_TMP/$file"
    else
        echo "Downloading $file..."
        if ! curl -fsSL --max-time 30 -o "$SCREENSAVER_TMP/$file" "$RAW_BASE/screensaver/$file"; then
            echo "Error downloading $file"
            SCREENSAVER_OK=false
        fi
    fi
done
# Tom lista: visa KTH-bakgrunden i stället för skärmsläckarens inbyggda testbild
if [ "$SCREENSAVER_OK" == "true" ] && [ -z "$(ls -A "$SCREENSAVER_TMP")" ]; then
    echo "SCREENSAVER_FILES är tom, använder KTH-bakgrunden"
    cp /usr/local/bin/screen_bg_kth_logo_navy.png "$SCREENSAVER_TMP/" 2>/dev/null || SCREENSAVER_OK=false
fi
if [ "$SCREENSAVER_OK" == "true" ]; then
    rm -rf /usr/local/bin/screensaver/*
    cp "$SCREENSAVER_TMP"/* /usr/local/bin/screensaver/ 2>/dev/null
    chmod 644 /usr/local/bin/screensaver/* 2>/dev/null
else
    echo "Keeping existing screensaver files"
fi
rm -rf "$SCREENSAVER_TMP"

# Chrome policy: grundpolicyn följer med koden (files.manifest) och kopieras vid varje start,
# så att inställningarna gäller även om GitHub-grenen inte går att nå. allowlist_from_ezproxy.sh
# lägger sedan på det som inställningarna styr (utskrift, nedladdningar, webbplatser …).
# Äldre installationer utan de lokala filerna hämtar som förut från GitHub.
POLICY_DEST=/var/snap/chromium/current/policies/managed/policies.json
POLICY_LOCAL_DIR=/usr/local/share/publicom/policies
mkdir -p "$(dirname "$POLICY_DEST")"
if [[ ! "$POLICY_FILE" =~ ^policies_[a-z0-9_-]+\.json$ ]]; then
    echo "Error: ogiltigt POLICY_FILE '$POLICY_FILE', befintlig policy behålls"
elif [ -f "$POLICY_LOCAL_DIR/$POLICY_FILE" ] && jq empty "$POLICY_LOCAL_DIR/$POLICY_FILE"; then
    echo "Installing policy $POLICY_FILE"
    install -o root -g root -m 0644 "$POLICY_LOCAL_DIR/$POLICY_FILE" "$POLICY_DEST"
else
    echo "Downloading policy $POLICY_FILE"
    safe_download "$RAW_BASE/$POLICY_FILE" "$POLICY_DEST" json
fi
chown root:root "$POLICY_DEST"
chmod 644 "$POLICY_DEST"
