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

# Säker inläsning av config/secrets. Spegel av files/usr/local/bin/config_lib.sh: install.sh
# körs som bootstrap (i produktion laddas den ensam via curl) och kan inte source:a config_lib.sh
# innan filträdet hämtats, därför bäddas funktionen in här. Håll de två kopiorna i synk
# (tools/check.sh kontrollerar det). Till skillnad från "source" KÖRS ingenting i filen.
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

# Läs in miljövariabler
ENV_FILE="/usr/local/bin/config/.config"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE file not found!"
    exit 1
fi

# Gör miljövariabler tillgängliga i script
load_config "$ENV_FILE"

# Läs in hemligheter
SECRET_FILE="/usr/local/bin/secrets/.secrets"

if [ ! -f "$SECRET_FILE" ]; then
    echo "Fel: $SECRET_FILE hittades inte"
    exit 1
else
    # Gör variabler tillgängliga i script
    load_config "$SECRET_FILE"
    echo "Hittade $SECRET_FILE"
fi

if [ -z "$VNC_PASSWORD" ]; then
    echo "Error: VNC_PASSWORD is not set in $SECRET_FILE"
    exit 1
fi

BRANCH="${PUBLICOM_BRANCH:-stable}"

# Uppdatera paketlistan för ubuntu
apt update

# Datornamnet måste finnas i /etc/hosts. Annars slås det upp till nätverksadresserna,
# och xauth i startx gör omvända DNS-uppslag som tar ca 5 s vid varje sessionsstart.
grep -q "^127.0.1.1" /etc/hosts || echo "127.0.1.1 $(hostname)" >> /etc/hosts

# GRUB: dold meny och tyst start. Fungerar på både 20.04 och 24.04.
# Ubuntus vanliga menyposter (10_linux) behålls så att kärnuppdateringar följs automatiskt.
cat > /etc/default/grub.d/99-publicom.cfg <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISABLE_RECOVERY=true
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
EOF
# Lösenordsskydd: datorn startar utan lösenord, men att ändra menyposter eller använda
# GRUB:s kommandorad kräver lösenordet. Hash skapas med grub-mkpasswd-pbkdf2.
if [ -n "$GRUB_PASSWORD_HASH" ]; then
    cat > /etc/grub.d/01_publicom_password <<EOF
#!/bin/sh
cat <<'GRUBEOF'
set superusers="kthb"
password_pbkdf2 kthb $GRUB_PASSWORD_HASH
GRUBEOF
EOF
    chmod 700 /etc/grub.d/01_publicom_password
    sed -i 's/^CLASS="--class gnu-linux --class gnu --class os"$/CLASS="--class gnu-linux --class gnu --class os --unrestricted"/' /etc/grub.d/10_linux
else
    echo "Varning: GRUB_PASSWORD_HASH saknas i $SECRET_FILE, GRUB-menyn lösenordsskyddas inte"
fi
# Underhållsläge (fysisk inloggningsprompt) utlöses genom att lägga till kärnparametern
# publicom.maintenance vid start: håll Esc vid uppstart, tryck e på menyposten (kräver
# GRUB-lösenordet), lägg till " publicom.maintenance" sist på linux-raden och tryck Ctrl-X.
# Då hoppas gästkiosken över (guest.service) och publicom-maintenance-login.service ger en
# textinloggning på tty1. Se README. (Ingen egen menypost, så det följer kärnuppdateringar.)
update-grub

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
# Försättsblad (job-sheets). Standard none,none = inga blad före/efter jobbet.
# Styrs av PRINT_JOB_SHEETS i config; sätt t ex "standard," för ett blad före varje jobb.
lpadmin -p KTH-Print -o job-sheets-default="${PRINT_JOB_SHEETS:-none,none}"

# CUPS-härdning: stäng av webbgränssnittet (nås annars via localhost:631 i Chromium)
# och spara inte jobbhistorik eller utskrivna filer, så att en gäst inte kan se eller
# skriva ut tidigare gästers dokument (alla gäster delar användaren guest).
cupsctl WebInterface=No PreserveJobHistory=No PreserveJobFiles=No
systemctl try-restart cups 2>/dev/null

# Installera GUI/Fönsterhanterare/chromium etc.
apt install -y --no-install-recommends xorg matchbox-window-manager chromium-browser xserver-xorg-legacy xinit tint2 xprintidle xbindkeys openbox zenity xscreensaver xscreensaver-gl-extra unclutter x11-utils

# xautolock för att kunna starta om sessioner efter inaktivitet, feh för bakgrund,
# jq för json (bokningsdata och policyfil), x11vnc för fjärråtkomst
apt install -y xautolock feh jq x11vnc
# xterm för administratörens terminal (Ctrl+Shift+T, /usr/local/bin/open_terminal.sh)
apt install -y --no-install-recommends xterm

