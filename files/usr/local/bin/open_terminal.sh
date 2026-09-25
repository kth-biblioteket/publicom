#!/bin/bash
# Terminal för administratören, öppnas med Ctrl+Shift+T (se ~/.xbindkeysrc).
# Inloggningen görs av su mot kthb-kontots vanliga lösenord (PAM), så inget lösenord
# eller hash lagras i filen. Gästen får aldrig ett eget skal: fel lösenord stänger fönstret.
# Fördröjning efter fel lösenord sätts i /etc/pam.d/su (pam_faildelay) av install.sh.
exec xterm -title "Admin (kthb)" -fa Monospace -fs 12 \
    -e /bin/sh -c 'su -l kthb || { echo "Fel lösenord, fönstret stängs."; sleep 2; }'
