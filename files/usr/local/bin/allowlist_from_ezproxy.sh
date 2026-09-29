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

POLICY_PATH="/var/snap/chromium/current/policies/managed/policies.json"
STANZA_CACHE="/var/cache/publicom/db_stanzas.txt"

# Kör ett jq-filter på policyn och ersätt filen atomiskt.
# Om jq misslyckas behålls den befintliga policyn.
# Användning: update_policy '<filter>' [jq-argument...]
function update_policy() {
  local filter="$1"; shift
  local tmp
  tmp=$(mktemp "${POLICY_PATH}.XXXXXX") || return 1
  if jq "$@" "$filter" "$POLICY_PATH" > "$tmp" && [ -s "$tmp" ]; then
    chown root:root "$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$POLICY_PATH"
  else
    echo "Error: could not update policy with filter: $filter"
    rm -f "$tmp"
    return 1
  fi
}

# Gör om ett värdnamn till den domän som ska tillåtas.
# t ex www.jstor.org -> jstor.org, men www.cambridge.co.uk -> cambridge.co.uk (inte co.uk)
function base_domain() {
  echo "$1" | awk -F. '{
    if (NF >= 3 && length($NF) == 2 && $(NF-1) ~ /^(co|ac|com|org|net|gov|edu)$/)
      print $(NF-2)"."$(NF-1)"."$NF
    else if (NF >= 2)
      print $(NF-1)"."$NF
    else
      print $0
  }'
}

# Sätt URLBlocklist och URLAllowlist från listorna i config (+ ev. extra domäner)
# "*" blockeras alltid så att endast tillåtna domäner går att nå.
function apply_restrictions() {
  local blocked allowed
  IFS=',' read -r -a blocked <<< "$BLACK_LIST"
  allowed=("$@")
  update_policy '.URLBlocklist = (["*"] + $ARGS.named.blocked | map(select(. != "")) | unique)
                 | .URLAllowlist = ($ARGS.named.allowed | map(select(. != "")) | unique)' \
    --argjson blocked "$(jq -n '$ARGS.positional' --args "${blocked[@]}")" \
    --argjson allowed "$(jq -n '$ARGS.positional' --args "${allowed[@]}")"
}

# Utskrift i Chromium. Sätts åt båda hållen: grundpolicyn har PrintingEnabled=false, men om
# den inte kunde laddas ner (safe_download behåller den gamla filen) skulle ett tidigare
# PRINTER=true annars ligga kvar och Ctrl+P fortsätta fungera.
if [ "$PRINTER" == "true" ]; then
  update_policy '.PrintingEnabled = true'
else
  update_policy '.PrintingEnabled = false'
fi

# Dialogrutor för filer (spara som, välja fil att ladda upp, t ex bifoga i mejl).
# FILE_DIALOGS=false stänger av dem helt; nedladdningar sparas då direkt i Downloads.
if [ "$FILE_DIALOGS" == "false" ]; then
  update_policy '.AllowFileSelectionDialogs = false'
else
  update_policy 'del(.AllowFileSelectionDialogs)'
fi

IFS=',' read -r -a ALLOWED_DOMAINS <<< "$WHITE_LIST"

if [ "$COMPUTER_TYPE" != "searchcomputer" ]; then
  ###########
  # Gästdator
  ###########
  # Om ALMA_LOGIN är true så blockeras inga webbplatser. Filer (file://) går bara att öppna i
  # Chromiums egna kataloger (Downloads), inte i resten av gästens hem, och nedladdningar sparas
  # direkt i Downloads utan att Chromium öppnar en dialogruta där man kan bläddra i filsystemet.
  # Chromium visar nedladdade filer med versionskatalogen (t ex .../chromium/3533/Downloads),
  # som byts vid uppdatering, därför tillåts hela katalogen.
  if [ "$ALMA_LOGIN" == "true" ]; then
    update_policy '.URLBlocklist = ["file://*"]
                   | .URLAllowlist = ["file:///home/guest/snap/chromium/"]
                   | .PromptForDownloadLocation = false
                   | .DownloadDirectory = "/home/guest/snap/chromium/current/Downloads"'
  else
    # Om gästdatorn är öppen(utan login)
    # Hämta stanzafil(ezproxy) med tillåtna domäner. Senaste lyckade nedladdning sparas
    # så att den kan användas om hämtningen misslyckas (t ex utgången token).
    mkdir -p "$(dirname "$STANZA_CACHE")"
    if [ -z "$GITHUB_TOKEN" ]; then
      echo "Error: GITHUB_TOKEN is not set in $SECRET_FILE"
    else
      URL="https://raw.githubusercontent.com/kth-biblioteket/ezproxy/main/db_stanzas.txt"
      if curl -fsSL --max-time 30 -H "Authorization: token $GITHUB_TOKEN" -o "${STANZA_CACHE}.new" "$URL"; then
        mv -f "${STANZA_CACHE}.new" "$STANZA_CACHE"
      else
        echo "Error: could not download stanza file (expired GITHUB_TOKEN?), using cached copy if available"
        rm -f "${STANZA_CACHE}.new"
      fi
    fi

    # Lägg till domäner från stanzafil(ezproxy)
    if [ -f "$STANZA_CACHE" ]; then
      while IFS= read -r line; do
        if [[ $line =~ ^(URL|HJ|DJ)[[:space:]] ]]; then
            DOMAIN=$(echo "$line" | awk '{print $2}')
            # Ta bort protokoll, sökväg och port
            DOMAIN="${DOMAIN#*://}"
            DOMAIN="${DOMAIN%%/*}"
            DOMAIN="${DOMAIN%%:*}"
            [ -n "$DOMAIN" ] && ALLOWED_DOMAINS+=("$(base_domain "$DOMAIN")")
        fi
      done < "$STANZA_CACHE"
    else
      echo "Warning: no stanza file available, only WHITE_LIST is allowed"
    fi

    apply_restrictions "${ALLOWED_DOMAINS[@]}"
  fi
else
  ###########
  # Sökdator
  ###########
  apply_restrictions "${ALLOWED_DOMAINS[@]}"
fi

# Härdning som gäller alla datortyper, oavsett listorna ovan:
# - blockera datorns egna tjänster (CUPS 631, VNC 5900) som annars nås via localhost
#   trots URL-listorna (gästdatorer med inloggning blockerar bara file://)
# - ingen helskärm (F11), så att en falsk inloggningssida inte kan täcka hela skärmen
# - inga tillägg
update_policy '.URLBlocklist = ((.URLBlocklist // []) + ["localhost", "127.0.0.1", "[::1]"] | unique)
               | .FullscreenAllowed = false
               | .ExtensionInstallBlocklist = ["*"]'
