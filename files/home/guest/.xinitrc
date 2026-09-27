#!/bin/bash

/usr/local/bin/clean-up.sh

# Tala om för användartjänsterna (systemd --user, D-Bus) vilken skärm som gäller, som en vanlig
# skrivbordssession gör. Annars kraschar xdg-desktop-portal och GTK 4-program (t ex zenity på 24.04)
# väntar ca 25 s på den innan de visar något.
if command -v dbus-update-activation-environment > /dev/null; then
  dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
fi

LOG_FILE="/tmp/guest_login.log"

function log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

## Starta electron-appen för login
function prompt_for_code() {
  form_input=$(/usr/local/bin/electron-login/node_modules/.bin/electron /usr/local/bin/electron-login/main.js)
  local electron_status=$?
  # Logga inte själva bokningsdatan, den innehåller användar-id
  log_message "Electron exited with status $electron_status"
  return $electron_status
}

## Inloggning som webbsida i Chromium (LOGIN_UI=web). login_session.sh (root) har hämtat en
## inloggningsbiljett och installerat en policy där bara inloggningssidan är tillåten. Chromium visar
## sidan i kioskläge tills login_agent.sh (root) har skrivit bokningen till LOGIN_SESSION_FILE,
## i samma format som Electron-appen skriver ut.
LOGIN_URL_FILE="/run/publicom/login-url"
LOGIN_SESSION_FILE="/run/publicom/session.json"
LOGIN_RESTART_FILE="/run/publicom/restart"
LOGIN_PROFILE="/home/guest/snap/chromium/common/publicom-login"

function prompt_for_login_web() {
  local url loop
  url=$(cat "$LOGIN_URL_FILE")
  # Kioskläget ber fönsterhanteraren om helskärm, men före inloggningen körs ingen (som med Electron).
  # Ange därför skärmens storlek direkt (efter eventuell rotation).
  local size
  size=$(xdpyinfo | awk '/dimensions:/{print $2}' | tr x ,)
  log_message "Web login started"
  (
    while [ ! -f "$LOGIN_SESSION_FILE" ]; do
      rm -rf "$LOGIN_PROFILE"
      chromium-browser $CHROMIUM_FLAGS --kiosk --window-position=0,0 ${size:+--window-size=$size} --user-data-dir="$LOGIN_PROFILE" --incognito --no-first-run --disable-session-crashed-bubble --disable-features=TranslateUI "$url"
      sleep 1
    done
  ) &
  loop=$!
  while [ ! -f "$LOGIN_SESSION_FILE" ]; do
    # login_agent.sh ber om en ny session (biljetten gäller inte längre eller publicomtools svarar inte)
    if [ -f "$LOGIN_RESTART_FILE" ]; then
      log_message "Web login restart requested"
      kill "$loop" 2>/dev/null
      pkill -u guest -f -- "--user-data-dir=$LOGIN_PROFILE"
      exit 1
    fi
    sleep 0.5
  done
  # Inloggad: stäng inloggningssidan. Sessionen startar i en ny Chromium med ny profil och gästpolicyn.
  kill "$loop" 2>/dev/null
  pkill -u guest -f -- "--user-data-dir=$LOGIN_PROFILE"
  for _ in $(seq 1 20); do pgrep -u guest -f -- "--user-data-dir=$LOGIN_PROFILE" > /dev/null || break; sleep 0.25; done
  rm -rf "$LOGIN_PROFILE"
  form_input=$(cat "$LOGIN_SESSION_FILE")
  log_message "Web login done"
  return 0
}

# Chromium-profil som raderas före varje start så att inget följer med till nästa användare.
# Ligger under snap-katalogen eftersom Chromium (snap) har en egen privat /tmp.
CHROMIUM_PROFILE="/home/guest/snap/chromium/common/publicom-profile"

## Starta Chromium med ny tom profil. Argument läggs till före standardflaggorna.
## CHROMIUM_FLAGS i .config ger extra flaggor, t ex --enable-unsafe-swiftshader i test-VM utan GPU.
function launch_chromium() {
  rm -rf "$CHROMIUM_PROFILE"
  chromium-browser "$@" $CHROMIUM_FLAGS --start-maximized --user-data-dir="$CHROMIUM_PROFILE" --incognito --no-first-run --disable-session-crashed-bubble --disable-features=TranslateUI $WEBSITES
}

ENV_FILE="/usr/local/bin/config/.config"
if [ ! -f "$ENV_FILE" ]; then
    log_message "Error: $ENV_FILE file not found!"
#    exit 1
else
    log_message "$ENV_FILE file found!"
fi

# Gör variabler tillgängliga i script
source "$ENV_FILE"

# Skärmlayout
if [ -n "$SCREEN_ROTATION" ] && [ "$SCREEN_ROTATION" != "normal" ]; then
    log_message "Roterar skärm till: $SCREEN_ROTATION"
    # Hittar namnet på den aktiva skärmen och roterar den
    MONITOR=$(xrandr | grep " connected" | cut -d' ' -f1 | head -n1)
    xrandr --output "$MONITOR" --rotate "$SCREEN_ROTATION"
