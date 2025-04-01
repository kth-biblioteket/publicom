#!/bin/bash
################################################
####                                        ####
####    Installationsfil Publicom           ####
####    Ver 2.0                             ####
################################################

# Kontrollera att scriptet körs som root
if [ "$(id -u)" -ne "0" ]; then
    echo "Detta script måste köras som root." 1>&2
    exit 1
fi

# Läs in miljövariabler
ENV_FILE="/usr/local/bin/config/.config"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE file not found!"
    exit 1
fi

# Gör miljövariabler tillgängliga i script
source "$ENV_FILE"

# Läs in hemligheter
SECRET_FILE="/usr/local/bin/secrets/.secrets"

if [ ! -f "$SECRET_FILE" ]; then
    echo "Fel: $SECRET_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    source "$SECRET_FILE"
    echo "Hittade $SECRET_FILE"
fi
# Uppdatera paketlistan för ubuntu
apt update

# Sätt datum/tid
timedatectl set-timezone Europe/Stockholm

# Sätt brittisk engelska
locale-gen en_GB.UTF-8
update-locale LANG=en_GB.UTF-8

# Lägg till en gästanvändare utan lösenord för autologin och anslut till grupper
adduser guest --disabled-password --gecos ""
usermod -aG lpadmin video tty input guest

# Installera skrivarfunktion
apt install -y cups

# Lägg till KTH-Print-skrivare och drivrutin
apt install -y cups printer-driver-gutenprint
## Skapa med deneric drivrutin
lpadmin -p KTH-Print -E -v lpd://testkthb@kth-print3.ug.kth.se -m drv:///sample.drv/generic.ppd

## Eventuellt skapa med Minolta drivrutin
#curl -o /home/guest/https://s3.lib.kth.se/guestcomputer/KMbeuC658ux.ppd
#curl -o /usr/lib/cups/filter/KMbeuEmpPS.pl https://s3.lib.kth.se/guestcomputer/KMbeuEmpPS.pl
#chmod 755 KMbeuEmpPS.pl
#curl -o /usr/lib/cups/filter/KMbeuEnc.pm https://s3.lib.kth.se/guestcomputer/KMbeuEnc.pm
#chmod 755 KMbeuEnc.pm
#lpadmin -p KTH-Print -E -v lpd://testkthb@kth-print3.ug.kth.se -P /home/guest/KMbeuC658ux.ppd

# Defaultskrivare
lpadmin -d KTH-Print
# Skrivarinställningar
lpadmin -p KTH-Print -o PageSize=A4

# Installera GUI/Fönsterhanterare/chromium etc.
apt install -y --no-install-recommends xorg matchbox-window-manager chromium-browser xserver-xorg-legacy xinit tint2 xprintidle xbindkeys openbox zenity xscreensaver xscreensaver-gl-extra

# Installera xautolock för att kunna starta om sessioner efter inaktivitet
apt install -y xautolock

# Inaktivera automatiska uppdateringar
bash -c 'cat <<EOF > /etc/apt/apt.conf.d/10periodic
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF'

# Inaktivera automatiska uppdateringsmeddelanden
apt remove -y update-notifier update-notifier-common

# Konfigurera openbox
mkdir -p /home/guest/.config/openbox
cat <<'EOL' > /home/guest/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
  </desktops>
  <applications>
    <application type="normal">
      <decor>no</decor>
      <focus>yes</focus>
    </application>
  </applications>
</openbox_config>
EOL

# Skapa fil för datornamn att visas i tintpanelen
cat <<'EOL' > /usr/local/bin/update_tint_computer_name.sh
#!/bin/bash

# Ladda variabler från .config
source /usr/local/bin/config/.config

# Skriv ut variabeln
echo "$COMPUTER_NAME"
EOL

chmod +x /usr/local/bin/update_tint_computer_name.sh

# https://github.com/o9000/tint2/blob/master/doc/tint2.md
# Konfigurera tint2 som är en panel för att kunna visa text, klocka, status(tid kvar etc), knappar mm
mkdir -p /home/guest/.config/tint2

cat <<'EOL' > /home/guest/.config/tint2/tint2rc-search
# Backgrounds
# Background 1: Panel
rounded = 0
border_width = 0
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #000000 60
border_color = #000000 30
background_color_hover = #000000 60
border_color_hover = #000000 30
background_color_pressed = #000000 60
border_color_pressed = #000000 30


#-------------------------------------
# Panel
panel_items = T:F:E:C
panel_size = 100% 30
panel_margin = 0 0
panel_padding = 2 0 2
panel_background_id = 1
wm_menu = 1
panel_dock = 0
panel_pivot_struts = 0
panel_position = bottom center horizontal
panel_layer = bottom
panel_monitor = all
panel_shrink = 0
autohide = 0
autohide_show_timeout = 0
autohide_hide_timeout = 0.5
autohide_height = 2
strut_policy = follow_size
panel_window_name = tint2
disable_transparency = 0
mouse_effects = 1
font_shadow = 0
mouse_hover_icon_asb = 100 0 10
mouse_pressed_icon_asb = 100 0 0
scale_relative_to_dpi = 0
scale_relative_to_screen_height = 0

#-------------------------------------
# Task
task_padding = 10 5 10

#-------------------------------------
# Clock
time1_format = %H:%M
time2_format = %A %d %B
time1_timezone = 
time2_timezone = 
clock_font_color = #ffffff 100
clock_padding = 2 0
clock_background_id = 0
clock_tooltip = 
clock_tooltip_timezone = 
clock_lclick_command = 
clock_rclick_command = orage
clock_mclick_command = 
clock_uwheel_command = 
clock_dwheel_command = 


#-------------------------------------
# Tooltip
tooltip_show_timeout = 0.5
tooltip_hide_timeout = 0.1
tooltip_padding = 4 4
tooltip_background_id = 5
tooltip_font_color = #dddddd 100

# Executor 1
execp = new
execp_command = /usr/local/bin/update_tint_computer_name.sh
execp_interval = 0
execp_has_icon = 0
execp_cache_icon = 1
execp_continuous = 0
execp_markup = 1
execp_tooltip =
execp_lclick_command =
execp_rclick_command =
execp_mclick_command =
execp_uwheel_command =
execp_dwheel_command =
execp_font = Droid Sans Fallback 12
execp_font_color = #EBE5E0 100
execp_padding = 100 10
execp_background_id = 0
execp_centered = 0
execp_icon_w = 0
execp_icon_h = 0
EOL


cat <<'EOL' > /home/guest/.config/tint2/tint2rc
# Backgrounds
# Background 1: Panel
rounded = 0
border_width = 0
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #000000 60
border_color = #000000 30
background_color_hover = #000000 60
border_color_hover = #000000 30
background_color_pressed = #000000 60
border_color_pressed = #000000 30


#-------------------------------------
# Panel
panel_items = T:F:E:C
panel_size = 100% 30
panel_margin = 0 0
panel_padding = 2 0 2
panel_background_id = 1
wm_menu = 1
panel_dock = 0
panel_pivot_struts = 0
panel_position = bottom center horizontal
panel_layer = bottom
panel_monitor = all
panel_shrink = 0
autohide = 0
autohide_show_timeout = 0
autohide_hide_timeout = 0.5
autohide_height = 2
strut_policy = follow_size
panel_window_name = tint2
disable_transparency = 0
mouse_effects = 1
font_shadow = 0
mouse_hover_icon_asb = 100 0 10
mouse_pressed_icon_asb = 100 0 0
scale_relative_to_dpi = 0
scale_relative_to_screen_height = 0

#-------------------------------------
# Task
task_padding = 10 5 10

#-------------------------------------
# Clock
time1_format = %H:%M
time2_format = %A %d %B
time1_timezone = 
time2_timezone = 
clock_font_color = #ffffff 100
clock_padding = 2 0
clock_background_id = 0
clock_tooltip = 
clock_tooltip_timezone = 
clock_lclick_command = 
clock_rclick_command = orage
clock_mclick_command = 
clock_uwheel_command = 
clock_dwheel_command = 


#-------------------------------------
# Tooltip
tooltip_show_timeout = 0.5
tooltip_hide_timeout = 0.1
tooltip_padding = 4 4
tooltip_background_id = 5
tooltip_font_color = #dddddd 100

# Executor 1
execp = new
execp_command = /usr/local/bin/update_tint_computer_name.sh
execp_interval = 0
execp_has_icon = 0
execp_cache_icon = 1
execp_continuous = 0
execp_markup = 1
execp_tooltip =
execp_lclick_command =
execp_rclick_command =
execp_mclick_command =
execp_uwheel_command =
execp_dwheel_command =
execp_font = Droid Sans Fallback 12
execp_font_color = #EBE5E0 100
execp_padding = 100 10
execp_background_id = 0
execp_centered = 0
execp_icon_w = 0
execp_icon_h = 0
EOL

