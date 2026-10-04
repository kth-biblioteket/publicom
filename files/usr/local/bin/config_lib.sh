#!/bin/bash
################################################
####                                        ####
####    Säker inläsning av config/secrets    ####
####                                        ####
################################################
# source:a den här filen och anropa: load_config <fil>
#
# Till skillnad från "source <fil>" KÖRS ingenting i filen. .config hämtas från GitHub vid varje
# uppstart, och "source" skulle köra allt som ligger där som root (t ex $(...) eller ; kommando).
# load_config läser bara rader på formen NYCKEL=värde: NYCKEL måste vara ett giltigt variabelnamn,
# ett lager omgivande citattecken tas bort, och värdet tilldelas ordagrant med printf -v, så att
# kommandosubstitution, semikolon, backticks m.m. i värdet aldrig körs. Övriga rader ignoreras.

load_config() {
    local file="$1" line key val
    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"                       # ta bort ev. CR (Windows-radslut)
        case "$line" in ''|\#*) continue ;; esac   # tomma rader och kommentarer
        case "$line" in *=*) ;; *) continue ;; esac # måste innehålla =
        key="${line%%=*}"
        val="${line#*=}"
        # Bara giltiga variabelnamn (a-z, A-Z, 0-9, _, inte inledande siffra). Det stoppar
        # även rader som "export FOO", "a b=c" och liknande.
        case "$key" in ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;; esac
        # Ta bort ett lager matchande citattecken runt värdet
        case "$val" in
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
            \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac
        printf -v "$key" '%s' "$val"
    done < "$file"
}

# Minuter mellan statusrapporterna till publicomtools (HEARTBEAT_INTERVAL), 1–60.
# Saknas värdet eller är det ogiltigt gäller 5. Används av init.sh (heartbeat.timer) och heartbeat.sh.
heartbeat_interval() {
    local m="$HEARTBEAT_INTERVAL"
    if [[ "$m" =~ ^[0-9]{1,2}$ ]] && [ "$((10#$m))" -ge 1 ] && [ "$((10#$m))" -le 60 ]; then
        echo "$((10#$m))"
    else
        echo 5
    fi
}