fi

# Ta bort filen som innehåller starttiden för sessionen
rm -f /tmp/logout_timer.txt

# Rensa tint2 warnings
echo -e "/usr/local/bin/icons/icons8-green-circle-32.png\n " > /tmp/tint2_inactivity_warning.txt

# Skärmsläckarens inställningar skapas från mallen vid varje session. deploy.sh uppdaterar bara mallen,
# så att xscreensaver (som läser om ~/.xscreensaver när den ändras) inte påverkas mitt i en session.
sed "s/^timeout:.*$/timeout: ${SCREENSAVER_IDLE:-00:30:00}/" /usr/local/share/publicom/xscreensaver > /home/guest/.xscreensaver

# Funktion för att dölja muspekaren om SIGNAGE är true
function hide_mouse_cursor() {
    if [ "$SIGNAGE" == "true" ]; then
        log_message "SIGNAGE is true - hiding mouse cursor with unclutter"
        # Kontrollera om unclutter är installerat
        if command -v unclutter &> /dev/null; then
            # Dölj muspekaren efter 1 sekunds inaktivitet
            unclutter -idle 1 -root &
            log_message "unclutter started successfully"
        else
            log_message "WARNING: unclutter not installed - cannot hide mouse cursor"
            # Fallback: försök med xbanish om det finns
            if command -v xbanish &> /dev/null; then
                xbanish &
                log_message "xbanish started as fallback"
            else
                log_message "No cursor hiding tool available"
            fi
        fi
    else
        log_message "SIGNAGE is not true - mouse cursor will be visible"
    fi
}

# Funktion för att sätta bakgrund baserat på layout
function set_background() {
    # Standard bakgrund (stående/portrait)
    BG_IMAGE="/usr/local/bin/screen_bg_kth_logo_navy.png"
    
    # Kolla om SCREEN_ROTATION är satt och om den är "normal" (liggande) eller roterad (stående)
    if [ -n "$SCREEN_ROTATION" ]; then
        case "$SCREEN_ROTATION" in
            "normal"|"inverted")
                # Liggande layout
                if [ -n "$BG_LANDSCAPE" ]; then
                    BG_IMAGE="$BG_LANDSCAPE"
                fi
                ;;
            "left"|"right")
                # Stående layout
                if [ -n "$BG_PORTRAIT" ]; then
                    BG_IMAGE="$BG_PORTRAIT"
                fi
                ;;
        esac
    fi
    
    log_message "Setting background to: $BG_IMAGE"
    feh --bg-scale "$BG_IMAGE"
}

# Kontrollera att bakgrundsbilderna finns
function check_background_images() {
    if [ -n "$BG_LANDSCAPE" ] && [ ! -f "$BG_LANDSCAPE" ]; then
        log_message "Warning: Landscape background image not found: $BG_LANDSCAPE"
    fi
    if [ -n "$BG_PORTRAIT" ] && [ ! -f "$BG_PORTRAIT" ]; then
        log_message "Warning: Portrait background image not found: $BG_PORTRAIT"
    fi
}

# Kolla bakgrundsbilder vid start
check_background_images

