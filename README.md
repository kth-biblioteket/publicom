# PubLiCom
## KTH Bibliotekets Publika Datorer, Public Computers KTH Library
Datorer i bibliotekets publika miljöer

- Kioskdatorer
- Sökdatorer
- Gästdatorer

### Installation
- Installera Ubuntu Server 24.04 LTS på en dator (20.04 fungerar också, men har inte längre standardsupport).
- Välj att installera SSH
- Uppgradera vid behov: `sudo apt upgrade -y`. Byt Ubuntu-version genom att installera om, inte med `do-release-upgrade`.
- Ställ in BIOS/UEFI enligt [checklistan](#biosuefi-checklista) nedan.
- GRUB (dold meny, tyst start, lösenordsskydd) ställs in av `install.sh`, se [GRUB](#grub) nedan.
  Lägg **inte** till `systemd.unified_cgroup_hierarchy=0` (behövdes tidigare för 22.04, men inte längre och fungerar inte på 24.04).

Skapa en hemlighetsfil
```bash
sudo mkdir /usr/local/bin/secrets
sudo nano /usr/local/bin/secrets/.secrets
```
```
GITHUB_TOKEN=xxxxxxx
VNC_PASSWORD=xxxxxxx
BOOKING_API_KEY=xxxxxxx
GRUB_PASSWORD_HASH=grub.pbkdf2.sha512.10000.xxxxxxx
HEARTBEAT_TOKEN=xxxxxxx
```
`HEARTBEAT_TOKEN` är valfri, se [Statussida](#statussida-heartbeat).
`GRUB_PASSWORD_HASH` skapas med `grub-mkpasswd-pbkdf2` (kopiera allt från `grub.pbkdf2...`). Välj ett lösenord med **bara a–z och siffror**: GRUB använder alltid amerikansk tangentbordslayout, så t ex `-`, `å`, `ä`, `ö` och andra specialtecken hamnar på andra tangenter än på ett svenskt tangentbord. Användarnamnet i GRUB är `kthb`. Saknas den startar datorn som vanligt, men GRUB-menyn skyddas inte.
Github token user "kthbiblioteket" https://github.com/settings/personal-access-tokens

Token: `publiccomputers` (fine-grained). **Går ut 23 november 2026**, förnya den i god tid och byt på datorerna som använder den. Behövs bara för öppna gästdatorer (`ALMA_LOGIN=false`); i dag har ingen config det.
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

Brandvägg och fjärråtkomst
- `install.sh` slår på `ufw`: allt inkommande nekas utom SSH (port 22) från `SSH_ALLOW_FROM` i config (standard `130.237.0.0/16`, KTH:s nät).
- VNC lyssnar bara lokalt på datorn (`x11vnc -localhost`), så port 5900 är aldrig öppen utåt. Anslut via SSH-tunnel:
```bash
ssh -L 5900:localhost:5900 kthb@<dator>
```
  och anslut sedan VNC-klienten till `localhost:5900` (med VNC-lösenordet som vanligt).
- Äldre datorer får `-localhost` automatiskt vid deploy (x11vnc.service). Den gamla ufw-regeln för 5900 kan tas bort med `sudo ufw delete allow from 130.237.0.0/16 to any port 5900`.

Eventuellt wifi:
```bash
sudo nmcli dev wifi connect "KTH-IoT" password "xXXXxXxX"
```

Kontrollera access till SSH från KTH-nätverket

Terminal på datorn (Ctrl+Shift+T i gästsessionen)
- Öppnar `xterm` med `su -l kthb`, så inloggningen kräver kthb-kontots vanliga lösenord. Inget lösenord eller hash lagras i någon fil, och gästen får aldrig ett eget skal (fel lösenord stänger fönstret).
- Efter fel lösenord väntar `su` 4 sekunder (`pam_faildelay` i `/etc/pam.d/su`). Kontot låses aldrig, så man kan inte låsa ute sig själv. SSH påverkas inte.
- `/usr/local/bin/open_terminal.sh` installeras av `deploy.sh`. `xterm` och fördröjningen installeras av `install.sh`.
- Äldre datorer har ett eget `open_terminal.sh` med en lösenordshash. Det ersätts automatiskt vid deploy, men `xterm` och fördröjningen måste läggas till en gång:
```bash
sudo apt install -y --no-install-recommends xterm
grep -q pam_faildelay /etc/pam.d/su || sudo sed -i '0,/^auth/s//auth       optional   pam_faildelay.so delay=4000000\nauth/' /etc/pam.d/su
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
# Dialogrutor för filer (spara som, bifoga/ladda upp). false = inga, nedladdningar fungerar ändå
FILE_DIALOGS=true
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

### BIOS/UEFI-checklista
Görs i datorns egen BIOS/UEFI-meny (oftast F2, F10, F12 eller Del vid påslag, olika för olika tillverkare).
Detta är det yttersta skyddet: med tillgång till BIOS kan man starta från ett USB-minne och kringgå
GRUB-lösenordet, kioskläget och alla policyer. GRUB och Ubuntu kan inte skydda BIOS.

- [ ] **Administratörslösenord** (Supervisor/Setup password) satt och antecknat på säker plats
- [ ] **Start endast från den inbyggda disken**, övriga enheter borttagna ur startordningen
- [ ] **Start från USB avstängt** (USB boot / External boot)
- [ ] **Start från nätverk avstängt** (PXE / Network boot)
- [ ] **Startmeny vid påslag avstängd eller lösenordsskyddad** (Boot menu, ofta F12)
- [ ] **Secure Boot på** (Ubuntus signerade kärna fungerar med det)
- [ ] Gärna: **tyst uppstart** (Quiet boot / logotyp i stället för text)
- [ ] Gärna: **starta efter strömavbrott** (AC power recovery / Restore on AC power loss: On), så att datorn kommer tillbaka av sig själv

Obs: inget av detta skyddar mot att någon öppnar datorn och tar ut disken. Det kräver diskkryptering.

### GRUB
`install.sh` gör följande (fungerar på både Ubuntu 20.04 och 24.04):
- `/etc/default/grub.d/99-publicom.cfg`: dold meny, ingen fördröjning, inga recovery-poster, `quiet`.
- Om `GRUB_PASSWORD_HASH` finns i hemlighetsfilen: `/etc/grub.d/01_publicom_password` sätter superanvändaren `kthb` med lösenord, och Ubuntus vanliga poster i `/etc/grub.d/10_linux` märks `--unrestricted`.

Resultat: datorn startar utan lösenord, men att ändra menyposter (tangenten `e`), använda GRUB:s kommandorad, "Advanced options" och "UEFI Firmware Settings" kräver lösenordet. Menyposterna genereras av Ubuntu och följer kärnuppdateringar automatiskt, inga kärnversioner eller partitioner är hårdkodade.

Kontrollera efteråt:
```bash
sudo grep -E "^set superusers|^menuentry" /boot/grub/grub.cfg
```

#### Datorer som använder det gamla upplägget
Tidigare beskrevs egna poster i `40_custom` med hårdkodad kärnversion och `chmod -x /etc/grub.d/10_linux`. Det slutar fungera när den kärnan tas bort vid en uppdatering. För att byta:
```bash
sudo nano /etc/grub.d/40_custom        # ta bort de egna menuentry-blocken och password-raderna
sudo chmod +x /etc/grub.d/10_linux
```
Kör sedan GRUB-delen av `install.sh` (eller installera om), och kontrollera med kommandot ovan innan omstart.

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

### Automatiska uppdateringar
- **Säkerhetsuppdateringar** installeras automatiskt av `unattended-upgrades` (bara `-security`, enligt Ubuntus standard): paketlistor ca 01:30, installation ca 02:30.
- Om en uppdatering kräver omstart (t ex ny kärna) startar datorn om **kl. 03:30**, även med gästsessionen igång.
- **Chromium (snap)** uppdateras bara mellan 02:00 och 04:00 (`snap set system refresh.timer=02:00-04:00`, görs av `install.sh`).
- Datorn behöver vara påslagen på natten. Är den avstängd körs uppdateringen när den startas, och en eventuell omstart sker natten efter.
- Konfigureras av `deploy.sh` (`10periodic`, `52publicom-unattended-upgrades`, tidtagarna i `apt-daily*.timer.d`). Senaste körningen: `/var/log/unattended-upgrades/unattended-upgrades.log`.
- Obs: Ubuntu 20.04 får bara säkerhetsuppdateringar via Ubuntu Pro (ESM). Utan Pro finns inga nya att installera, ännu ett skäl att gå över till 24.04.

### Statussida (heartbeat)
Varje dator skickar sin status till [publicomtools](https://github.com/kth-biblioteket/publicomtools) (`https://apps.lib.kth.se/publicomtools`) var 5:e minut: senaste deploy, uptime, om gästsessionen körs, kraschade tjänster, ledigt diskutrymme och om en omstart väntar. Statussidan kräver KTH-inloggning.
- Skickas av `heartbeat.sh` via `heartbeat.timer` (installeras och aktiveras av `deploy.sh`).
- Adressen är `HEARTBEAT_URL` i config (`config/base.env`). Token är `HEARTBEAT_TOKEN` i `.secrets`, samma värde som `HEARTBEAT_TOKEN` i publicomtools. **Utan token skickas ingenting**, så funktionen slås på dator för dator.
- Datorn identifieras med `PUBLICOM_HOST` (namnet på host-filen, t ex `gc1`), som `tools/build-configs.sh` skriver in i `.config_<dator>`.
- Kontrollera på datorn: `journalctl -u heartbeat.service -n 5`. Kör direkt: `sudo systemctl start heartbeat.service`.

### Gästens filer
Inget som en gäst har sparat får finnas kvar till nästa användare. Chromiums dialogruta för att spara filer når hela `/home/guest`, inte bara Downloads.
- `clean-up.sh` (vid sessionsstart och utloggning) tar bort allt i `/home/guest` utom det som `files.manifest` installerar och det som sessionen behöver (`KEEP_HOME`, `KEEP_CONFIG` i skriptet). Chromiums hemkatalog i snap töms på allt utom de tomma mapparna Downloads, Documents osv.
- `session_cleanup.sh` (root, efter sessionen) tömmer Chromiums privata `/tmp` (`/tmp/snap-private-tmp/snap.chromium/tmp`).
- Ska en ny fil installeras i `/home/guest` måste den läggas till i `KEEP_HOME`/`KEEP_CONFIG`, annars tas den bort vid varje session. `tools/check.sh` kontrollerar det.

### Kontroller (CI)
`tools/check.sh` kontrollerar skriptens syntax (och `shellcheck` om det finns), JSON, Electron-koden, att `.config_*` är aktuella och att `files.manifest` stämmer med `files/`. Kör den innan commit:
```bash
tools/check.sh
```
Samma kontroller körs automatiskt i GitHub Actions (`.github/workflows/ci.yml`) vid varje push och pull request. Merga inte till `main` eller `stable` om de misslyckas.

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
