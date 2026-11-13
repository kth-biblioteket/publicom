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
    # Tre försök: nätverk och DNS kan vara ostadiga en stund efter uppstart (länken uppe men namnuppslagning inte klar)
    local attempt ok=1
    for attempt in 1 2 3; do
        curl -fsSL --max-time 30 "${auth[@]}" -o "$tmp" "$url" && { ok=0; break; }
        [ "$attempt" -lt 3 ] && sleep 10
    done
    if [ "$ok" -ne 0 ]; then
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

# Vänta (högst 2 minuter) tills servern går att slå upp. network-online.target räcker inte alltid: länken kan vara uppe och ha en adress
# medan DNS inte svarar ännu, och då hämtades ingen ny konfiguration och tjänsterna föll. Misslyckas det går init.sh vidare och försöker ändå.
function wait_for_dns() {
    local url="$1" host i
    host=$(echo "$url" | sed -E 's#^[a-z]+://([^/:?]+).*#\1#')
    [ -n "$host" ] && [ "$host" != "$url" ] || return 0
    for i in $(seq 1 60); do
        getent hosts "$host" > /dev/null 2>&1 && return 0
        [ "$i" -eq 1 ] && echo "Väntar på att $host kan slås upp (nätverk/DNS)"
        sleep 2
    done
    echo "Varning: $host kunde inte slås upp efter 2 minuter, försöker ändå"
    return 1
}
wait_for_dns "$REMOTE_CONFIG_URL"

# Hämta configfil (GitHub-råfil eller publicomtools device-endpoint) och spara lokalt.
# Skicka device-token om den finns — krävs av publicomtools, ignoreras av GitHub.
safe_download "$REMOTE_CONFIG_URL" /usr/local/bin/config/.config env "${PUBLICOM_DEVICE_TOKEN:-$HEARTBEAT_TOKEN}"
# Nollställ så att värdet från den gamla filen inte ligger kvar om den nya saknar det.
# load_config (inte source) så att den nyss hämtade filen inte kan köra kod som root.
unset PUBLICOM_BRANCH HEARTBEAT_INTERVAL
load_config "$ENV_FILE"

# Branch som filerna hämtas från. publicomtools skriver inte standardvärden i configfilen, så utan PUBLICOM_BRANCH
# gäller stable (som i deploy.sh och install.sh). Förut föll den tillbaka på main och hämtade ingen kod alls.
PUBLICOM_BRANCH="${PUBLICOM_BRANCH:-stable}"
RAW_BASE="https://raw.githubusercontent.com/kth-biblioteket/publicom/${PUBLICOM_BRANCH}"

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
# En post i SCREENSAVER_FILES är antingen ett filnamn eller en https-adress till en bild i publicomtools mediebibliotek.
# Filnamn följer med koden (files.manifest) och kopieras därifrån; en bild som inte finns lokalt
# (äldre installation, eller en ny bild som inte rullats ut) hämtas från GitHub som förut.
# Adresser hämtas bara från publicomtools värd (PUBLICOMTOOLS_URL) och måste vara en PNG eller JPG på högst 15 MB.
# Senast hämtade bilden sparas i en cache, så att den finns kvar om hämtningen misslyckas (nätverk nere, tjänsten nere).
# Allt samlas i en separat katalog och byts ut först om alla filer kom fram.
SCREENSAVER_LOCAL_DIR=/usr/local/share/publicom/screensaver
SCREENSAVER_CACHE=/var/lib/publicom/screensaver-cache
SCREENSAVER_TMP=$(mktemp -d)
SCREENSAVER_OK=true
SCREENSAVER_HOST=$(printf '%s' "$PUBLICOMTOOLS_URL" | sed -nE 's#^https://([^/:]+).*#\1#p')
mkdir -p "$SCREENSAVER_CACHE"
SCREENSAVER_KEEP=" "

# Skriver bildtypen (png eller jpg) om filen är en bild, annars inget och felkod
function image_ext() {
    case "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" in
        ffd8ff) echo jpg ;;
        89504e) [ "$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')" == "89504e470d0a1a0a" ] && echo png || return 1 ;;
        *) return 1 ;;
    esac
}

# Hämtar en adress till $SCREENSAVER_TMP (via cachen). Skriver filnamnet som gavs, annars felkod.
function fetch_screensaver_url() {
    local url="$1" id tmp ext name
    if [[ ! "$url" =~ ^https://[A-Za-z0-9._~:/?\&=%+@-]+$ ]]; then
        echo "Error: ogiltig adress i SCREENSAVER_FILES: $url" >&2; return 1
    fi
    if [ -z "$SCREENSAVER_HOST" ] || [ "$(printf '%s' "$url" | sed -nE 's#^https://([^/:]+).*#\1#p')" != "$SCREENSAVER_HOST" ]; then
        echo "Error: $url ligger inte på $SCREENSAVER_HOST" >&2; return 1
    fi
    id=$(printf '%s' "$url" | sha1sum | cut -c1-12)
    tmp=$(mktemp "$SCREENSAVER_CACHE/dl.XXXXXX") || return 1
    echo "Downloading $url..." >&2
    if curl -fsSL --max-time 60 --max-filesize 15728640 --retry 2 --retry-delay 5 -o "$tmp" "$url" 2>/dev/null \
        && ext=$(image_ext "$tmp"); then
        rm -f "$SCREENSAVER_CACHE/media-$id".*
        mv -f "$tmp" "$SCREENSAVER_CACHE/media-$id.$ext"
    else
        rm -f "$tmp"
        echo "Error: kunde inte hämta en bild från $url" >&2
    fi
    # Cachen gäller både en ny hämtning och en tidigare (när hämtningen misslyckades)
    for name in "$SCREENSAVER_CACHE/media-$id".*; do
        [ -f "$name" ] || { echo "Error: ingen bild att visa för $url" >&2; return 1; }
        cp "$name" "$SCREENSAVER_TMP/$(basename "$name")" || return 1
        SCREENSAVER_KEEP="$SCREENSAVER_KEEP$(basename "$name") "
    done
}

IFS=',' read -ra FILE_ARRAY <<< "$SCREENSAVER_FILES"
for file in "${FILE_ARRAY[@]}"; do
    file="${file// /}"
    [ -z "$file" ] && continue
    if [[ "$file" == https://* ]]; then
        fetch_screensaver_url "$file" || SCREENSAVER_OK=false
    elif [[ ! "$file" =~ ^[A-Za-z0-9._-]+$ ]]; then
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
# Rensa cachen från bilder som inte längre används
for cached in "$SCREENSAVER_CACHE"/*; do
    [ -f "$cached" ] && [[ "$SCREENSAVER_KEEP" != *" $(basename "$cached") "* ]] && rm -f "$cached"
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
# En dator utan POLICY_FILE i inställningarna (t.ex. en ny dator vars grundinställningar inte har det) får grundpolicyn för sin typ,
# så att den inte startar utan policy: gästdatorer policies_guest.json, övriga (sökdator, skylt, kiosk) policies_search.json
if [ -z "$POLICY_FILE" ]; then
    case "$COMPUTER_TYPE" in
        guestcomputer) POLICY_FILE="policies_guest.json" ;;
        *)             POLICY_FILE="policies_search.json" ;;
    esac
    echo "POLICY_FILE saknas i inställningarna, använder $POLICY_FILE för $COMPUTER_TYPE"
fi
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
