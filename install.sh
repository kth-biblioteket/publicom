#!/bin/bash
################################################
####                                        ####
####    Installationsfil Publicom           ####
####    Ver 3.0                             ####
################################################
# Installerar paket och gör engångsinställningar.
# Alla skript och konfigurationsfiler installeras av deploy.sh enligt files.manifest,
# och uppdateras sedan automatiskt vid varje uppstart (init.sh -> deploy.sh).

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

if [ -z "$VNC_PASSWORD" ]; then
    echo "Error: VNC_PASSWORD is not set in $SECRET_FILE"
    exit 1
fi

BRANCH="${PUBLICOM_BRANCH:-stable}"

# Uppdatera paketlistan för ubuntu
apt update

# Sätt datum/tid
timedatectl set-timezone Europe/Stockholm

# Sätt brittisk engelska
locale-gen en_GB.UTF-8
update-locale LANG=en_GB.UTF-8

# Lägg till en gästanvändare utan lösenord för autologin och anslut till grupper
id guest > /dev/null 2>&1 || adduser guest --disabled-password --gecos ""
# Gästen ska inte vara med i några extra grupper (t ex lpadmin skulle ge rätt att administrera skrivare).
# Tidigare rad "usermod -aG lpadmin video tty input guest" hade fel syntax och gjorde ingenting.

# Installera skrivarfunktion
# Lägg till KTH-Print-skrivare och drivrutin
apt install -y cups printer-driver-gutenprint
## Skapa med generisk drivrutin
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
apt install -y --no-install-recommends xorg matchbox-window-manager chromium-browser xserver-xorg-legacy xinit tint2 xprintidle xbindkeys openbox zenity xscreensaver xscreensaver-gl-extra unclutter

# xautolock för att kunna starta om sessioner efter inaktivitet, feh för bakgrund,
# jq för json (bokningsdata och policyfil), x11vnc för fjärråtkomst
apt install -y xautolock feh jq x11vnc

# Inaktivera automatiska uppdateringsmeddelanden
apt remove -y update-notifier update-notifier-common

# Ser till att konsol inte visas
systemctl disable getty@tty1

# Installera npm och nodejs
apt install -y nodejs
NEEDRESTART_MODE=a apt install -y npm
npm install -g n
n stable
npm install -g npm@latest
hash -r

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

# Tidigare separat tjänst som ersatts av ExecStopPost i guest.service
systemctl disable session-cleanup.service 2>/dev/null
rm -f /etc/systemd/system/session-cleanup.service

# Installera alla skript och konfigurationsfiler (files.manifest).
# Normalt hämtas branchen från GitHub. För test kan en lokal kopia av repot anges:
#   sudo PUBLICOM_SRC=/tmp/publicom ./install.sh
WORK=$(mktemp -d)
if [ -n "$PUBLICOM_SRC" ]; then
    echo "Installerar från lokal kopia $PUBLICOM_SRC"
    SRC="$PUBLICOM_SRC"
else
    echo "Hämtar publicom ($BRANCH)"
    if ! curl -fsSL --max-time 120 -o "$WORK/src.tar.gz" "https://github.com/kth-biblioteket/publicom/archive/refs/heads/$BRANCH.tar.gz" \
        || ! tar -xzf "$WORK/src.tar.gz" -C "$WORK"; then
        echo "Error: kunde inte hämta branch $BRANCH" 1>&2
        exit 1
    fi
    SRC=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -n1)
fi
if [ ! -f "$SRC/files.manifest" ]; then
    echo "Error: $SRC/files.manifest saknas" 1>&2
    exit 1
fi
bash "$SRC/files/usr/local/bin/deploy.sh" "$SRC"

if [ ! -x /usr/local/bin/electron-login/node_modules/.bin/electron ]; then
    echo "Error: Electron installerades inte, se utskriften ovan" 1>&2
    exit 1
fi

mkdir -p /usr/local/bin/screensaver

# Hämta config, Chromium-policy och skärmsläckarbilder
/usr/local/bin/init.sh

# Vid installation från lokal kopia kan filerna saknas på GitHub (t ex en branch som inte är pushad).
# Ta dem då från den lokala kopian.
if [ -n "$PUBLICOM_SRC" ]; then
    source "$ENV_FILE"
    POLICY_PATH="/var/snap/chromium/current/policies/managed/policies.json"
    mkdir -p "$(dirname "$POLICY_PATH")"
    install -o root -g root -m 0644 "$SRC/$POLICY_FILE" "$POLICY_PATH"
    IFS=',' read -ra FILE_ARRAY <<< "$SCREENSAVER_FILES"
    for file in "${FILE_ARRAY[@]}"; do
        [ -n "$file" ] && install -m 0644 "$SRC/screensaver/$file" "/usr/local/bin/screensaver/$file"
    done
fi
rm -rf "$WORK"

# Bygg allowlist i Chromium-policyn
/usr/local/bin/allowlist_from_ezproxy.sh

# Rätt behörigheter för guest-kontots config
chown -R guest:guest /home/guest/.config

## Installera/konfigurera VNC Viewer
echo "Setting up VNC password..."
mkdir -p /home/kthb/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" /home/kthb/.vnc/passwd

cp /home/guest/.Xauthority /home/kthb/.Xauthority 2>/dev/null
chown kthb:kthb /home/kthb/.Xauthority 2>/dev/null

systemctl daemon-reload
systemctl enable init.service allowlist_from_ezproxy.service guest.service x11vnc.service
systemctl start x11vnc

## Stäng av USB-access Ubuntu
BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"

if ! grep -q "^blacklist usb-storage" "$BLACKLIST_FILE"; then
    echo "blacklist usb-storage" | tee -a "$BLACKLIST_FILE"
fi

if ! grep -q "^blacklist uas" "$BLACKLIST_FILE"; then
    echo "blacklist uas" | tee -a "$BLACKLIST_FILE"
fi

# disable-usb-storage.conf installeras av deploy.sh
update-initramfs -u

reboot