cat <<'EOL' > /home/guest/.config/tint2/tint2rc-alma
# Backgrounds
# Background 1: Panel
rounded = 0
border_width = 0
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #000061 60
border_color = #6298D2 30
background_color_hover = #000061 60
border_color_hover = #000061 30
background_color_pressed = #000061 60
border_color_pressed = #000061 30


#-------------------------------------
# Panel
panel_items = T:P:F:E:E:E:E:C
panel_size = 100% 30
panel_margin = 0 0
panel_padding = 2 0 2
panel_background_id = 1
wm_menu = 1
panel_dock = 0
panel_pivot_struts = 0
panel_position = bottom center horizontal
panel_layer = bottom
panel_monitor = all
panel_shrink = 0
autohide = 0
autohide_show_timeout = 0
autohide_hide_timeout = 0.5
autohide_height = 2
strut_policy = follow_size
panel_window_name = tint2
disable_transparency = 0
mouse_effects = 1
font_shadow = 0
mouse_hover_icon_asb = 100 0 10
mouse_pressed_icon_asb = 100 0 0
scale_relative_to_dpi = 0
scale_relative_to_screen_height = 0

#-------------------------------------
# Task
task_padding = 10 5 10

#-------------------------------------
# Clock
time1_format = %H:%M
time2_format = %A %d %B
time1_timezone = 
time2_timezone = 
clock_font_color = #ffffff 100
clock_padding = 2 0
clock_background_id = 1
clock_tooltip = 
clock_tooltip_timezone = 
clock_lclick_command = 
clock_rclick_command = orage
clock_mclick_command = 
clock_uwheel_command = 
clock_dwheel_command = 


#-------------------------------------
# Tooltip
tooltip_show_timeout = 0.5
tooltip_hide_timeout = 0.1
tooltip_padding = 4 4
tooltip_background_id = 1
tooltip_font_color = #dddddd 100

# Executor 1 - Visa inloggad användare
execp = new
execp_command = cat /tmp/current_alma_userid_id.txt
execp_interval = 0
execp_has_icon = 0
execp_cache_icon = 0
execp_continuous = 0
execp_markup = 1
execp_tooltip =
execp_lclick_command =
execp_rclick_command =
execp_mclick_command =
execp_uwheel_command =
execp_dwheel_command =
execp_font = "Sans" 12
execp_font_color = #ffffff 100
execp_padding = 50 50 10
execp_background_id = 1
execp_centered = 0

# Executor 2 - Visa datornamn
execp = new
execp_command = /usr/local/bin/update_tint_computer_name.sh
execp_interval = 0
execp_has_icon = 0
execp_cache_icon = 0
execp_continuous = 0
execp_markup = 1
execp_tooltip =
execp_lclick_command =
execp_rclick_command =
execp_mclick_command =
execp_uwheel_command =
execp_dwheel_command =
execp_font = "Sans" 12
execp_font_color = #ffffff 100
execp_padding = 50 50 10
execp_background_id = 1
execp_centered = 0

# Executor 3 - Visa kvarvarande tid för sessionen
execp = new
execp_command = echo "$(/usr/local/bin/show_remaining_time.sh)"
execp_interval = 1
execp_has_icon = 1
execp_cache_icon = 1
execp_icon_w = 32  # Width of the icon
execp_icon_h = 32  # Height of the icon
execp_continuous = 0
execp_markup = 1
execp_tooltip = Left click for hardinfo
execp_lclick_command = hardinfo
execp_rclick_command = 
execp_mclick_command = 
execp_uwheel_command = 
execp_dwheel_command = 
execp_font = "Sans" 12
execp_font_color = #ffffff 100
execp_padding = 50 50 10
execp_background_id = 1
execp_centered = 0

# Executor 4 - Inaktivitetsvarning
execp = new
execp_command = cat /tmp/tint2_inactivity_warning.txt
execp_interval = 1
execp_has_icon = 1
execp_icon_w = 32  
execp_icon_h = 32  
execp_cache_icon = 1
execp_continuous = 0
execp_markup = 1
execp_tooltip = Left click to clear
execp_lclick_command = /usr/local/bin/clear_inactivity.sh
execp_font = "Sans" 12
execp_font_color = #FF8282 100
execp_padding = 50 50 10
execp_background_id = 1
execp_centered = 0

#-------------------------------------
# Button 1
button = new
button_icon = /usr/share/icons/Humanity/actions/32/xfsm-logout.svg
button_text = Logout
button_lclick_command = /usr/local/bin/logout_and_cancel.sh
button_rclick_command =
button_mclick_command =
button_uwheel_command =
button_dwheel_command =
button_font_color = #ffffff 100
button_padding = 5 0
button_background_id = 1
button_centered = 0
button_max_icon_size = 28
EOL

# Inaktivetetsvarning, anropas av autolock vid sessionsstart
cat <<'EOL' > /usr/local/bin/tint2_inactivity_warning.sh 
#!/bin/bash

WARNING_FILE="/tmp/tint2_inactivity_warning.txt"

# Skriv meddelande till tint2
echo -e "/usr/local/bin/icons/icons8-red-circle-32.png\nInactive session will terminate soon!" > "$WARNING_FILE"

# Vänta så idle_time hinner uppdateras
sleep 2

# Övervaka aktivitet
for i in {1..60}; do
    IDLE_TIME=$(xprintidle)
    if [[ $IDLE_TIME -lt 1000 ]]; then
        # Användaren aktiv, rensa meddelande
        echo -e "/usr/local/bin/icons/icons8-green-circle-32.png\n " > "$WARNING_FILE"
        exit 0
    fi
    sleep 1
done

exit 0
EOL

chmod +x /usr/local/bin/tint2_inactivity_warning.sh

# Rensa aktivitetsvarning
cat <<'EOL' > /usr/local/bin/clear_inactivity.sh
#!/bin/bash
echo -e "/usr/local/bin/icons/icons8-green-circle-32.png\n " > /tmp/tint2_inactivity_warning.txt
EOL

chmod +x /usr/local/bin/clear_inactivity.sh

# Ser till att konsol inte visas
systemctl disable getty@tty1

# Ser till att högerklick inaktiveras (kontextmenyer etc)
cat <<'EOL' > /home/guest/.Xmodmap 
pointer = 1 2 0 4 5 6 7 8 9
EOL

# Stäng av magic sysrq
cat <<'EOL' > /etc/sysctl.d/99-disable-sysrq.conf
kernel.sysrq = 0
EOL

# Stäng av hårdvaruknappar/funktionsknappar
mkdir -p /etc/systemd/logind.conf.d
cat <<'EOL' > /etc/systemd/logind.conf.d/50-disable-sleep.conf
[Login]
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKey=ignore
EOL

# Mappa tangenter
# Förhindrar t ex diverse kombinationer.
# Todo definiera flera?
cat <<'EOL' > /home/guest/.xbindkeysrc
#disable shift+click
"true"
m:0x01 + b:1

"NoSymbol"
Control + a

"NoSymbol"
Control + b

"NoSymbol"
Control + d

"NoSymbol"
Control + e

"NoSymbol"
Control + f

"NoSymbol"
Control + g

"NoSymbol"
Control + h

"NoSymbol"
Control + i

"NoSymbol"
Control + j

"NoSymbol"
Control + k

"NoSymbol"
Control + l

"NoSymbol"
Control + m

"NoSymbol"
Control + Shift + m

"NoSymbol"
Control + n

"NoSymbol"
Control + Shift + n

"NoSymbol"
Control + o

#"NoSymbol"
#Control + p

"NoSymbol"
Control + q

"NoSymbol"
Control + r

"NoSymbol"
Control + s

"NoSymbol"
Control + t

"NoSymbol"
Control + u

"NoSymbol"
Control + w

"NoSymbol"
Control + Shift + w

"NoSymbol"
Control + x

"NoSymbol"
Control + y

"NoSymbol"
Control + z

"NoSymbol"
Control + Alt + Delete

"NoSymbol"
Alt + F1

"NoSymbol"
Alt + F2

"NoSymbol"
Alt + F3

"NoSymbol"
Alt + F4

"NoSymbol"
Alt + F5

"NoSymbol"
Alt + F6

"NoSymbol"
Alt + F7

"NoSymbol"
Alt + F8

"NoSymbol"
Alt + F9

"NoSymbol"
Alt + F10

"NoSymbol"
Alt + F11

"NoSymbol"
Alt + F12
EOL

