# PubLiCom
## KTH Bibliotekets Publika Datorer, Public Computers KTH Library
Datorer i bibliotekets publika miljöer

- Kioskdatorer
- Sökdatorer
- Gästdatorer

### Installation
- Installera en Ubuntu Server (20.04) på en dator.
- Välj att installera SSH
- Uppgradera vid behov
    - apt upgrade -y
    - do-release-upgrade(uppgraderar till nästa version)
- BIOS Tillåt endast boot från HD
- BIOS Lösenordsskydda
- BIOS quiet etc
```bash
sudo nano /etc/default/grub
```
För Ubuntu 22.04 
GRUB_CMDLINE_LINUX_DEFAULT="quiet systemd.unified_cgroup_hierarchy=0"
```
GRUB_DEFAULT="Ubuntu"
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_HIDDEN_TIMEOUT=0
GRUB_DISABLE_RECOVERY=true
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="quiet"
```
```bash
sudo update-grub
```

Skapa en hemlighetsfil
```bash
sudo mkdir /usr/local/bin/secrets
sudo nano /usr/local/bin/secrets/.secrets
```
```
GITHUB_TOKEN=xxxxxxx
VNC_PASSWORD=xxxxxxx
BOOKING_API_KEY=xxxxxxx
```
Github token user "kthbiblioteket" https://github.com/settings/personal-access-tokens

Expires on Mon, Nov 24 2025 – **har gått ut och måste förnyas** på varje dator (behövs för öppna gästdatorer, `ALMA_LOGIN=false`).
Tokenen används bara för att läsa `kth-biblioteket/ezproxy/db_stanzas.txt`. Skapa den med minsta möjliga behörighet (fine-grained, endast *Contents: Read* på det repot).
Om hämtningen misslyckas används senast hämtade kopia i `/var/cache/publicom/db_stanzas.txt`, och ett fel syns i `journalctl -u allowlist_from_ezproxy`.

```bash
sudo chown root:root /usr/local/bin/secrets/.secrets
sudo chmod 600 /usr/local/bin/secrets/.secrets
sudo chmod 700 /usr/local/bin/secrets
```

Skapa en .config-fil kopiera från rätt fil i detta repo
```bash
sudo mkdir /usr/local/bin/config
sudo curl -o "/usr/local/bin/config/.config" https://raw.githubusercontent.com/kth-biblioteket/publicom/stable/.config_xxx
```

Aktivera/konfiguera firewall UFW
```bash
# Endast tillgång från KTH-nätverket
sudo ufw --force enable
sudo ufw allow from 130.237.0.0/16 to any port 22 comment "Allow SSH from internal KTH network"
sudo ufw allow from 130.237.0.0/16 to any port 5900 comment "Allow VNC from internal KTH network"
sudo ufw deny 22
sudo ufw deny 5900
```

Eventuellt wifi:
```bash
sudo nmcli dev wifi connect "KTH-IoT" password "xXXXxXxX"
```

Kontrollera access till SSH från KTH-nätverket

Skapa lösen till terminal
```bash
echo -n "xXxXXxxX" | sha256sum
sudo nano /usr/local/bin/open_terminal.sh

#!/bin/bash
# Fråga efter lösenord med Zenity
pass=$(zenity --password --title="Admin-åtkomst" --text="Ange lösenord för terminal:" 2>/dev/null)

# Om användaren klickar avbryt, gör ingenting
[ -z "$pass" ] && exit 0

# Räkna ut hashen på det som skrevs in
input_hash=$(echo -n "$pass" | sha256sum | awk '{print $1}')

# Klistra in din kopierade hash här nedanför
target_hash="xxxxxxx"

if [ "$input_hash" == "$target_hash" ]; then
    xterm &
else
    zenity --error --text="Felaktigt lösenord!" --timeout=3 2>/dev/null
fi


sudo chmod +x /usr/local/bin/open_terminal.sh
```

