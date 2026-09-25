#!/bin/bash
################################################
####                                        ####
####    Deploy Publicom                     ####
####                                        ####
################################################
# Installerar skript och konfigurationsfiler enligt files.manifest.
# Körs av init.sh vid varje uppstart och av install.sh vid installation.
#
# Användning:
#   deploy.sh              Hämtar branchen PUBLICOM_BRANCH (standard: stable) från GitHub
#   deploy.sh <katalog>    Använder en lokal kopia av repot (t ex vid test)
#
# Allt valideras innan något ändras. Om hämtning eller validering misslyckas
# lämnas den befintliga installationen orörd.

ENV_FILE="/usr/local/bin/config/.config"
STATE_DIR="/var/lib/publicom"
REPO="kth-biblioteket/publicom"

if [ "$(id -u)" -ne "0" ]; then
    echo "deploy.sh måste köras som root." 1>&2
    exit 1
fi

[ -f "$ENV_FILE" ] && source "$ENV_FILE"
BRANCH="${PUBLICOM_BRANCH:-stable}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Hämta källan
if [ -n "$1" ]; then
    SRC="$1"
    echo "Deploy från lokal katalog $SRC"
else
    echo "Deploy från branch $BRANCH"
    if ! curl -fsSL --max-time 120 -o "$WORK/src.tar.gz" "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"; then
        echo "Error: kunde inte hämta $BRANCH, befintlig installation behålls"
        exit 0
    fi
    if ! tar -xzf "$WORK/src.tar.gz" -C "$WORK"; then
        echo "Error: kunde inte packa upp $BRANCH, befintlig installation behålls"
        exit 0
    fi
    SRC=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -n1)
fi

MANIFEST="$SRC/files.manifest"
if [ ! -f "$MANIFEST" ]; then
    echo "Error: $MANIFEST saknas, befintlig installation behålls"
    exit 0
fi

# Läs manifestet: rättigheter ägare mål [källa]
ENTRIES=()
while read -r mode owner dest source; do
    [[ -z "$mode" || "$mode" == \#* ]] && continue
    ENTRIES+=("$mode|$owner|$dest|${source:-files$dest}")
done < "$MANIFEST"

# Validera allt innan något installeras
ERRORS=0
for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r mode owner dest source <<< "$entry"
    file="$SRC/$source"
    if [ ! -f "$file" ]; then
        echo "Error: $source saknas"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    case "$dest" in
        *.sh|*/.xinitrc) bash -n "$file" || { echo "Error: syntaxfel i $source"; ERRORS=$((ERRORS + 1)); } ;;
        *.json) jq empty "$file" || { echo "Error: ogiltig JSON i $source"; ERRORS=$((ERRORS + 1)); } ;;
    esac
done
if [ "$ERRORS" -gt 0 ]; then
    echo "Error: $ERRORS fel i $BRANCH, befintlig installation behålls"
    exit 0
fi