# Skapa skript som rensar nedladdningar och andra filer
cat <<'EOL' > /usr/local/bin/clean-up.sh
#!/bin/bash
GUEST_HOME="/home/guest/snap/chromium/current"
TARGET_DIRS=("Desktop" "Documents" "Downloads" "Music" "Pictures" "Public" "Templates" "Videos")
for DIR in "${TARGET_DIRS[@]}"; do
  if [ -d "$GUEST_HOME/$DIR" ]; then
    # Delete everything (files, hidden files, subdirectories) in the target directory
    find "$GUEST_HOME/$DIR" -mindepth 1 -exec rm -rf {} +
  fi
done
EOL

chmod +x /usr/local/bin/clean-up.sh

# Skapa skript som startar om browsern efter viss tid (för icke inloggad användare)
# Se till att rensa eventuella nedladdningar etc
cat <<'EOL' > /home/guest/restart_x.sh
#!/bin/bash
/usr/local/bin/clean-up.sh
pkill -f chromium-browser
sleep 1
EOL

chmod +x /home/guest/restart_x.sh

# Skapa skript för att användaren ska kunna logga ut(via knapp i tint2 t ex)
# Se till att rensa eventuella nedladdningar etc
cat <<'EOL' > /usr/local/bin/logout_and_cancel.sh
#!/bin/bash

if zenity --question --text="Are you sure you want to log out?"; then
    /usr/local/bin/clean-up.sh
    pkill X
fi
EOL

# Skapa screensaver-folder
mkdir -p /usr/local/bin/screensaver

# Skapa fil för att konfigurera screensaver
cat <<'EOL' > /home/guest/.xscreensaver
timeout:        0:00:10
chooseRandomImages: True
imageDirectory: /usr/local/bin/screensaver
mode:           one
selected:       0

programs: \
- GL:   glslideshow -root -duration 10 -zoom 100 -pan 1 -fade 0 \n\
EOL

chmod +x /usr/local/bin/logout_and_cancel.sh

# Skapa skript som startar om sessionen efter viss tid (för inloggad användare)
cat <<'EOL' > /usr/local/bin/logout_timer.sh
#!/bin/bash

LOG_FILE="/tmp/logout_timer.log"

function log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if [ -n "$1" ]; then
    TIMEOUT_SECONDS=$1
    log_message "Received timeout duration: $TIMEOUT_SECONDS seconds"
else
    LOGOUT_AFTER_MINUTES=60
    TIMEOUT_SECONDS=$((LOGOUT_AFTER_MINUTES * 60))
    log_message "Using default timeout duration: $TIMEOUT_SECONDS seconds"
fi

TIME_FILE="/tmp/logout_timer.txt"

REMAINING_TIME_FILE="/tmp/remaining_time.txt"

# Spara starttiden för sessionen i en fil
if [ ! -f "$TIME_FILE" ]; then
    date +%s > "$TIME_FILE"
fi

START_TIME=$(cat "$TIME_FILE")

# Loop för att uppdatera hur lång tid som är kvar och avsluta sessionen när tiden är slut
# Kvarvarande tid i minuter och sekunder sparas till fil som kan läsas och visas för användaren
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    REMAINING_TIME=$((TIMEOUT_SECONDS - ELAPSED_TIME))

    if [ $REMAINING_TIME -le 0 ]; then
        echo "00:00" > "$REMAINING_TIME_FILE"
        # rm -f "$TIME_FILE"
        # Avsluta X-sessionen för användaren(guest.service startar då om hela sessionen för användaren så att electron-appen för login startar igen)
        /usr/local/bin/clean-up.sh
        pkill X
        exit
    else
        REMAINING_MINUTES=$((REMAINING_TIME / 60))
        REMAINING_SECONDS=$((REMAINING_TIME % 60))
        FORMATTED_TIME=$(printf "%02d:%02d" $REMAINING_MINUTES $REMAINING_SECONDS)
        # Visa varning är det är x minuter kvar av tiden
        if [ $REMAINING_TIME -le 60 ]; then
            echo -e "/usr/share/icons/Humanity/actions/32/gtk-cancel.svg\nYour session will end soon $FORMATTED_TIME" > "$REMAINING_TIME_FILE"
        else
            echo -e "/usr/share/icons/Humanity/apps/32/clock.svg\nRemaning time: $FORMATTED_TIME" > "$REMAINING_TIME_FILE"
        fi
    fi
    sleep 1
done
EOL

chmod +x /usr/local/bin/logout_timer.sh

#script för att visa hur lång tid som är kvar till logout i tint2

cat <<'EOL' > /usr/local/bin/show_remaining_time.sh
#!/bin/bash

# Check if the file exists
if [ -f /tmp/remaining_time.txt ]; then
    # If the file exists, display its content
    cat /tmp/remaining_time.txt
else
    # If the file does not exist, show blank
    echo ""
fi
EOL

chmod +x /usr/local/bin/show_remaining_time.sh

# Start-skript för guest
sudo -u guest cat <<'EOL' > /home/guest/.xinitrc
#!/bin/bash

/usr/local/bin/clean-up.sh

LOG_FILE="/tmp/guest_login.log"

function log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