if [ "$COMPUTER_TYPE" != "searchcomputer" ]; then
  # Öppen gästdator(utan login)
  if [ "$ALMA_LOGIN" != "true" ]; then
      log_message "Öppen gästdator"
      # Starta om session after X minuters inaktivitet
      if [ "${SESSION_IDLE:-0}" -gt 0 ]; then
        xautolock -time $SESSION_IDLE -locker /home/guest/restart_x.sh &
      fi
      # Ta bort högerklick
      xmodmap /home/guest/.Xmodmap &
      # Mappning tangentbord
      xbindkeys &
      # Starta screensaver
      if [ "$SCREENSAVER" == "true" ]; then
        xscreensaver -no-splash &
      else
        # Se till att skärmen inte blir blank
        xset s off
        xset -dpms
        xset s noblank
      fi
      # Bakgrund 
      set_background
      # Starta openbox windows manager
      openbox &
      # Starta tint2 Dock
      tint2 -c /home/guest/.config/tint2/tint2rc &
      # Starta Chromium i fullskärm, och se till att den startar om ifall den avslutas helt av någon anledning
      while true; do
          launch_chromium
          sleep 1
      done
  else
    # Gästdator som kräver login
    CURRENT_BOOKING_ID_FILE="/tmp/current_booking_id.txt"
    CURRENT_ALMA_USER_ID_FILE="/tmp/current_alma_userid_id.txt"
    
    # Rensa filerna
    rm -f "$CURRENT_BOOKING_ID_FILE"
    rm -f "$CURRENT_ALMA_USER_ID_FILE"

    current_user=$(whoami)
    log_message "Current user: $current_user"

    # Kör bara för användare "guest"
    if [ "$current_user" == "guest" ]; then
      # Starta skärmsläckare om det är aktiverat
      if [ "$SCREENSAVER" == "true" ]; then
        xscreensaver -no-splash &
      else
        # Se till att skärmen inte blir blank
        xset s off
        xset -dpms
        xset s noblank
      fi
      if [ "$LOGIN_UI" == "web" ] && [ -s "$LOGIN_URL_FILE" ]; then
        prompt_for_login_web
      else
        prompt_for_code
      fi
      status=$?

      if [[ $status -eq 0 ]]; then
        # Bokningsdata
        # "// empty" ger tom sträng i stället för "null" när fältet saknas
        entry_id=$(echo "$form_input" | jq -r '.booking_data.id // empty' 2>/dev/null)
        create_by=$(echo "$form_input" | jq -r '.booking_data.create_by // empty' 2>/dev/null)
        start_time=$(echo "$form_input" | jq -r '.booking_data.start_time // empty' 2>/dev/null)
        end_time=$(echo "$form_input" | jq -r '.booking_data.end_time // empty' 2>/dev/null)

        # Kolla om bokningsdata existerar
        if [[ -z "$entry_id" || -z "$create_by" || -z "$start_time" || -z "$end_time" ]]; then
            log_message "ERROR: Electron output invalid or crashed, booking data missing."
            # Visa meddelandet en stund och starta sedan om sessionen (tillbaka till inloggningen)
            # i stället för att låsa datorn tills personal startar om den
            xmessage -center -buttons "" -timeout 15 "Inloggningen misslyckades, försök igen. Kontakta biblioteket om felet kvarstår. / The login failed, please try again. Contact the library if the problem persists."
            exit 1
        fi

        # Spara entry_id från bokningen
        echo "$entry_id" > "$CURRENT_BOOKING_ID_FILE"

        # Spara create_by från bokningen(för att visa usernamen i tint2)
        echo "$create_by" > "$CURRENT_ALMA_USER_ID_FILE"

        current_time=$(date +%s)
        seconds=$((end_time - current_time))
        log_message "Start time: $start_time, End time: $end_time, Duration: $seconds seconds"

        # Starta logout_timer.sh med antal sekunder som ska gå innan logout
        /usr/local/bin/logout_timer.sh "$seconds" &

        # Starta om X-session after X minuters inaktivitet, visa en varning 1 minut innan avslut
        if [ "${SESSION_IDLE:-0}" -gt 0 ]; then
            xautolock -time $SESSION_IDLE -notify 60 -notifier "/usr/local/bin/tint2_inactivity_warning.sh" -locker "pkill X" &
        fi
       
        # Ta bort högerklick
        xmodmap /home/guest/.Xmodmap &
       
        # Mappning tangentbord
        xbindkeys &
       
        # Se till att skärmen inte blir blank
        xset s off
        xset -dpms
        xset s noblank
       
        # Bakgrund
        set_background
       
        # Starta openbox windows manager
        openbox &
       
        # Starta tint2 Dock
        tint2 -c /home/guest/.config/tint2/tint2rc-alma &
       
        # Starta Chromium i fullskärm, och se till att den startar om ifall den avslutas helt av någon anledning
        while true; do
            launch_chromium
            sleep 1
        done
      else
        log_message "Error: Electron app failed with status $status. Restarting session."
        # Visa meddelande och vänta så att guest.service inte når systemds gräns för snabba omstarter
        xmessage -center -buttons "" -timeout 15 "Inloggningen startar om, vänta... / The login is restarting, please wait..."
        exit 1
      fi
    else
      log_message "Non-guest user detected. Starting session."
      # Se till att skärmen inte blir blank
      xset s off
      xset -dpms
      xset s noblank
      matchbox-window-manager &
      launch_chromium
    fi
  fi
else
  # Sökdator / Kiosk
  log_message "Starting session for search computer."
  # Starta om session after X minuters inaktivitet
  if [ "${SESSION_IDLE:-0}" -gt 0 ]; then
    xautolock -time $SESSION_IDLE -locker /home/guest/restart_x.sh &
  fi
  # Ta bort högerklick
  xmodmap /home/guest/.Xmodmap &
  # Mappning tangentbord
  xbindkeys &
  # Starta screensaver
  if [ "$SCREENSAVER" == "true" ]; then
    xscreensaver -no-splash &
  else
    # Se till att skärmen inte blir blank
    xset s off
    xset -dpms
    xset s noblank
  fi
  # Bakgrund
  set_background
  # Dölj muspekaren om SIGNAGE är true
  hide_mouse_cursor
  # Starta openbox windows manager
  openbox &
  # Starta tint2 Dock
  tint2 -c /home/guest/.config/tint2/tint2rc-search &
  # Starta Chromium i fullskärm, och se till att den startar om ifall den avslutas helt av någon anledning
  while true; do
      launch_chromium $KIOSK
      sleep 1
  done
fi
