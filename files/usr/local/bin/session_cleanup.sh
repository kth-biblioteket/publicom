#!/bin/bash

# Uppdatera aktuell boknings sluttid med nuvarande tid.
# Så att datorn blir ledig igen när användaren loggar ut eller när sessionen avslutas pga inaktivitet.
# Config-parameter som styr om det ska vara aktivt. BOOKING_TYPE=dropin
# Kontroll i api om nuvarande tid är större än end_time, då ska inte end_time uppdateras


ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"

if [ ! -f "$ENV_FILE" ]; then
    echo "Fel: $ENV_FILE hittades inte"
    exit 0
else
    # Gör variabler tillgängliga i script
    source "$ENV_FILE"
    echo "Hittade $ENV_FILE"
fi

if [ ! -f "$SECRET_FILE" ]; then
    echo "Fel: $SECRET_FILE hittades inte"
    exit 0
else
    # Gör variabler tillgängliga i script
    source "$SECRET_FILE"
    echo "Hittade $SECRET_FILE"
fi

# Chromiums privata /tmp (snap) finns kvar mellan sessionerna och kan bara nås av root.
# Filer som gästen har sparat där ska inte finnas kvar till nästa användare.
CHROMIUM_TMP="/tmp/snap-private-tmp/snap.chromium/tmp"
if [ -d "$CHROMIUM_TMP" ]; then
    find "$CHROMIUM_TMP" -mindepth 1 -maxdepth 1 -user guest -exec rm -rf -- {} +
fi

# Inloggning i Chromium (LOGIN_UI=web): publicomtools avslutar bokningen, så att API-nyckeln
# bara behöver finnas på servern. Var sessionen en Electron-inloggning (reserv) känner
# publicomtools inte till bokningen, och då används det direkta anropet nedan.
DEVICE_TOKEN="${PUBLICOM_DEVICE_TOKEN:-$HEARTBEAT_TOKEN}"
if [ "$BOOKING_TYPE" == "dropin" ] && [ "$LOGIN_UI" == "web" ] && [ -n "$PUBLICOMTOOLS_URL" ] && [ -n "$DEVICE_TOKEN" ]; then
    BOOKING_ID=$(cat /tmp/current_booking_id.txt 2>/dev/null)
    if [ -n "$BOOKING_ID" ]; then
        HEADER_FILE=$(mktemp)
        echo "Authorization: Bearer $DEVICE_TOKEN" > "$HEADER_FILE"
        HTTP_CODE=$(jq -cn --arg host "${PUBLICOM_HOST:-$(hostname)}" --arg bookingId "$BOOKING_ID" \
            '{host: $host, bookingId: $bookingId}' |
            curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
                -H @"$HEADER_FILE" --data-binary @- "$PUBLICOMTOOLS_URL/api/device/session/end")
        rm -f "$HEADER_FILE"
        if [ "$HTTP_CODE" == "200" ]; then
            rm -f /tmp/current_booking_id.txt
            echo "Booking $BOOKING_ID ended via publicomtools" >> /var/log/guest_cleanup.log
            exit 0
        fi
        echo "publicomtools could not end booking $BOOKING_ID (HTTP $HTTP_CODE)" >> /var/log/guest_cleanup.log
    fi
fi

if [ "$BOOKING_TYPE" == "dropin" ]; then
    if [ -z "$BOOKING_API_KEY" ]; then
        echo "Error: API key (BOOKING_API_KEY) not found in $SECRET_FILE" >> /var/log/guest_cleanup.log
        exit 0
    fi

    if [ -z "$RESERVATION_API_UPDATE_URL" ]; then
        echo "Error: API key (RESERVATION_API_UPDATE_URL) not found in $ENV_FILE" >> /var/log/guest_cleanup.log
        exit 0
    fi

    BOOKING_ID=$(cat /tmp/current_booking_id.txt 2>/dev/null)
    # Ta bort filen så att samma bokning inte avslutas igen vid nästa sessionsslut
    rm -f /tmp/current_booking_id.txt

    if [ -z "$BOOKING_ID" ]; then
        # Ingen inloggad session (t ex öppen dator), inget att göra
        exit 0
    else
        echo "Booking id: $BOOKING_ID"
    fi

    END_TIME=$(date +%s)

    echo "end_time: $END_TIME"

    API_URL="$RESERVATION_API_UPDATE_URL$BOOKING_ID?end_time=$END_TIME"

    echo "API_URL: $API_URL"

    # Timeout så att en långsam API-server inte fördröjer att nästa session startar
    API_RESPONSE=$(curl -s --max-time 10 -w "%{http_code}" -o /tmp/api_response.json -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{\"status\": \"ended\", \"apikey\": \"$BOOKING_API_KEY\"}")

    # Extract the HTTP response code from the curl response
    HTTP_CODE="${API_RESPONSE: -3}"

    # Check if the HTTP code indicates success (e.g., 200 OK)
    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "API request successful. Response logged." >> /var/log/guest_cleanup.log
    else
        echo "Error: API request failed with HTTP status code $HTTP_CODE. Response logged in /tmp/api_response.json" >> /var/log/guest_cleanup.log
        cat /tmp/api_response.json >> /var/log/guest_cleanup.log
        exit 0
    fi
else
   echo "Drop in bookings not activated" >> /var/log/guest_cleanup.log
fi
