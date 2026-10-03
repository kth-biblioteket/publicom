# Installera en dator

Gäller både en helt ny dator och ominstallation av en dator i den gamla flottan. Alla datorer kör
**Ubuntu Server 24.04 LTS**. Byt Ubuntu-version genom att installera om, aldrig med `do-release-upgrade`.

Det tar ungefär en timme, mest väntan. Installationen kan göras över SSH, på plats eller på distans,
när Ubuntu väl är installerat.

## 1. Förbered

**I publicomtools (admin)**

Datorn måste finnas i admin innan den installeras, annars får den inga inställningar.

- **En dator i den gamla flottan** (gc1, gc2, kc1, kc2, pcad, pcangdomen, scbh, scng, scsg) finns redan,
  med profil och egna inställningar inlästa från de gamla configfilerna. Gå igenom dem under
  *Datorer → datorn → Inställningar* innan du installerar. Kontrollera särskilt profilen,
  *Resurs i bokningssystemet* (gästdatorer) och *Inloggningsskärm*. Granskningen varnar för
  vissa felaktiga kombinationer.
- **En helt ny dator** (nytt värdnamn): *Datorer → Lägg till dator*. Ange värdnamnet (samma som i Ubuntu:
  små bokstäver, siffror och `-`), profilen och gärna ett namn för listan. Ställ sedan in det som skiljer datorn
  från profilen. Den visas som *Väntar på installation* tills den har hämtat sina inställningar.

**Att ha med sig**

- [ ] USB-minne med **Ubuntu Server 24.04.x amd64** från ubuntu.com. Välj uttryckligen 24.04, inte
      "senaste LTS". Server, inte Desktop. amd64, inte arm64.
- [ ] Värdena till `.secrets` (se steg 4). För en dator i den gamla flottan: samma värden som i dess nuvarande `.secrets`.
- [ ] BIOS-lösenordet.

## 2. BIOS/UEFI

Görs i datorns egen BIOS/UEFI-meny (oftast F2, F10, F12 eller Del vid påslag). Det här är det yttersta
skyddet: med tillgång till BIOS kan man starta från ett USB-minne och kringgå allt annat.

- [ ] **Administratörslösenord** (Supervisor/Setup password) satt och antecknat på säker plats
- [ ] **Start endast från den inbyggda disken**, övriga enheter borttagna ur startordningen
- [ ] **Start från USB avstängt** (tillåt det bara under installationen, stäng av efteråt)
- [ ] **Start från nätverk avstängt** (PXE / Network boot)
- [ ] **Startmeny vid påslag avstängd eller lösenordsskyddad** (Boot menu, ofta F12)
- [ ] **Secure Boot på**
- [ ] Gärna: **tyst uppstart** (Quiet boot)
- [ ] Gärna: **starta efter strömavbrott** (Restore on AC power loss: On)

## 3. Installera Ubuntu

- [ ] Ubuntu Server 24.04 med användaren `kthb` och **OpenSSH**. Värdnamnet ska vara datorns namn i admin.
- [ ] Eventuellt wifi: `sudo nmcli dev wifi connect "KTH-IoT" password "<lösenord>"`
- [ ] SSH fungerar från KTH-nätet: `ssh kthb@<dator>`

Lägg **inte** till `systemd.unified_cgroup_hierarchy=0` (behövdes för 22.04, fungerar inte på 24.04).

## 4. Hemligheter

```bash
sudo mkdir -p /usr/local/bin/secrets
sudo nano /usr/local/bin/secrets/.secrets
```
```
PUBLICOM_DEVICE_TOKEN=xxxxxxx
VNC_PASSWORD=xxxxxxx
GRUB_PASSWORD_HASH=grub.pbkdf2.sha512.10000.xxxxxxx
BOOKING_API_KEY=xxxxxxx
```
```bash
sudo chown root:root /usr/local/bin/secrets/.secrets
sudo chmod 600 /usr/local/bin/secrets/.secrets
sudo chmod 700 /usr/local/bin/secrets
```

