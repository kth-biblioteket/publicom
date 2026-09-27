#!/bin/bash
# Kontroller för repot. Körs av CI (.github/workflows/ci.yml) och kan köras lokalt:
#   tools/check.sh
# Kräver bash, jq och node. shellcheck används om det finns.
cd "$(dirname "$0")/.." || exit 1
FAIL=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FEL   $1"; FAIL=1; }

echo "== Skriptens syntax (bash -n)"
SCRIPTS=$(find files tools -type f \( -name "*.sh" -o -name ".xinitrc" \); echo install.sh)
for f in $SCRIPTS; do bash -n "$f" 2>/dev/null && ok "$f" || fail "$f: syntaxfel"; done

echo "== shellcheck (endast fel)"
if command -v shellcheck > /dev/null; then
    for f in $SCRIPTS; do
        out=$(shellcheck -s bash -S error "$f" 2>&1) && ok "$f" || { fail "$f"; echo "$out" | sed 's/^/        /'; }
    done
else
    echo "  (shellcheck saknas, hoppar över)"
fi

echo "== JSON"
for f in policies_*.json files/usr/local/bin/electron-login/package*.json; do
    jq empty "$f" 2>/dev/null && ok "$f" || fail "$f: ogiltig JSON"
done

echo "== JavaScript (Electron)"
for f in files/usr/local/bin/electron-login/*.js; do
    node --check "$f" 2>/dev/null && ok "$f" || fail "$f: syntaxfel"
done

echo "== Genererade configfiler"
tools/build-configs.sh --check && ok ".config_* är aktuella" || fail "kör tools/build-configs.sh"

echo "== files.manifest"
while read -r mode owner dest src; do
    [[ -z "$mode" || "$mode" == \#* ]] && continue
    [[ "$mode" =~ ^0[0-7]{3}$ ]] || fail "$dest: ogiltiga rättigheter '$mode'"
    [[ "$owner" =~ ^[a-z]+:[a-z]+$ ]] || fail "$dest: ogiltig ägare '$owner'"
    src=${src:-files$dest}
    [ -f "$src" ] || fail "$dest: källfilen $src saknas"
done < files.manifest
# Filer under files/ som inte installeras
while read -r f; do
    grep -qE "[[:space:]]${f#files}([[:space:]]|$)" files.manifest || fail "$f finns men saknas i files.manifest"
done < <(find files -type f ! -name ".DS_Store")
[ $FAIL -eq 0 ] && ok "alla filer i manifestet finns och alla filer är med"

echo "== clean-up.sh behåller det som installeras i /home/guest"
keep_home=" $(grep -m1 '^KEEP_HOME=' files/usr/local/bin/clean-up.sh | sed 's/^KEEP_HOME=(\(.*\))$/\1/') "
keep_config=" $(grep -m1 '^KEEP_CONFIG=' files/usr/local/bin/clean-up.sh | sed 's/^KEEP_CONFIG=(\(.*\))$/\1/') "
CLEAN_FAIL=$FAIL
while read -r _ _ dest _; do
    rel=${dest#/home/guest/}
    top=${rel%%/*}
    [[ "$keep_home" == *" $top "* ]] || fail "$dest: $top saknas i KEEP_HOME i clean-up.sh (tas bort vid varje session)"
    if [[ "$top" == ".config" ]]; then
        sub=${rel#.config/}; sub=${sub%%/*}
        [[ "$keep_config" == *" $sub "* ]] || fail "$dest: $sub saknas i KEEP_CONFIG i clean-up.sh"
    fi
done < <(grep -E '^[0-7]{4}[[:space:]]+[^[:space:]]+[[:space:]]+/home/guest/' files.manifest)
[ $FAIL -eq "$CLEAN_FAIL" ] && ok "alla filer i /home/guest behålls"

echo "== Filer som datorerna hämtar direkt från GitHub"
for f in $(grep -ho '^POLICY_FILE="[^"]*"' .config_* | cut -d'"' -f2 | sort -u); do
    [ -f "$f" ] && ok "$f" || fail "$f (POLICY_FILE) saknas"
done
for f in $(grep -ho '^SCREENSAVER_FILES="[^"]*"' .config_* | cut -d'"' -f2 | tr ',' '\n' | sort -u | grep .); do
    [ -f "screensaver/$f" ] && ok "screensaver/$f" || fail "screensaver/$f (SCREENSAVER_FILES) saknas"
done

echo
[ $FAIL -eq 0 ] && echo "Alla kontroller OK" || echo "Kontroller misslyckades"
exit $FAIL