## Starta electron-appen för login
function prompt_for_code() {
  form_input=$(npx electron /usr/local/bin/electron-login/main.js)
  log_message "Raw JSON output: $form_input"
  return $?
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

# Ta bort filen som innehåller starttiden för sessionen
rm -f /tmp/logout_timer.txt

# Rensa tint2 warnings
echo -e "/usr/local/bin/icons/icons8-green-circle-32.png\n " > /tmp/tint2_inactivity_warning.txt

# Uppdatera timeout för skärmsläckare
sed -i "s/^timeout:.*$/timeout: $SCREENSAVER_IDLE/" /home/guest/.xscreensaver

if [ "$COMPUTER_TYPE" != "searchcomputer" ]; then
  # Öppen gästdator(utan login)
  if [ "$ALMA_LOGIN" != "true" ]; then
      log_message "Öppen gästdator"
      # Starta om session after X minuters inaktivitet
      xautolock -time $SESSION_IDLE -locker /home/guest/restart_x.sh &
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
      feh --bg-scale /usr/local/bin/screen_bg_kth_logo_navy.png
      # Starta openbox windows manager
      openbox &
      # Starta tint2 Dock
      tint2 -c /home/guest/.config/tint2/tint2rc &
      # Starta Chromium i fullskärm, och se till att den startar om ifall den avslutas helt av någon anledning
      while true; do
          chromium-browser --start-maximized --user-data-dir=/tmp/chromium-temp-profile --incognito --no-first-run --disable-session-crashed-bubble --disable-features=TranslateUI $WEBSITES
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
      prompt_for_code
      status=$?

      if [[ $status -eq 0 ]]; then
        # Bokningsdata
        entry_id=$(echo "$form_input" | jq -r '.booking_data.id')
        create_by=$(echo "$form_input" | jq -r '.booking_data.create_by')
        start_time=$(echo "$form_input" | jq -r '.booking_data.start_time')
        end_time=$(echo "$form_input" | jq -r '.booking_data.end_time')

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
        xautolock -time $SESSION_IDLE -notify 60 -notifier "/usr/local/bin/tint2_inactivity_warning.sh" -locker "pkill X" &
       
        # Ta bort högerklick
        xmodmap /home/guest/.Xmodmap &
       
        # Mappning tangentbord
        xbindkeys &
       
        # Se till att skärmen inte blir blank
        xset s off
        xset -dpms
        xset s noblank
       
        # Bakgrund
        feh --bg-scale /usr/local/bin/screen_bg_kth_logo_navy.png
       
        # Starta openbox windows manager
        openbox &
       
        # Starta tint2 Dock
        tint2 -c /home/guest/.config/tint2/tint2rc-alma &
       
        # Starta Chromium i fullskärm, och se till att den startar om ifall den avslutas helt av någon anledning
        while true; do
            chromium-browser --start-maximized --user-data-dir=/tmp/chromium-temp-profile --incognito --no-first-run --disable-session-crashed-bubble --disable-features=TranslateUI $WEBSITES
            sleep 1
        done
      else
        log_message "Error: Electron app failed. Displaying error message."
        #yad --error --text="Something unexpected occurred. Please try again." --center --button="OK:0"
        exit 1
      fi
    else
      log_message "Non-guest user detected. Starting session."
      # Se till att skärmen inte blir blank
      xset s off
      xset -dpms
      xset s noblank
      matchbox-window-manager &
      chromium-browser --start-maximized --user-data-dir=/tmp/chromium-temp-profile \
        --incognito --no-first-run --disable-session-crashed-bubble \
        --disable-features=TranslateUI $WEBSITES
    fi
  fi
else
  # Sökdator / Kiosk
  log_message "Starting session for search computer."
  # Starta om session after X minuters inaktivitet
  xautolock -time $SESSION_IDLE -locker /home/guest/restart_x.sh &
  # Ta bort högerklick
  xmodmap /home/guest/.Xmodmap &
  # Mappning tangentbord
  xbindkeys &
  # Starta screensaver
  if [ "$SCREENSAVER" == "true" ]; then
    xscreensaver -no-splash &
  fi
  # Bakgrund
  feh --bg-scale /usr/local/bin/screen_bg_kth_logo_navy.png
  # Starta openbox windows manager
  openbox &
  # Starta tint2 Dock
  tint2 -c /home/guest/.config/tint2/tint2rc-search &
  # Starta Chromium i fullskärm, och se till att den startar om ifall den avslutas helt av någon anledning
  while true; do
      chromium-browser $KIOSK --start-maximized --user-data-dir=/tmp/chromium-temp-profile --incognito --no-first-run --disable-session-crashed-bubble --disable-features=TranslateUI $WEBSITES
      sleep 1
  done
fi
EOL

# Gör script exekverbart med rätt ägare
chmod +x /home/guest/.xinitrc
chown guest:guest /home/guest/.xinitrc

# Skapa init skript
cat <<'EOL' > /usr/local/bin/init.sh
#!/bin/bash

ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"

if [ ! -f "$ENV_FILE" ]; then
    echo "Fel: $ENV_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    source "$ENV_FILE"
    echo "Hittade $ENV_FILE"
fi

if [ ! -f "$SECRET_FILE" ]; then
    echo "Fel: $SECRET_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    source "$SECRET_FILE"
    echo "Hittade $SECRET_FILE"
fi

# Hämta configfil från GitHub och spara till den lokala datorn
URL=REMOTE_CONFIG_URL
if curl -s -o /usr/local/bin/config/.config $REMOTE_CONFIG_URL; then
   echo "Successfully downloaded $REMOTE_CONFIG_URL"
else
   echo "Error downloading $REMOTE_CONFIG_URL"
fi
source "$ENV_FILE"

# Skärmsläckarfiler
rm -rf /usr/local/bin/screensaver/*
IFS=',' read -ra FILE_ARRAY <<< "$SCREENSAVER_FILES"
for file in "${FILE_ARRAY[@]}"; do
    echo "Downloading $file..."
    if curl -s -o "/usr/local/bin/screensaver/$file" "https://raw.githubusercontent.com/kth-biblioteket/publicom/main/screensaver/$file"; then
        echo "Successfully downloaded $file"
    else
        echo "Error downloading $file"
    fi
done

# Chrome policy
echo "Downloading policy $POLICY_FILE"
if curl -s -o "/var/snap/chromium/current/policies/managed/policies.json" "https://raw.githubusercontent.com/kth-biblioteket/publicom/main/$POLICY_FILE"; then
  echo "Successfully downloaded $POLICY_FILE"
else
  echo "Error downloading $POLICY_FILE"
fi
EOL
chmod +x /usr/local/bin/init.sh

# Skapa service för init
cat <<'EOL' > /etc/systemd/system/init.service 
[Unit]
Description=Kör init.sh vid start
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/init.sh

[Install]
WantedBy=multi-user.target
EOL

systemctl enable init.service

# Skapa service som hämtar tillåtelselista från EZProxy vid startup
cat <<'EOL' > /etc/systemd/system/allowlist_from_ezproxy.service 
[Unit]
Description=Run allowlist_from_ezproxy script at startup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/local/bin/allowlist_from_ezproxy.sh

[Install]
WantedBy=multi-user.target
EOL

systemctl enable allowlist_from_ezproxy.service

# Skapa service för att starta sessionen(och startar om den ifall den avslutas helt av någon anledning)
cat <<'EOL' > /etc/systemd/system/guest.service
[Unit]
Description=Guest Mode
# After=allowlist_from_ezproxy.service systemd-user-sessions.service
# Requires=allowlist_from_ezproxy.service

[Service]
User=guest
Restart=always
ExecStart=/usr/bin/startx
Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
EOL

systemctl enable guest.service

# Skapa service som körs vid avslut av session
cat <<'EOL' > /etc/systemd/system/session-cleanup.service
[Unit]
Description=Cleanup after guest session
After=guest.service
Requires=guest.service

[Service]
Type=simple
ExecStart=/usr/local/bin/session_cleanup.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOL

systemctl enable session-cleanup.service

# Skapa skript som körs vid avslut av session
cat <<'EOL' > /usr/local/bin/session_cleanup.sh
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

if [ "$BOOKING_TYPE" == "dropin" ]; then
    if [ -z "$BOOKING_API_KEY" ]; then
        echo "Error: API key (BOOKING_API_KEY) not found in $SECRET_FILE" >> /var/log/guest_cleanup.log
        exit 0
    else
        echo "BOOKING_API_KEY: $BOOKING_API_KEY"
    fi

    if [ -z "$RESERVATION_API_UPDATE_URL" ]; then
        echo "Error: API key (RESERVATION_API_UPDATE_URL) not found in $ENV_FILE" >> /var/log/guest_cleanup.log
        exit 0
    fi

    BOOKING_ID=$(cat /tmp/current_booking_id.txt)

    if [ -z "$BOOKING_ID" ]; then
        echo "Error: booking_id not found in /tmp/current_booking_id.txt" >> /var/log/guest_cleanup.log
        exit 0
    else
        echo "Booking id: $BOOKING_ID"
    fi

    END_TIME=$(date +%s)

    echo "end_time: $END_TIME"

    API_URL="$RESERVATION_API_UPDATE_URL$BOOKING_ID?end_time=$END_TIME"

    echo "API_URL: $API_URL"

    API_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/api_response.json -X POST "$API_URL" \
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
EOL

chmod +x /usr/local/bin/session_cleanup.sh

## Tillåt alla att starta x11
cat <<'EOL' > /etc/X11/Xwrapper.config
allowed_users=anybody
needs_root_rights=yes
EOL

# Skapa policies för chromium för diverse inställningar(allowlists etc)
## https://chromeenterprise.google/policies/

mkdir /var/snap/chromium/current/policies
mkdir /var/snap/chromium/current/policies/managed
curl -s -o "/var/snap/chromium/current/policies/managed/policies.json" "https://raw.githubusercontent.com/kth-biblioteket/publicom/main/$POLICY_FILE"

chmod 777 /var/snap/chromium/current/policies/managed/policies.json

# Skapa script som hämtar domänlista från github och uppdaterar chromiums policy
# Beroende av att token för github finns i .env filen
# Körs vid start av dator
cat <<'EOL' > /usr/local/bin/allowlist_from_ezproxy.sh
#!/bin/bash

ENV_FILE="/usr/local/bin/config/.config"
SECRET_FILE="/usr/local/bin/secrets/.secrets"

if [ ! -f "$ENV_FILE" ]; then
    echo "Fel: $ENV_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    source "$ENV_FILE"
    echo "Hittade $ENV_FILE"
fi

if [ ! -f "$SECRET_FILE" ]; then
    echo "Fel: $SECRET_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    source "$SECRET_FILE"
    echo "Hittade $SECRET_FILE"
fi

# Aktivera printer för chrome
if [ "$PRINTER" == "true" ]; then
  POLICY_PATH="/var/snap/chromium/current/policies/managed/policies.json"
  POLICY=$(cat $POLICY_PATH | jq '.PrintingEnabled = true')
  echo $POLICY | jq '.' > $POLICY_PATH
fi
if [ "$COMPUTER_TYPE" != "searchcomputer" ]; then
  ###########
  # Gästdator
  ###########
  # Om ALMA_LOGIN är true så ska ska inget blockeras
  if [ "$ALMA_LOGIN" == "true" ]; then
    POLICY_PATH="/var/snap/chromium/current/policies/managed/policies.json"
    POLICY=$(cat $POLICY_PATH | jq '.URLBlocklist = []')
    echo $POLICY | jq '.' > $POLICY_PATH
  else
    # Om gästdatorn är öppen(utan login)

    # Finns githubtoken för att hämta stanzafil(ezproxy) med tillåtna domäner
    if [ -z "$GITHUB_TOKEN" ]; then
      echo "Error: GITHUB_TOKEN is not set in $ENV_FILE"
    else
      # Hämta stanzafil(ezproxy)
      URL="https://raw.githubusercontent.com/kth-biblioteket/ezproxy/main/db_stanzas.txt"

      curl -H "Authorization: token $GITHUB_TOKEN" -L -o /tmp/db_stanzas.txt $URL

      # Skapa en lista med tillåtna domäner
      IFS=',' read -r -a ALLOWED_DOMAINS <<< "$WHITE_LIST"

      # Lägg till domäner från stanzafil(ezproxy)
      while IFS= read -r line; do
        if [[ $line =~ ^(URL|HJ|DJ) ]]; then
            DOMAIN=$(echo $line | cut -d' ' -f2)
            DOMAIN="${DOMAIN/http:\/\//https:\/\/}"
            if [[ ! $DOMAIN =~ ^https:// ]]; then
                DOMAIN="https://$DOMAIN"
            fi
            # Ta bort allt efter toppdomänen
            DOMAIN=$(echo "$DOMAIN" | awk -F[/:] '{print $4}')
            # Kontrollera om det redan finns en huvuddomän
            BASE_DOMAIN=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
            # Spara domäner i en lista
            ALLOWED_DOMAINS+=("$BASE_DOMAIN")
        fi
      done < /tmp/db_stanzas.txt

      POLICY_PATH="/var/snap/chromium/current/policies/managed/policies.json"

      POLICY=$(cat $POLICY_PATH)

      POLICY=$(cat $POLICY_PATH | jq '.URLBlocklist = ["*","google.com","google.com"]')

      ALLOWED_DOMAINS_JSON=$(printf '"%s",' "${ALLOWED_DOMAINS[@]}" | sed 's/,$//')

      POLICY=$(echo $POLICY | jq '.URLAllowlist = []')

      POLICY=$(echo $POLICY | jq --argjson domains "[$ALLOWED_DOMAINS_JSON]" '.URLAllowlist += $domains')

      POLICY=$(echo $POLICY | jq '.URLAllowlist |= unique')

      # Spara till policyfilen
      echo $POLICY | jq '.' > $POLICY_PATH
    fi
  fi
else
  ###########
  # Sökdator
  ###########
  POLICY_PATH="/var/snap/chromium/current/policies/managed/policies.json"
  IFS=',' read -r -a ALLOWED_DOMAINS <<< "$WHITE_LIST"
  POLICY=$(cat $POLICY_PATH)

  POLICY=$(cat $POLICY_PATH | jq '.URLBlocklist = ["*","google.com","google.com"]')

  ALLOWED_DOMAINS_JSON=$(printf '"%s",' "${ALLOWED_DOMAINS[@]}" | sed 's/,$//')

  POLICY=$(echo $POLICY | jq '.URLAllowlist = []')
  POLICY=$(echo $POLICY | jq --argjson domains "[$ALLOWED_DOMAINS_JSON]" '.URLAllowlist += $domains')

  POLICY=$(echo $POLICY | jq '.URLAllowlist |= unique')
  echo $POLICY
  # Spara till policyfilen
  echo $POLICY | jq '.' > $POLICY_PATH
fi
EOL

# Gör exekverbart
chmod +x /usr/local/bin/allowlist_from_ezproxy.sh

###### Electron Login App #######
# main.js 
# preload.js 
# index.html
#################################
mkdir /usr/local/bin/electron-login

cat <<'EOL' > /usr/local/bin/electron-login/main.js
const { app, BrowserWindow, screen, ipcMain, Menu, globalShortcut } = require('electron');
const path = require('path');
const axios = require('axios');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '../config', '.config') });

const { BOOKING_TYPE, DEFAULT_BOOKING_TIME, API_URL, RESERVATION_API_URL, BOOKING_SYSTEM_URL, RESOURCE_ID, LOGINTYPE, REGISTER_ACCOUNT_URL, RESERVATION_API_CREATE_URL, RESERVATION_API_UPDATE_URL, RESERVATION_API_CURRENT_RES_URL, MAIN_WINDOW_TIMEOUT, EXTERNAL_URL_TIMEOUT, ELECTRON_DEV_TOOLS } = process.env;

let mainWindow;
let newWindow;
let storedUsername = '';
let inactivityTimer = null;
let authToken = null;

/**
 * Verifies the user's code (PIN or password).
 * @param {string} username - The username.
 * @param {string} code - The PIN or password.
 * @returns {Promise<string>} The verification result.
 */
async function verifyCode(username, code) {
    try {
        const endpoint = LOGINTYPE === 'pin' ? API_URL : `${API_URL}?op=auth`;
        const data = LOGINTYPE === 'pin' ? { user: username, pin_number: code } : { user: username, password: code };
        const response = await axios.post(endpoint, data, { timeout: 10000 });
        switch (response.data.message) {
            //Skicka tillbaks almas primary_id om allt är ok
            case 'Success': {
                authToken = response.data.token;
                return response.data.data.primary_id;
            }
            default: return 'invalid';
        }
    } catch (error) {
        if (error.response) {
            if (error.response.status === 400) return 'invalid-username';
            if (error.response.status === 401) return 'invalid';
        }
        console.error('Error: ' + error);
        return 'error';
    }
}

/**
 * Checks the reservation for a given username.
 * @param {string} username - The username.
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_URL:user_id/:room_id"
 */
async function checkReservation(username) {
    try {
        const response = await axios.post(`${RESERVATION_API_URL}${username}/${RESOURCE_ID}`, {
            alma_user_id: username,
            resource_id: RESOURCE_ID,
        }, { timeout: 10000 });

        return response.data;
    } catch (error) {
        console.error('Error checking reservation:', error);
        return 'Error: Could not check reservation';
    }
}

/**
 * Checks the reservation for the current resource.
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_CURRENT_RES_URL:room_id"
 */
async function checkCurrentReservationStatus() {
    try {
        const response = await axios.post(`${RESERVATION_API_CURRENT_RES_URL}${RESOURCE_ID}`, {
        }, { timeout: 10000 });

        return response.data;
    } catch (error) {
        console.error('Error checking reservation:', error);
        return 'Error: Could not check reservation';
    }
}

/**
 * Creates a reservation for a given username.
 * @param {string} room_id - The id for the computer/resource.
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_CREATE_URL:room_id"
 */
async function createReservation(create_by, name, start_time, end_time) {
    try {
        const response = await axios.post(
          `${RESERVATION_API_CREATE_URL}${RESOURCE_ID}`,
          {
              create_by,
              name,
              start_time,
              end_time
          },
          {
              timeout: 10000,  
              headers: { 
                "Content-Type": "application/json",
                "x-access-token": authToken,
              }  
          }
        );
        return response.data;
    } catch (error) {
        console.error('Error creating reservation:', error.message);
        return 'Error: Could not create reservation';
    }
}

/**
 * Updates a reservation for a given entry_id.
 * @param {string}
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_UPDATE_URL:entry_i"
 */
async function resetReservation(entry_id) {
    try {
        // Sätt sluttid till nu minus 10 sekunder för att säkerställa att en kontroll inte visar att bokning finns.
        const end_time = new Date();
        const endTimestamp = Math.floor(end_time.getTime() / 1000) - 10;
        const response = await axios.post(
          `${RESERVATION_API_UPDATE_URL}${entry_id}?end_time=${endTimestamp}`,
          {},
          {
              timeout: 10000,  
              headers: { 
                "Content-Type": "application/json",
                "x-access-token": authToken,
              }  
          }
        );
        return response.data;
    } catch (error) {
        console.error('Error updating reservation:', error);
        return 'Error: Could not update reservation';
    }
}

/**
 * Creates the main application window.
 */
function createMainWindow() {
    const { width, height } = screen.getPrimaryDisplay().workAreaSize;

    mainWindow = new BrowserWindow({
        width,
        height,
        frame: false,
        transparent: false,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            devTools: ELECTRON_DEV_TOOLS === 'true'
        },
    });

    const dynamicComputerName = process.env.RESOURCE_ID || '1';

    mainWindow.loadFile('index.html', { query: { computername: dynamicComputerName, bookingType: BOOKING_TYPE } });

    mainWindow.on('closed', () => {
        if (statusUpdateInterval) clearInterval(statusUpdateInterval);
        mainWindow = null;
    });

    let statusUpdateInterval;

    mainWindow.webContents.on('did-finish-load', async() => {
        //Kontrollera om det finns en bokning
        //Görs inte för dropin-datorer
        if (BOOKING_TYPE === 'dropin') {
            //Sätt status till obokad
            mainWindow.webContents.send('current-status', {valid: false});
        } else {
            async function updateReservationStatus() {
                const currentstatus = await checkCurrentReservationStatus();
                mainWindow.webContents.send('current-status', currentstatus);
            }
            updateReservationStatus();
            statusUpdateInterval = setInterval(updateReservationStatus, 10000);
        }
        mainWindow.webContents.send('load-username', storedUsername);
        const placeholder = LOGINTYPE === 'pin' ? 'PIN' : 'lösenord / password';
        mainWindow.webContents.executeJavaScript(`
            const input = document.getElementById('pin');
            if (input) input.placeholder = '${placeholder}';
        `);
    });

    mainWindow.on('close', (event) => event.preventDefault());
}

