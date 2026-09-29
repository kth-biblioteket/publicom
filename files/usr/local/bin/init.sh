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
        env)  bash -n "$tmp" && grep -q '^REMOTE_CONFIG_URL=' "$tmp" ;;
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
unset PUBLICOM_BRANCH
load_config "$ENV_FILE"

# Branch som filerna hämtas från (äldre configfiler saknar PUBLICOM_BRANCH)
RAW_BASE="https://raw.githubusercontent.com/kth-biblioteket/publicom/${PUBLICOM_BRANCH:-main}"

# Uppdatera skript och konfigurationsfiler enligt files.manifest.
# Ändringar gäller från och med den här uppstarten eftersom guest.service startar efter init.service.
if [ -x /usr/local/bin/deploy.sh ] && [ -n "$PUBLICOM_BRANCH" ]; then
    /usr/local/bin/deploy.sh || echo "Error: deploy misslyckades"
fi

# Skärmsläckarfiler
# Ladda ner till separat katalog och byt ut först om alla filer kom ner
SCREENSAVER_TMP=$(mktemp -d)
SCREENSAVER_OK=true
IFS=',' read -ra FILE_ARRAY <<< "$SCREENSAVER_FILES"
for file in "${FILE_ARRAY[@]}"; do
    [ -z "$file" ] && continue
    echo "Downloading $file..."
    if ! curl -fsSL --max-time 30 -o "$SCREENSAVER_TMP/$file" "$RAW_BASE/screensaver/$file"; then
        echo "Error downloading $file"
        SCREENSAVER_OK=false
    fi
done
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
