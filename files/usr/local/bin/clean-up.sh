#!/bin/bash
################################################
####                                        ####
####    Rensa gästens filer                 ####
####                                        ####
################################################
# Körs som guest i början av varje session (.xinitrc) och vid utloggning (logout_timer.sh,
# logout_and_cancel.sh). Inget som en gäst har sparat eller skapat får finnas kvar till nästa
# användare. Chromiums dialogruta för att spara filer når hela /home/guest, inte bara Downloads.
# Chromiums privata /tmp rensas av session_cleanup.sh (root).

GUEST="/home/guest"

# Det som behålls direkt i /home/guest: filerna som files.manifest installerar, .Xauthority för
# den pågående X-sessionen, .xscreensaver (skapas av .xinitrc), skalfilerna från /etc/skel och snap.
# tools/check.sh kontrollerar att allt som files.manifest installerar i /home/guest finns med här.
KEEP_HOME=(.xinitrc .xbindkeysrc .Xmodmap restart_x.sh .config .Xauthority .xscreensaver .bashrc .profile .bash_logout snap)
# Det som behålls i /home/guest/.config (files.manifest)
KEEP_CONFIG=(openbox tint2)
# Mapparna i Chromiums hemkatalog (snap) som behålls men töms
TARGET_DIRS=(Desktop Documents Downloads Music Pictures Public Templates Videos)

# Ta bort allt i katalogen $1 utom namnen i de följande argumenten
function remove_all_except() {
    local dir="$1" entry name keep
    shift
    [ -d "$dir" ] || return 0
    for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        name=$(basename "$entry")
        keep=false
        for k in "$@"; do
            [ "$name" == "$k" ] && keep=true && break
        done
        $keep || rm -rf -- "$entry"
    done
}

remove_all_except "$GUEST" "${KEEP_HOME[@]}"
remove_all_except "$GUEST/.config" "${KEEP_CONFIG[@]}"

# Snap: bara Chromium
remove_all_except "$GUEST/snap" chromium
# Chromiums hemkatalog: allt utom mapparna ovan, som töms. Även GTK:s bokmärken och listan över
# senast använda filer ligger här (.config, .local); snap skapar det som behövs igen när Chromium startar.
CHROMIUM_HOME=$(readlink -f "$GUEST/snap/chromium/current")
if [ -n "$CHROMIUM_HOME" ] && [ -d "$CHROMIUM_HOME" ]; then
    remove_all_except "$CHROMIUM_HOME" "${TARGET_DIRS[@]}"
    for dir in "${TARGET_DIRS[@]}"; do
        remove_all_except "$CHROMIUM_HOME/$dir"
    done
fi
# Chromiums gemensamma katalog: profilerna (publicom-profile, samma sökväg som CHROMIUM_PROFILE
# i .xinitrc) och allt annat utom cachen (typsnitt m.m.)
remove_all_except "$GUEST/snap/chromium/common" .cache

exit 0