/**
 * Creates a new window for external URLs or specific content.
 * @param {string} url - The URL to load.
 */
function createNewWindow(url) {
    const { width, height } = screen.getPrimaryDisplay().workAreaSize;

    newWindow = new BrowserWindow({
        width,
        height,
        frame: false,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            sandbox: false,
            devTools: ELECTRON_DEV_TOOLS === 'true'
        },
    });

    newWindow.loadURL(url);

    newWindow.webContents.on('did-navigate', (event, currentUrl) => {
        if (currentUrl !== `file://${path.join(__dirname, 'index.html')}`) injectExternalScript(newWindow);
    });

    newWindow.on('closed', () => {
        mainWindow = null;
        if (inactivityTimer) clearTimeout(inactivityTimer);
        ipcMain.removeAllListeners('user-activity');
    });

    injectExternalScript(newWindow);

    //Timer för att återgå till huvudfönstret om användaren är inaktiv i xxx millisekunder
    const resetInactivityTimer = () => {
        if (inactivityTimer) clearTimeout(inactivityTimer);
        inactivityTimer = setTimeout(() => {
            createMainWindow()
        }, EXTERNAL_URL_TIMEOUT); 
    };

    ipcMain.on('user-activity', () => {
        resetInactivityTimer()
    });
    newWindow.on('focus', resetInactivityTimer);

    resetInactivityTimer();
}

