# PubLiCom
## KTH Bibliotekets Publika Datorer, Public Computers KTH Library
Datorer i bibliotekets publika miljöer

- Kioskdatorer
- Sökdatorer
- Gästdatorer

### Installation
- Installera en Ubuntu Server (20.04 eller nyare) på en dator.
- Välj att installera SSH
- Uppgradera vid behov
    - apt upgrade -y
    - do-release-upgrade
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
```
```bash
sudo chown root:root /usr/local/bin/secrets/.secrets
sudo chmod 600 /usr/local/bin/secrets/.secrets
sudo chmod 700 /usr/local/bin/secrets
```

Skapa en .config-fil kopiera från rätt fil i detta repo
```bash
sudo mkdir /usr/local/bin/config
sudo curl -o "/usr/local/bin/config/.config" https://raw.githubusercontent.com/kth-biblioteket/publicom/main/.config_xxx
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

Kontrollera access till SSH från KTH-nätverket

Kopiera install.sh från github, gör den exekverbar och starta den
```bash
sudo curl -L -o ./install.sh https://raw.githubusercontent.com/kth-biblioteket/publicom/main/install.sh
sudo chmod +x install.sh
sudo ./install.sh
```

#### Config Exempel
```
REMOTE_CONFIG_URL="https://raw.githubusercontent.com/kth-biblioteket/publicom/main/.config_xxxx"
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
ELECTRON_DEV_TOOLS=false
ALMA_LOGIN=false
PRINTER=false
COMPUTER_TYPE=searchcomputer
COMPUTER_NAME="KTH Library Search computer"
SESSION_IDLE=5
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
