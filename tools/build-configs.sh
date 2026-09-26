#!/bin/bash
# Genererar .config_<dator> i repots rot från
#   config/base.env + config/profiles/<PROFILE>.env + config/hosts/<dator>.env
# Senare filer skriver över tidigare. Värden kopieras exakt som de står.
#
# Användning:
#   tools/build-configs.sh           Generera alla filer
#   tools/build-configs.sh --check   Kontrollera att genererade filer är aktuella (avslutar med 1 annars)
#
# De genererade filerna checkas in, eftersom datorerna hämtar dem direkt från GitHub.

cd "$(dirname "$0")/.." || exit 1

CHECK=false
[ "$1" == "--check" ] && CHECK=true

# Slå ihop env-filer. Nyckelordningen följer första förekomsten.
function merge_env() {
    awk '
        /^[[:space:]]*(#|$)/ { next }
        {
            eq = index($0, "=")
            if (eq == 0) next
            key = substr($0, 1, eq - 1)
            if (!(key in value)) order[++n] = key
            value[key] = substr($0, eq + 1)
        }
        END { for (i = 1; i <= n; i++) print order[i] "=" value[order[i]] }
    ' "$@"
}

STATUS=0
for host_file in config/hosts/*.env; do
    host=$(basename "$host_file" .env)
    profile=$(grep -m1 '^PROFILE=' "$host_file" | cut -d= -f2)
    profile_file="config/profiles/$profile.env"
    if [ ! -f "$profile_file" ]; then
        echo "Error: $host_file anger profil '$profile' men $profile_file saknas" 1>&2
        STATUS=1
        continue
    fi

    merged=$(merge_env config/base.env "$profile_file" "$host_file" | grep -v '^PROFILE=')
    branch=$(echo "$merged" | grep -m1 '^PUBLICOM_BRANCH=' | cut -d= -f2 | tr -d '"')

    output="# GENERERAD FIL, ändra inte här.
# Redigera config/base.env, $profile_file eller $host_file
# och kör tools/build-configs.sh
REMOTE_CONFIG_URL=\"https://raw.githubusercontent.com/kth-biblioteket/publicom/${branch:-main}/.config_$host\"
PUBLICOM_HOST=$host
PUBLICOM_PROFILE=$profile
$merged"

    target=".config_$host"
    if $CHECK; then
        if ! diff -q <(echo "$output") "$target" > /dev/null 2>&1; then
            echo "Inaktuell: $target (kör tools/build-configs.sh)" 1>&2
            STATUS=1
        fi
    else
        echo "$output" > "$target"
        echo "Skrev $target"
    fi
done

exit $STATUS