/**
 * Injects a back button into the window.
 * @param {BrowserWindow} window - The window where the button will be injected.
 */
function injectExternalScript(window) {
    window.webContents.executeJavaScript(`
        if (!document.getElementById('back-button')) {
        const style = document.createElement('style');
        style.innerHTML = 'form { padding: 10px; }';
        document.head.appendChild(style);
        const backButton = document.createElement('button');
        backButton.id = 'back-button';
        backButton.innerHTML = '<i class="fas fa-home" style="color: #ffffff26; font-size: 70px; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);"></i><span style="font-size: 16px; font-weight: 700">Back to login</span>';
        backButton.style.position = 'relative';
        backButton.style.top = '10px';
        backButton.style.left = '10px';
        backButton.style.padding = '10px';
        backButton.style.width = '130px';
        backButton.style.height = '80px';
        backButton.style.backgroundColor = '#007bff';
        backButton.style.color = 'white';
        backButton.style.border = 'none';
        backButton.style.borderRadius = '5px';
        backButton.style.cursor = 'pointer';
        backButton.style.zIndex = '1001';

        const backgroundDiv = document.createElement('div');
        backgroundDiv.id = 'background-div';
        backgroundDiv.style.position = 'relative';
        backgroundDiv.style.top = '0';
        backgroundDiv.style.left = '0';
        backgroundDiv.style.width = '100%';
        backgroundDiv.style.height = '100px';
        backgroundDiv.style.backgroundColor = '#000061';
        backgroundDiv.style.zIndex = '1000';

        document.body.style.margin = '0'; // Ensure no margins interfere with the button
        document.body.style.padding = '0px';
        document.body.insertBefore(backgroundDiv, document.body.firstChild);
        backgroundDiv.appendChild(backButton);

        // Add click event to send an IPC message
        backButton.addEventListener('click', () => {
            window.electron.ipcRenderer.send('back-to-main');
        });

        // Detect mousemove, wheel, and keydown events
        document.addEventListener('mousemove', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        document.addEventListener('wheel', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        document.addEventListener('keydown', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        // Optionally detect clicks or any other interactions
        document.addEventListener('click', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        // Add Font Awesome link
        var link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css';
        document.head.appendChild(link);
    }
    `);
}

/**
 * Event handlers for IPC communication.
 */
function setupIPC() {
    ipcMain.on('submit-form', async (event, username, pin) => {
        mainWindow.webContents.send('spinner-start', ``);
        const verificationResult = await verifyCode(username, pin);
        switch (verificationResult) {
            case 'invalid-username':
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', '<div class="kth-alert warning"><h2>Invalid username. / Fel användarnamn.</h2> <p>Please try again. / Försök igen.</p>');
                break;
            case 'invalid':
                const message_en = LOGINTYPE === 'pin' ? 'Invalid Username/PIN' : 'Invalid Username/Password';
                const message_sv = LOGINTYPE === 'pin' ? 'Fel Username/PIN' : 'Fel Username/Password';
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', `<div class="kth-alert warning"><h2>Info</h2><p>${message_en}. Please try again.</p><p>${message_sv}. Försök igen.</p>`);
                break;
            case 'error':
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', '<div class="kth-alert warning"><h2>An error occurred. Please try again. / Ett fel uppstod. Försök igen.</h2><p>If the error persists contact the info desk. / Om felet kvarstår kontakta informationsdisken.</p>');
                break;
            default:
                
                // Avsluta(sätt sluttid) eventuell befintlig bokning på Dropin-datorer 
                if(BOOKING_TYPE==='dropin') {  
                    const status = await checkCurrentReservationStatus()
                    if (status.valid) {
                        const resetBooking = await resetReservation(status.reservation.id);
                    }
                }
                const reservationstatus = await checkCurrentReservationStatus()
                let reservation
                if (!reservationstatus.valid) {
                  // Om datorn är ledig
                  // Skapa en bokning för användaren med starttid som är nuvarande tids timme. 
                  // t ex om kl är 12:23 så ska start_time vara 12:00
                  // end_time ska vara start_time + x timmar
                  const start_time = new Date();
                  //start_time.setMinutes(0);
                  //start_time.setSeconds(0);
                  start_time.setMilliseconds(0);
                  const end_time = new Date(start_time);
                  end_time.setHours(start_time.getHours() + parseInt(DEFAULT_BOOKING_TIME, 10));
                  const startTimestamp = Math.floor(start_time.getTime() / 1000);
                  const endTimestamp = Math.floor(end_time.getTime() / 1000);
                  reservation = await createReservation(username, username, startTimestamp, endTimestamp);
                } else {
                  // Om datorn är upptagen
                  // Kolla bokning med det primary_id som alma returnerar för en giltig bokning
                  reservation = await checkReservation(verificationResult);
                }
               if (reservation.valid) {
                    mainWindow.webContents.send('spinner-remove', ``);
                    //Skickar data tillbaks till anropande shell-script
                    console.log(JSON.stringify({ booking_data: reservation.reservation }));
                    process.exit(0);
                } else {
                    mainWindow.webContents.send('spinner-remove', ``);
                    mainWindow.webContents.send('user-message', `<div class="kth-alert warning"> <h2>Login/booking failed</h2> <p>${reservation.message}</p></div>`);
                }
        }
    });

    ipcMain.on('load-username', (event, username) => {
        storedUsername = username;
        mainWindow.webContents.send('load-username', storedUsername);
    });

    ipcMain.on('load-external-url', (event, type) => {
        if(type === 'book-computer') {
            createNewWindow(BOOKING_SYSTEM_URL + '?room=' + RESOURCE_ID);
            return;
        }

        if(type === 'register-account') {
            createNewWindow(REGISTER_ACCOUNT_URL);
            return;
        }
       
    });

    ipcMain.on('back-to-main', () => {
        if (inactivityTimer) {
            clearTimeout(inactivityTimer);
            inactivityTimer = null;
            ipcMain.removeAllListeners('user-activity');
        }
        createMainWindow();
    });
}

/**
 * App lifecycle events.
 */
app.whenReady().then(() => {
    const argv = process.argv.slice(1);
    storedUsername = argv[1] || '';
    createMainWindow();
    setupIPC();
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});
EOL

cat <<'EOL' > /usr/local/bin/electron-login/preload.js
const { contextBridge, ipcRenderer } = require('electron');
const fs = require('fs');
const path = require('path');

contextBridge.exposeInMainWorld('electron', {
    ipcRenderer: {
        send: (channel, data) => ipcRenderer.send(channel, data),
        on: (channel, func) => ipcRenderer.on(channel, (event, ...args) => func(...args))
    }
});
EOL