- `PUBLICOM_DEVICE_TOKEN` krävs: med den hämtar datorn sina inställningar och skickar status. Samma värde som `PUBLICOM_DEVICE_TOKEN` i publicomtools.
- `VNC_PASSWORD` krävs av `install.sh`.
- `GRUB_PASSWORD_HASH` skapas med `grub-mkpasswd-pbkdf2` (kopiera allt från `grub.pbkdf2...`). Välj ett lösenord med **bara a–z och siffror**: GRUB använder alltid amerikansk tangentbordslayout. Saknas den startar datorn som vanligt, men GRUB-menyn skyddas inte.
- `BOOKING_API_KEY` behövs bara på gästdatorer med inloggningsskärmen som program (Electron), och som reserv för webbinloggningen.
- `GITHUB_TOKEN` behövs **inte** längre. EZproxy-listan hämtas från publicomtools, se [Drift](drift.md#webbläsarens-regler).

## 5. Inställningar och installation

Hämta datorns första inställningar från publicomtools (pilotdatorn gc3 använder `apps-ref.lib.kth.se`):

```bash
sudo mkdir -p /usr/local/bin/config
sudo curl -fsS -H "Authorization: Bearer $(sudo grep '^PUBLICOM_DEVICE_TOKEN=' /usr/local/bin/secrets/.secrets | cut -d= -f2-)" \
  -o /usr/local/bin/config/.config \
  "https://apps.lib.kth.se/publicomtools/api/device/config?host=$(hostname)"
grep -E '^(PUBLICOM_HOST|PUBLICOM_PROFILE|PUBLICOM_BRANCH|REMOTE_CONFIG_URL)=' /usr/local/bin/config/.config
```

Kontrollera att värdnamn, profil och gren stämmer. Får du 404 finns datorn inte i admin (steg 1).

Installera från datorns gren (`PUBLICOM_BRANCH`, normalt `stable`). Datorn startar om när den är klar.
Kör i `tmux` över SSH, så överlever installationen ett tappat nätverk:

```bash
BRANCH=$(grep '^PUBLICOM_BRANCH=' /usr/local/bin/config/.config | cut -d'"' -f2)
curl -fsSL -o /tmp/install.sh "https://raw.githubusercontent.com/kth-biblioteket/publicom/${BRANCH:-stable}/install.sh"
sudo bash /tmp/install.sh 2>&1 | tee ~/install.log
```

**Från en lokal kopia** (en gren som inte är pushad, eller utan internet till GitHub): packa koden på din dator
med `git archive --format=tar.gz --prefix=publicom/ <gren> > ~/publicom.tar.gz`, kopiera den till datorn och kör:

```bash
tar -xzf /tmp/publicom.tar.gz -C /tmp
sudo PUBLICOM_SRC=/tmp/publicom bash /tmp/publicom/install.sh 2>&1 | tee ~/install.log
```

## 6. Kontrollera

Efter omstarten, på datorn:

- [ ] Datorn startar direkt till rätt läge (inloggningsskärm, sökdator eller skylt), utan meny eller text
- [ ] `systemctl --failed`: inga kraschade tjänster
- [ ] `journalctl -b -u init.service | grep -iE "error|policy|deploy"`: inställningarna och koden hämtades
- [ ] `sudo ufw status`: bara SSH (22) från `SSH_ALLOW_FROM`
- [ ] `lpstat -p -d`: KTH-Print finns och är standard (om utskrift används)
- [ ] `less ~/install.log` eller `grep -iE "error|fail" ~/install.log`

I admin:

- [ ] Datorn är **OK** i datoröversikten och har hört av sig de senaste minuterna
- [ ] Chippet **Gamla configfiler** är borta (datorn hämtar sina inställningar från publicomtools)
- [ ] Under *Teknik* stämmer *Det datorn får vid start* med det du förväntar dig

Sist: stäng av start från USB i BIOS igen.

Den fullständiga checklistan för att prova en ny version på riktig hårdvara finns i [Test på riktig dator](hardvarutest.md).