# Skapa katalog inklusive saknade föräldrakataloger.
# Kataloger i gästens hem ska ägas av gästen (install -d sätter bara ägare på sista nivån).
function make_dir() {
    local dir="$1"
    [ -d "$dir" ] && return
    make_dir "$(dirname "$dir")"
    if [[ "$dir" == /home/guest/* ]]; then
        install -d -o guest -g guest -m 0755 "$dir"
    else
        install -d -m 0755 "$dir"
    fi
}

# Installera filer som har ändrats (innehåll, rättigheter eller ägare)
CHANGED=()
for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r mode owner dest source <<< "$entry"
    file="$SRC/$source"
    if [ -f "$dest" ] && cmp -s "$file" "$dest" \
        && [ "$(stat -c '%a %U:%G' "$dest")" == "${mode#0} $owner" ]; then
        continue
    fi
    make_dir "$(dirname "$dest")"
    # Skriv till temporärfil och byt atomiskt, så att skript som körs just nu
    # (t ex init.sh) inte påverkas
    tmp="$dest.publicom-new"
    cp "$file" "$tmp" && chown "$owner" "$tmp" && chmod "$mode" "$tmp" && mv -f "$tmp" "$dest"
    if [ $? -eq 0 ]; then
        echo "Installed $dest"
        CHANGED+=("$dest")
    else
        echo "Error: kunde inte installera $dest"
        rm -f "$tmp"
    fi
done

function changed() {
    local pattern="$1" f
    for f in "${CHANGED[@]}"; do
        [[ "$f" == $pattern ]] && return 0
    done
    return 1
}

# Åtgärder beroende på vad som ändrats
if changed "/etc/systemd/system/*"; then
    systemctl daemon-reload
    systemctl enable init.service allowlist_from_ezproxy.service guest.service x11vnc.service
fi
# Tidtagare räknar om nästa körning först när de startas om
for timer in apt-daily apt-daily-upgrade; do
    if changed "/etc/systemd/system/$timer.timer.d/*"; then
        systemctl restart "$timer.timer"
    fi
done
if changed "/etc/sysctl.d/*"; then
    sysctl --system > /dev/null
fi
if changed "/etc/modprobe.d/*"; then
    update-initramfs -u
fi
ELECTRON_DIR="/usr/local/bin/electron-login"
if changed "$ELECTRON_DIR/package*.json" || [ ! -f "$ELECTRON_DIR/node_modules/electron/path.txt" ]; then
    echo "Installerar npm-paket för electron-login"
    # Installera i temporär katalog och byt först när allt lyckats,
    # så att inloggningen fungerar även om nedladdningen avbryts
    NPM_DIR="$WORK/npm"
    mkdir -p "$NPM_DIR"
    cp "$ELECTRON_DIR/package.json" "$ELECTRON_DIR/package-lock.json" "$NPM_DIR/"
    # Electron laddar ner sitt program i ett postinstall-skript. npm 12 blockerar sådana skript
    # som standard, så skriptet körs uttryckligen. Kontrollera sedan att programmet finns
    # (.bin/electron finns även när nedladdningen inte har gjorts).
    if (cd "$NPM_DIR" && npm ci --omit=dev --no-audit --no-fund && node node_modules/electron/install.js) \
        && [ -f "$NPM_DIR/node_modules/electron/path.txt" ] \
        && [ -x "$NPM_DIR/node_modules/electron/dist/$(cat "$NPM_DIR/node_modules/electron/path.txt")" ]; then
        rm -rf "$ELECTRON_DIR/node_modules.old"
        [ -d "$ELECTRON_DIR/node_modules" ] && mv "$ELECTRON_DIR/node_modules" "$ELECTRON_DIR/node_modules.old"
        mv "$NPM_DIR/node_modules" "$ELECTRON_DIR/node_modules"
        rm -rf "$ELECTRON_DIR/node_modules.old"
    else
        echo "Error: npm ci misslyckades, befintliga node_modules behålls"
    fi
fi

# Chromiums sandlåda i Electron. Ubuntu 24.04 begränsar user namespaces för vanliga användare
# (AppArmor), och då används SUID-hjälparen chrome-sandbox. Den måste ägas av root med 4755,
# annars vägrar Electron starta.
CHROME_SANDBOX="$ELECTRON_DIR/node_modules/electron/dist/chrome-sandbox"
if [ -f "$CHROME_SANDBOX" ] && [ "$(stat -c '%a %U' "$CHROME_SANDBOX")" != "4755 root" ]; then
    chown root:root "$CHROME_SANDBOX" && chmod 4755 "$CHROME_SANDBOX" && echo "Installed $CHROME_SANDBOX (4755)"
fi

# Spara vad som är installerat
mkdir -p "$STATE_DIR"
{
    echo "branch=$BRANCH"
    echo "date=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "files_changed=${#CHANGED[@]}"
} > "$STATE_DIR/deployed"

echo "Deploy klar: ${#CHANGED[@]} filer ändrade"