cat <<'EOL' > /usr/local/bin/electron-login/index.html
<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Check-In</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link
    href="https://fonts.googleapis.com/css2?family=Figtree:ital,wght@0,300;0,400;0,500;0,600;0,700;0,800;0,900;1,300;1,400;1,500;1,600;1,700;1,800;1,900&display=swap"
    rel="stylesheet">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css" rel="stylesheet">
  <style>
    html {
      font-size: 18px;
    }

    @media (max-width: 1279px) {
      html {
        font-size: 14px;
      }
    }

    @media (max-width: 900px) {
      html {
        font-size: 10px;
      }
    }

    body,
    html {
      font-family: "Figtree", Arial, "Helvetica Neue", helvetica, sans-serif;
      font-weight: 300;
      color: #ffffff;
      height: 100%;
      width: 100%;
      margin: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
      background-image: url('../screen_bg_gc_empty.png');
      background-color: #004791;
      background-size: cover;
      background-position: center;
      background-repeat: no-repeat;
    }

    .form {
      background: rgba(255, 255, 255, 0);
      padding: 20px;
      border-radius: 10px;
      text-align: center;
      margin-top: 0px;
    }

    .logintext {
      color: #ffffff;
      font-size: 20px;
      font-weight: 500;
      margin-bottom: 20px;
    }

    .form-container {
      display: block;
      text-align: center;
      background: rgba(255, 255, 255, 0.1);
      padding: 20px;
      border-radius: 8px;
      margin-top: 0px;
      width: 300px;
    }

    .message-container,
    #spinner {
      display: none;
      justify-content: center;
      align-items: center;
      flex-direction: column;
      background: rgba(255, 255, 255, 0.6);
      padding: 20px;
      border-radius: 8px;
      margin-top: 0px;
      color: white;
      position: absolute;
      height: 100%;
      width: 100%;
      margin: 0;
      padding: 0;
    }

    .user-message {
      color: #Ffffff;
      margin-bottom: 10px;
    }

    input {
      display: block;
      margin: 10px auto;
      padding: 10px;
      width: 400px;
      border-radius: 10px;
      font-size: 22px;
    }

    button {
      padding: 10px 20px;
      background-color: #1e9044;
      color: white;
      border: none;
      border-radius: 5px;
      cursor: pointer;
    }

    button:hover {
      background-color: #45a049;
    }

    #open-book-computer {
      display: none;
      background-color: #78001A;
    }

    #open-register {
      display: none;
      background-color: #A65900;
    }

    #open-book-computer,
    #open-register {
      position: relative;
      padding: 10px;
      width: 130px;
      height: 80px;
      font-size: 0.7em;
      margin: 10px;
    }

    .open-url:hover {
      background-color: #af3e77;
    }

    .nav {
      display: flex;
      align-items: flex-start;
      width: 100%;
    }

    .computerinfo {
      font-size: 4.5em;
      font-weight: 700;
    }

    .computerinfo.sv {
      color: #ffffff;
      margin-bottom: 20px;
    }

    .computerinfo.en {
      color: #6298D2;
      margin-bottom: 40px;
    }

    #computername-container {
      justify-content: center;
      display: flex;
      width: 100%;
      flex-direction: column;
    }

    #computername {
      font-size: 8em;
      font-weight: 700;
    }

    /* Styling the container */
    .login-container {
      display: flex;
      flex-direction: column;
      align-items: center;
      width: 300px;
      /* Adjust width */
      margin: 50px auto;
      /* Center the form on the page */
      font-family: Arial, sans-serif;
    }

    /* Styling the username field */
    #username {
      width: 100%;
      padding: 10px;
      margin-bottom: 20px;
      border: 1px solid #ccc;
      border-radius: 5px;
      font-size: 16px;
      box-sizing: border-box;
    }

    /* Styling the password field wrapper */
    .password-field {
      position: relative;
      width: 100%;
    }

    /* Styling the password input */
    .password-field input {
      width: 100%;
      padding: 10px;
      border: 1px solid #ccc;
      border-radius: 5px;
      font-size: 16px;
      padding-right: 45px;
      /* Space for button */
      box-sizing: border-box;
      margin: 0;
    }

    /* Styling the login button */
    .password-field button {
      position: absolute;
      right: 0px;
      top: 0px;
      height: 100%;
      width: 35px;
      border: none;
      background-color: #ccc;
      color: black;
      font-size: 18px;
      border-radius: 3px;
      cursor: pointer;
      display: flex;
      justify-content: center;
      align-items: center;
    }

    /* Adjusting button hover effect */
    .password-field button:hover {
      background-color: #bbb;
    }

    #currentreservationinfo {
      font-size: 4em;
      font-weight: 600;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100px;
      color: white;
    }

    .available {
      background-color: #4DA060;
    }

    .booked {
      background-color: #E86A58;
    }

    /* https://cssloaders.github.io */
    .loader {
      width: 48px;
      height: 48px;
      border: 5px solid #FFF;
      border-bottom-color: transparent;
      border-radius: 50%;
      display: inline-block;
      box-sizing: border-box;
      animation: rotation 1s linear infinite;
    }

    @keyframes rotation {
      0% {
        transform: rotate(0deg);
      }

      100% {
        transform: rotate(360deg);
      }
    }

    /* KTH STYLE*/
    .kth-alert.warning {
      border-color: #c7321d;
    }

    .kth-alert.info {
      border-color: #004791;
    }

    .kth-alert {
      color: #000000;
      background-color: #ffffff;
      display: grid;
      gap: .25rem .5rem;
      grid-template-columns: auto 1fr;
      padding-inline: .625rem;
      padding-block: .5rem 1rem;
      border-block-start-width: .375rem;
      border-inline-width: .125rem;
      border-block-end-width: .125rem;
      border-style: solid;
      border-color: var(--color-text);
    }

    .kth-alert.warning:before {
      --icon: url(data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2220%22%20height%3D%2220%22%20fill%3D%22none%22%3E%3Cpath%20fill%3D%22%23212121%22%20d%3D%22M2.386%2017.085a.848.848%200%200%201-.764-.435.735.735%200%200%201-.109-.43c.007-.16.05-.311.13-.455L9.255%203.062a.708.708%200%200%201%20.324-.313.982.982%200%200%201%20.843%200%20.709.709%200%200%201%20.324.313l7.611%2012.703c.08.144.123.296.13.455a.735.735%200%200%201-.109.43.98.98%200%200%201-.31.313.83.83%200%200%201-.454.122H2.386ZM3.77%2015.43h12.46L10%205.056%203.77%2015.43Zm6.226-.945a.758.758%200%200%200%20.55-.224.736.736%200%200%200%20.229-.546.75.75%200%200%200-.224-.549.74.74%200%200%200-.547-.226.762.762%200%200%200-.55.222.728.728%200%200%200-.229.544c0%20.214.075.398.224.55.15.153.332.23.547.23Zm0-2.485c.21%200%20.39-.072.535-.216a.72.72%200%200%200%20.219-.534V8.805a.728.728%200%200%200-.214-.535.72.72%200%200%200-.532-.215.734.734%200%200%200-.535.215.72.72%200%200%200-.219.535v2.445c0%20.213.071.39.214.534a.72.72%200%200%200%20.532.216Z%22%2F%3E%3C%2Fsvg%3E);
      content: "";
      display: inline-block;
      width: 1.25rem;
      min-width: 1.25rem;
      height: 1.25rem;
      mask-image: var(--icon);
      mask-size: cover;
      background-color: currentColor;
    }

    .kth-alert.info:before {
      --icon: url(data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2220%22%20height%3D%2220%22%20fill%3D%22none%22%3E%3Cpath%20fill%3D%22%23212121%22%20d%3D%22M11%207c-1%200-3.5%202-4%202.5l.5.5c.5-.5%201-1%202-1s-1%204-1%207.5c0%201.5%201%201.5%202%201s2.5-1.5%203-2L13%2015c-1%20.5-1.5%201.5-2%201s1-7%201-8%200-1-1-1ZM12.5%204a1.5%201.5%200%201%201-3%200%201.5%201.5%200%200%201%203%200Z%22%2F%3E%3C%2Fsvg%3E);
      content: "";
      display: inline-block;
      width: 1.25rem;
      min-width: 1.25rem;
      height: 1.25rem;
      mask-image: var(--icon);
      mask-size: cover;
      background-color: currentColor;
    }

    .kth-alert>:is(h2, h3, h4) {
      font-weight: 400;
      font-size: 1rem;
      line-height: 1.5rem;
      font-weight: 600;
      margin: 0;
    }

    .kth-alert p:last-child {
      margin-block-end: 0;
    }

    .kth-alert p {
      margin-block: .5rem;
    }

    .kth-alert>* {
      grid-column-start: 2;
    }

    .kth-button.success,
    .kth-button.next {
      background: #3d784a;
      color: #fcfcfc;
    }

    .kth-button {
      display: inline-flex;
      padding: .5rem 1rem;
      justify-content: center;
      align-items: center;
      border: unset;
      border-radius: 1.25rem;
      background: none;
      font-weight: 700;
      font-size: 1rem;
      line-height: 1.5rem;
      text-decoration: none;
    }
  </style>
</head>