Kopiera install.sh från github, gör den exekverbar och starta den
```bash
sudo curl -L -o ./install.sh https://raw.githubusercontent.com/kth-biblioteket/publicom/stable/install.sh
sudo chmod +x install.sh
sudo ./install.sh
```

#### Config Exempel
Configfilerna `.config_xxx` genereras från `config/`, se [Config](#config) nedan. Exemplet visar vilka variabler som finns.
```
REMOTE_CONFIG_URL="https://raw.githubusercontent.com/kth-biblioteket/publicom/stable/.config_xxxx"
RESOURCE_ID=x
LOGINTYPE=password
API_URL=https://apps.lib.kth.se/almatools/almalogin
RESERVATION_API_UPDATE_URL=https://api.lib.kth.se/bookingsystem/v1/entry/updateendtime/guestcomputers/
RESERVATION_API_CREATE_URL=https://api.lib.kth.se/bookingsystem/v1/entry/create/guestcomputers/
RESERVATION_API_URL=https://api.lib.kth.se/bookingsystem/v1/entry/validate/guestcomputers/
RESERVATION_API_CURRENT_RES_URL=https://api.lib.kth.se/bookingsystem/v1/entry/check/guestcomputers/
BOOKING_SYSTEM_URL=https://apps.lib.kth.se/guestcomputers
BOOKING_TYPE=dropin
DEFAULT_BOOKING_TIME=2
REGISTER_ACCOUNT_URL=https://apps.lib.kth.se/formtools/api/v1/kthbform?formid=libraryaccount_kiosk&lang=sv&kiosk=true
EXTERNAL_URL_TIMEOUT=30000
# Valfritt: extra värdnamn (kommaseparerade) som "Registrera konto"/"Boka dator" får navigera till.
# Värdarna i REGISTER_ACCOUNT_URL och BOOKING_SYSTEM_URL är alltid tillåtna (endast https).
EXTERNAL_ALLOWED_HOSTS=
# Valfritt: extra flaggor till Chromium, t ex "--enable-unsafe-swiftshader" i test-VM utan GPU
CHROMIUM_FLAGS=
ELECTRON_DEV_TOOLS=false
ALMA_LOGIN=false
PRINTER=false
COMPUTER_TYPE=searchcomputer
COMPUTER_NAME="KTH Library Search computer"
SESSION_IDLE=5
SCREEN_ROTATION=left
SCREENSAVER=false
SCREENSAVER_IDLE=00:10:00
SCREENSAVER_FILES="screen_bg_kth_logo_navy_guest.png"
POLICY_FILE="policies_guest.json"
KIOSK=--kiosk
WEBSITES="https://www.kth.se/biblioteket"
WHITE_LIST="file:///home/guest,chrome://print,chrome-untrusted://print,chrome://newtab,chrome://downloads,kth.se,exlibrisgroup.com,libkey.io,thirdiron.com,kundo.se"
KOPIERA_NEDAN="Kopiera in lämplig WEBSITES och WHITE_LIST"
WEBSITES_GUEST="https://www.kth.se/biblioteket"
WEBSITES_SEARCH="https://kth-ch.primo.exlibrisgroup.com/discovery/search?vid=46KTH_INST:46KTH_Kiosk&lang=sv https://libris.kb.se/"
WEBSITES_GRUPPRUM_NORMAL="https://apps.lib.kth.se/mrbsgrupprumkiosk https://apps.lib.kth.se/mrbsreadingstudioskiosk"
WEBSITES_GRUPPRUM_KIOSK="https://s3.lib.kth.se/kthb-kiosk/grupprum.html"
WHITE_LIST_GRUPPRUM="apps.lib.kth.se,s3.lib.kth.se"
WHITE_LIST_GUEST="file:///home/guest,chrome://print,chrome-untrusted://print,chrome://newtab,chrome://downloads,kth.se,exlibrisgroup.com,libkey.io,thirdiron.com,kundo.se,wagnerguide.com,libris.kb.se"
WHITE_LIST_SEARCH="kth-ch.primo.exlibrisgroup.com,cdn.jsdelivr.net,kth-primo.hosted.exlibrisgroup.com,proxy-eu.hosted.exlibrisgroup.com,beacon-eu.hosted.exlibrisgroup.com,eu01.alma.exlibrisgroup.com,wagnerguide.com,api.oadoi.org,ebooks.cambridge.org,whatismyipaddress.com,kundo.se,apps.lib.kth.se,apps-ref.lib.kth.se,libris.kb.se,unpkg.com"
```

#### Doc
https://medium.com/@yann.cardaillac/ubuntu-22-04-in-simple-kiosk-mode-8d1379fa7b4a

#### Doc
https://gist.github.com/yt/45e3bc4b315b834bb0886b9048eb155e

### Eventuellt Skydda GRUB boot menu
```bash
grub-mkpasswd-pbkdf2
```
Kopiera hela hash-strängen (från grub.pbkdf2... och framåt)

```bash
sudo nano /etc/grub.d/40_custom
```

Lägg till följande i slutet av filen, ersätt <hashed-password> med den hash-sträng du kopierade ovan
Ta reda på vilken kärnversion(t ex 5.4.0-205-generic) som används genom att köra `uname -r`
Ta reda på vilken rotpartition(t ex /dev/mapper/ubuntu--vg-ubuntu--lv) som används genom att köra `blkid`
```
set superusers="kthb"
password_pbkdf2 kthb <hashed-password>
menuentry "Ubuntu" --unrestricted {
    linux /vmlinuz-5.4.0-205-generic root=/dev/mapper/ubuntu--vg-ubuntu--lv ro quiet quiet
    initrd /initrd.img-5.4.0-205-generic
}
menuentry "Ubuntu (Recovery Mode)" --restricted {
    linux /vmlinuz-5.4.0-205-generic root=/dev/mapper/ubuntu--vg-ubuntu--lv ro recovery nomodeset
    initrd /initrd.img-5.4.0-205-generic
}
```

```bash
## Inaktivera vanliga grubmenyn
sudo chmod -x /etc/grub.d/10_linux
## Uppdatera grub
sudo update-grub
```

#### Skapa en avbildning av en kiosk-dator
```bash
sudo dd if=/dev/sda bs=4M status=progress | smbclient //NAS_SERVER_IP/SHARE_NAME -U NAS_USERNAME%NAS_PASSWORD -c "put - backup.img"
```

### Struktur i repot
```
install.sh                 Installerar paket och engångsinställningar, kör sedan deploy.sh
files.manifest             Alla filer som installeras på datorerna, med rättigheter och ägare
files/                     Filerna, i samma sökväg som på datorn (files/usr/local/bin/init.sh -> /usr/local/bin/init.sh)
config/base.env            Gemensamma värden
config/profiles/*.env      En fil per typ av dator (guest-login, search, grouproom, signage)
config/hosts/*.env         En fil per dator, anger PROFILE och det som skiljer datorn från profilen
.config_xxx                GENERERADE från config/ med tools/build-configs.sh (checkas in, datorerna hämtar dem)
policies_*.json            Chromium-policyer
backgrounds/ icons/ screensaver/   Bilder
```

### Hur datorerna uppdateras
Vid varje uppstart kör `init.service` skriptet `init.sh`, som
1. hämtar datorns `.config_xxx` från branchen i `PUBLICOM_BRANCH` (normalt `stable`),
2. kör `deploy.sh`, som hämtar hela branchen, validerar alla filer (syntax, JSON) och installerar de som ändrats enligt `files.manifest`. Om något är fel ändras ingenting,
3. hämtar Chromium-policy och skärmsläckarbilder.

Därefter startar `allowlist_from_ezproxy.service` och sist `guest.service` (sessionen). Ändringar gäller alltså från och med nästa omstart.

Status för senaste deploy: `cat /var/lib/publicom/deployed` och `journalctl -u init`.

### Config
Ändra aldrig `.config_xxx` direkt. Ändra i `config/` och generera:
```bash
tools/build-configs.sh
```
Ny dator: skapa `config/hosts/<namn>.env` med minst `PROFILE=<profil>` och kör skriptet. `tools/build-configs.sh --check` kontrollerar att de genererade filerna är aktuella.

För att testa en branch på en enskild dator, sätt `PUBLICOM_BRANCH=<branch>` i datorns host-fil på den branchen.

### Rulla ut en ändring
Datorerna följer `stable`. `main` är utvecklingsbranch.
1. Gör ändringen på en egen branch och testa på en testdator (se ovan).
2. Merga till `main`.
3. När den är testad: uppdatera `stable`
```bash
git push origin main:stable
```
4. Datorerna hämtar ändringen vid nästa omstart.

**Viktigt:** `.config_xxx` och `policies_*.json` måste finnas kvar i roten på både `main` och `stable`. Datorer med äldre `init.sh` hämtar dem därifrån utan felkontroll.

### Flytta en befintlig dator till deploy (en gång)
Datorer installerade före version 3.0 uppdaterar inte sina skript automatiskt. Kör en gång på varje dator:
```bash
sudo curl -fsSL -o /tmp/publicom.tar.gz https://github.com/kth-biblioteket/publicom/archive/refs/heads/stable.tar.gz
sudo tar -xzf /tmp/publicom.tar.gz -C /tmp
sudo curl -fsSL -o /usr/local/bin/config/.config https://raw.githubusercontent.com/kth-biblioteket/publicom/stable/.config_xxx
sudo bash /tmp/publicom-stable/files/usr/local/bin/deploy.sh /tmp/publicom-stable
sudo systemctl disable session-cleanup.service; sudo rm -f /etc/systemd/system/session-cleanup.service
sudo reboot
```

##### Filer/Struktur

/usr/local/bin/ -la
total 118940
drwxr-xr-x  7 root root      4096 May 22 11:03 .
drwxr-xr-x 11 root root      4096 Jan 13  2025 ..
-rwxr-xr-x  1 root root      3615 May 22 10:10 allowlist_from_ezproxy.sh
-rwxr-xr-x  1 root root       382 May 22 10:10 clean-up.sh
-rwxr-xr-x  1 root root       109 May 22 10:10 clear_inactivity.sh
drwxr-xr-x  2 root root      4096 May 22 10:22 config
lrwxrwxrwx  1 root root        45 May 22 10:10 corepack -> ../lib/node_modules/corepack/dist/corepack.js
drwxr-xr-x  3 root root      4096 Jan 13  2025 electron-login
drwxr-xr-x  2 root root      4096 Apr  3 07:17 icons
-rwxr-xr-x  1 root root      1504 May 22 10:10 init.sh
-rw-r--r--  1 root root     11401 May 22 10:10 KTH_logo_RGB_vit_small.png
-rwxr-xr-x  1 root root       129 May 22 10:10 logout_and_cancel.sh
-rwxr-xr-x  1 root root      1918 May 22 10:10 logout_timer.sh
lrwxrwxrwx  1 root root        27 May 22 10:10 n -> ../lib/node_modules/n/bin/n
-rwxr-xr-x  1 root root 121509208 May 22 10:10 node
lrwxrwxrwx  1 root root        38 May 22 10:10 npm -> ../lib/node_modules/npm/bin/npm-cli.js
lrwxrwxrwx  1 root root        38 May 22 10:10 npx -> ../lib/node_modules/npm/bin/npx-cli.js
-rw-r--r--  1 root root     18683 May 22 10:10 screen_bg_gc_empty.png
-rw-r--r--  1 root root     75513 May 22 10:10 screen_bg_gc.png
-rw-r--r--  1 root root     94886 May 22 10:10 screen_bg_kth_logo_navy.png
drwxr-xr-x  2 root root      4096 Aug  4 11:14 screensaver
drwxr-xr-x  2 root root      4096 May 22 11:03 secrets
-rwxr-xr-x  1 root root      2502 May 22 10:10 session_cleanup.sh
-rwxr-xr-x  1 root root       223 May 22 10:10 show_remaining_time.sh
-rwxr-xr-x  1 root root       547 May 22 10:10 tint2_inactivity_warning.sh
-rwxr-xr-x  1 root root       126 May 22 10:10 update_tint_computer_name.sh

/usr/local/bin/config/ -la
total 12
drwxr-xr-x 2 root root 4096 May 22 10:22 .
drwxr-xr-x 7 root root 4096 May 22 11:03 ..
-rw-r--r-- 1 root root 1345 Aug  4 11:14 .config

/usr/local/bin/electron-login/ -la
total 92
drwxr-xr-x  3 root root  4096 Jan 13  2025 .
drwxr-xr-x  7 root root  4096 May 22 11:03 ..
-rw-r--r--  1 root root 13766 May 22 10:10 index.html
-rw-r--r--  1 root root 17270 May 22 10:10 main.js
drwxr-xr-x 76 root root  4096 May 22 10:10 node_modules
-rw-r--r--  1 root root   103 May 22 10:10 package.json
-rw-r--r--  1 root root 33386 May 22 10:10 package-lock.json
-rw-r--r--  1 root root   348 May 22 10:10 preload.js

/usr/local/bin/icons/ -la
total 16
drwxr-xr-x 2 root root 4096 Apr  3 07:17 .
drwxr-xr-x 7 root root 4096 May 22 11:03 ..
-rw-r--r-- 1 root root 1303 May 22 10:10 icons8-green-circle-32.png
-rw-r--r-- 1 root root 1185 May 22 10:10 icons8-red-circle-32.png

/usr/local/bin/screensaver/ -la
total 168
drwxr-xr-x 2 root root   4096 Aug  4 11:14 .
drwxr-xr-x 7 root root   4096 May 22 11:03 ..
-rw-r--r-- 1 root root 160611 Aug  4 11:14 screen_bg_kth_logo_navy_guest.png

/usr/local/bin/secrets/ -la
total 12
drwxr-xr-x 2 root root 4096 May 22 11:03 .
drwxr-xr-x 7 root root 4096 May 22 11:03 ..
-rw-r--r-- 1 root root  276 May 22 11:03 .secrets


/home/guest -la
total 80
drwxr-xr-x 9 guest guest 4096 Aug  5 08:15 .
drwxr-xr-x 4 root  root  4096 Jan 13  2025 ..
-rw-r--r-- 1 guest guest  220 Jan 13  2025 .bash_logout
-rw-r--r-- 1 guest guest 3771 Jan 13  2025 .bashrc
drwxr-xr-x 8 guest guest 4096 May 22 10:12 .cache
drwxr-xr-x 6 guest guest 4096 May 22 10:19 .config
drwx------ 3 guest guest 4096 Jan 13  2025 .dbus
-rwxr-xr-- 1 guest guest   82 Aug  4 11:16 .fehbg
drwx------ 3 guest guest 4096 Jan 13  2025 .local
drwxr-xr-x 5 guest guest 4096 May 22 10:12 .npm
drwx------ 3 guest guest 4096 May 22 10:12 .pki
-rw-r--r-- 1 guest guest  807 Jan 13  2025 .profile
-rwxr-xr-x 1 root  root    73 May 22 10:10 restart_x.sh
drwx------ 3 guest guest 4096 Jan 13  2025 snap
-rw------- 1 guest guest  195 May 22 11:05 .Xauthority
-rw-r--r-- 1 root  root  1005 May 22 10:10 .xbindkeysrc
-rwxr-xr-x 1 guest guest 6386 May 22 10:10 .xinitrc
-rw-r--r-- 1 root  root    28 May 22 10:10 .Xmodmap
-rw-r--r-- 1 guest guest  205 Aug  4 15:02 .xscreensaver