# Fördröjning på 4 s efter fel lösenord för su (terminalgenvägen). Ingen kontolåsning,
# eftersom kthb då kan låsas ute helt. Påverkar inte SSH.
grep -q "pam_faildelay" /etc/pam.d/su || sed -i '0,/^auth/s//auth       optional   pam_faildelay.so delay=4000000\nauth/' /etc/pam.d/su

# pam_lastlog.so togs bort i Ubuntu 24.04, men /etc/pam.d/login refererar den fortfarande.
# guest.service (PAMName=login) och underhållsinloggningen ger då "cannot open shared object
# file: pam_lastlog.so" vid varje session. Kommentera bort raden (funktionen är oviktig här).
if grep -qE '^[[:space:]]*session[[:space:]].*pam_lastlog\.so' /etc/pam.d/login; then
    sed -i -E 's/^([[:space:]]*session[[:space:]].*pam_lastlog\.so.*)$/# \1  # publicom: modulen finns inte i Ubuntu 24.04+/' /etc/pam.d/login
fi

# Automatiska säkerhetsuppdateringar (konfigureras av deploy.sh: 10periodic, 52publicom-unattended-upgrades)
apt install -y unattended-upgrades
# Snap-paket (Chromium) uppdateras bara nattetid
snap set system refresh.timer=02:00-04:00

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

# Fonter och det enda systembibliotek utöver grundpaketen som Chromium och Electron behöver.
# Tidigare installerades och togs hela ubuntu-desktop bort för det här (långsamt, drog in program
# som gnome-terminal). En ren 24.04 testades med bara detta: full gästsession (Electron och webb)
# fungerar, och fonter/PDF renderas.
# Liberation = metrik-kompatibla ersättare för Arial/Times/Courier (viktigt för PDF), DejaVu och
# Noto täcker resten inklusive andra skriftspråk och emoji.
apt install -y --no-install-recommends \
    fonts-liberation fonts-dejavu-core fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji
# ALSA-biblioteket som Electron-binären länkar mot (det enda som saknades på en ren installation).
# Heter libasound2t64 från och med 24.04 (t64-övergången), libasound2 på 20.04.
apt install -y libasound2t64 || apt install -y libasound2

# Stäng av tjänster som inte behövs på en publik dator
systemctl disable --now avahi-daemon bluetooth 2>/dev/null

# Låt bara root och kthb använda cron/at, så att en gäst inte kan lägga in jobb
# som överlever sessionen
printf 'root\nkthb\n' > /etc/cron.allow
chmod 600 /etc/cron.allow
command -v at > /dev/null && { printf 'root\nkthb\n' > /etc/at.allow; chmod 600 /etc/at.allow; }
# Chromium (snap) skriver bara ut via cups-snappen, som vidarebefordrar till cups från apt
# (KTH-Print). Utan den visar Chromium bara "Spara som PDF". Installera och koppla den.
snap install cups
snap connect chromium:cups cups:cups

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

if [ ! -f /usr/local/bin/electron-login/node_modules/electron/path.txt ]; then
    echo "Error: Electron installerades inte, se utskriften ovan" 1>&2
    exit 1
fi

mkdir -p /usr/local/bin/screensaver

# Hämta config, Chromium-policy och skärmsläckarbilder
/usr/local/bin/init.sh

# Vid installation från lokal kopia kan filerna saknas på GitHub (t ex en branch som inte är pushad).
# Ta dem då från den lokala kopian.
if [ -n "$PUBLICOM_SRC" ]; then
    load_config "$ENV_FILE"
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
systemctl enable init.service allowlist_from_ezproxy.service guest.service x11vnc.service publicom-maintenance-login.service heartbeat.timer
systemctl start x11vnc

## Brandvägg: allt inkommande nekas utom SSH från SSH_ALLOW_FROM (kommaseparerat, från config).
## VNC lyssnar bara lokalt (x11vnc -localhost) och nås via SSH-tunnel, så port 5900 öppnas inte.
## Obs: körs install.sh via SSH från en adress som inte är tillåten bryts anslutningen.
ufw default deny incoming
ufw default allow outgoing
IFS=',' read -ra SSH_SOURCES <<< "${SSH_ALLOW_FROM:-130.237.0.0/16}"
for src in "${SSH_SOURCES[@]}"; do
    ufw allow from "$src" to any port 22 proto tcp comment "SSH publicom"
done
# Regler från den tidigare manuella instruktionen
ufw delete allow from 130.237.0.0/16 to any port 5900 2>/dev/null
ufw delete deny 5900 2>/dev/null
ufw delete deny 22 2>/dev/null
ufw --force enable

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