<body>
  <div class="nav">
    <button id="open-book-computer" class="open-url">
      <i class="fas fa-desktop"
        style="color:#ffffff26;font-size: 70px; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);"></i><span
        style="font-weight: 700">Boka dator / Book computer</span>
    </button>
    <button id="open-register" class="open-url">
      <i class="fas fa-user-pen"
        style="color:#ffffff26;font-size: 70px; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);"></i><span
        style="font-weight: 700">Registrera bibliotekskonto / Register library account</span>
    </button>
  </div>
  <div id="form-container" class="form">
    <div class="computerinfo sv">Gästdator för dig som besöker KTH</div>
    <div class="computerinfo en">Guest computer for visitors to KTH</div>
    <div id="computername-container">
      <div id="computername"></div>
      <div id="currentreservationinfo"></div>
    </div>
    <div class="login-container">
      <input id="username" type="text" placeholder="användarnamn / username">
      <div class="password-field">
        <input id="pin" type="password" placeholder="">
        <button id="submit-button" aria-label="Login"><i class="fa fa-arrow-right"></i></button>
      </div>
    </div>
  </div>
  <div id="spinner"><span class="loader"></span></div>
  <div class="message-container" id="message-container">
    <div class="user-message" id="user-message"></div>
    <button class="kth-button success" id="ok-button">OK</button>
  </div>

  <script>
    const { ipcRenderer } = require('electron');
    const formContainer = document.getElementById('form-container');
    const messageContainer = document.getElementById('message-container');
    const userMessageElement = document.getElementById('user-message');
    const spinner = document.getElementById('spinner');
    const computernameContainer = document.getElementById('computername-container');

    document.addEventListener('DOMContentLoaded', () => {
      //Check current status
      ipcRenderer.on('current-status', (event, status) => {
        if (status.valid) {
          computernameContainer.classList.add('booked');
          computernameContainer.classList.remove('available');
          document.getElementById('currentreservationinfo').innerHTML = `Bokad / Booked`;
        } else {
          computernameContainer.classList.add('available');
          computernameContainer.classList.remove('booked');
          document.getElementById('currentreservationinfo').innerHTML = `Ledig / Available`;
        }
      });

      const params = new URLSearchParams(window.location.search);
      const computername = params.get('computername') || 'Datornamn saknas';
      const bookingType = params.get('bookingType') || 'bookable'

      document.querySelector('#computername').innerHTML = `${computername}`;

      ipcRenderer.on('load-username', (event, username) => {
        document.getElementById('username').value = username;
      });

      ipcRenderer.on('user-message', (event, message) => {
        //formContainer.style.display = 'none';
        userMessageElement.innerHTML = message;
        messageContainer.style.display = 'flex';
      });

      ipcRenderer.on('spinner-start', (event, message) => {
        spinner.style.display = 'flex';
      });

      ipcRenderer.on('spinner-remove', (event, message) => {
        spinner.style.display = 'none';
      });

      document.getElementById('ok-button').addEventListener('click', () => {
        messageContainer.style.display = 'none';
        //formContainer.style.display = 'block';
      });

      document.getElementById('submit-button').addEventListener('click', () => {
        const username = document.getElementById('username').value;
        const pin = document.getElementById('pin').value;
        ipcRenderer.send('submit-form', username, pin);
      });

      document.getElementById('pin').addEventListener('keypress', (event) => {
        if (event.key === 'Enter') {
          document.getElementById('submit-button').click();
        }
      });

      if (bookingType == 'dropin') {
        document.getElementById('open-book-computer').remove();
      } else {
        document.getElementById('open-book-computer').addEventListener('click', () => {
          ipcRenderer.send('load-external-url', 'book-computer');
        });
      }

      document.getElementById('open-register').addEventListener('click', () => {
        ipcRenderer.send('load-external-url', 'register-account');
      });
    });
  </script>
</body>

</html>
EOL

# Installera npm och nodejs
apt install -y nodejs
NEEDRESTART_MODE=a apt install -y npm
npm install -g n
n stable
npm install -g npm@latest
hash -r
# Installera Electron och beroenden
cd /usr/local/bin/electron-login
npm install electron
npm install axios
npm install dotenv

# Skapa icons-folder
mkdir -p /usr/local/bin/icons
# Ladda ner bakgrunder etc (Electron/feh)
curl -o "/usr/local/bin/KTH_logo_RGB_vit_small.png" https://raw.githubusercontent.com/kth-biblioteket/publicom/main/backgrounds/KTH_logo_RGB_vit_small.png
curl -o "/usr/local/bin/screen_bg_gc.png" https://raw.githubusercontent.com/kth-biblioteket/publicom/main/backgrounds/screen_bg_gc.png
curl -o "/usr/local/bin/screen_bg_gc_empty.png" https://raw.githubusercontent.com/kth-biblioteket/publicom/main/backgrounds/screen_bg_gc_empty.png
curl -o "/usr/local/bin/screen_bg_kth_logo_navy.png" https://raw.githubusercontent.com/kth-biblioteket/publicom/main/backgrounds/screen_bg_kth_logo_navy.png
curl -o "/usr/local/bin/icons/icons8-green-circle-32.png" https://raw.githubusercontent.com/kth-biblioteket/publicom/main/icons/icons8-green-circle-32.png
curl -o "/usr/local/bin/icons/icons8-red-circle-32.png" https://raw.githubusercontent.com/kth-biblioteket/publicom/main/icons/icons8-red-circle-32.png


# Hantera ctrl + alt + f1-f6 för att hindra användares åtkomst till konsol.
cat <<EOL > /usr/share/X11/xorg.conf.d/50-novtswitch.conf
Section "ServerFlags"
    Option "DontVTSwitch" "true"
EndSection
EOL

# bakgrund X-session
apt install -y feh

# Installera jq för att hanterna json(bokningsdata och policyfil)
apt install -y jq

# Rätt behörigheter för guest-kontots config
chmod -R 755 /home/guest/.config
chown -R guest:guest /home/guest/.config

# Installera och avinstallera ubuntu-desktop för att få in diverse komponenenter som behövs för att genererar rätt grafik, fonter etc i t ex pdf viewer i chrome.
# Att göra: ta reda på vilka för att slippa installera hela ubuntu-desktop
apt install -y ubuntu-desktop
apt remove --purge -y ubuntu-desktop
apt autoremove --purge -y
systemctl stop gdm3
systemctl disable gdm3

## Avinstallera cloud-init
apt purge cloud-init -y
rm -rf /etc/cloud && rm -rf /var/lib/cloud/

####
### Installera eventuellt x11vnc för gui accesss remote
####

#Disable access till terminal
#usermod -s /usr/sbin/nologin guest

## Installera/konfigurera VNC Viewer
# Check if the VNC_PASSWORD variable is set
if [ -z "$VNC_PASSWORD" ]; then
    echo "Error: VNC_PASSWORD is not set in $ENV_FILE"
    exit 1
fi

echo "Starting x11vnc and systemd setup..."

# 1. Install x11vnc if not already installed
echo "Installing x11vnc..."
apt update
apt install -y x11vnc

# 2. Set up a VNC password
echo "Setting up VNC password..."
mkdir -p /home/kthb/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" /home/kthb/.vnc/passwd

cp /home/guest/.Xauthority /home/kthb/.Xauthority
chown kthb:kthb /home/kthb/.Xauthority

# 3. Create a systemd service for x11vnc

echo "Creating systemd service file..."

cat <<'EOL' > /etc/systemd/system/x11vnc.service
[Unit]
Description=Start x11vnc at startup
After=display-manager.service

[Service]
ExecStart=/usr/bin/x11vnc -display :0 -auth /home/guest/.Xauthority -forever -loop -noxdamage -repeat -rfbauth /home/kthb/.vnc/passwd -rfbport 5900 -shared
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# 4. Reload systemd, enable and start the x11vnc service
echo "Enabling and starting the x11vnc service..."
systemctl daemon-reload
systemctl enable x11vnc
systemctl start x11vnc

echo "x11vnc setup is complete. The service is now running."

## Stäng av USB-access Ubuntu
BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"

if ! grep -q "^blacklist usb-storage" "$BLACKLIST_FILE"; then
    echo "blacklist usb-storage" | tee -a "$BLACKLIST_FILE"
fi

if ! grep -q "^blacklist uas" "$BLACKLIST_FILE"; then
    echo "blacklist uas" | tee -a "$BLACKLIST_FILE"
fi

update-initramfs -u

cat <<'EOL' > /etc/modprobe.d/disable-usb-storage.conf
install usb-storage /bin/false
install uas /bin/false
EOL

update-initramfs -u

# Restrict Ctrl+Alt+Backspace: Disable the ability to kill X with a key combination in
# /etc/X11/xorg.conf.d/10-kiosk.conf

reboot
