# Installera en dator

Gäller en ny dator och ominstallation av en befintlig. Alla datorer kör
**Ubuntu Server 24.04 LTS**. Byt Ubuntu-version genom att installera om, aldrig med `do-release-upgrade`.

Det tar ungefär en timme, mest väntan. Installationen kan göras över SSH, på plats eller på distans,
när Ubuntu väl är installerat.

## 1. Förbered

**I publicomtools (admin)**

Datorn måste finnas i admin innan den installeras, annars får den inga inställningar.

Lägg till datorn: *Datorer → Lägg till dator*. Ange värdnamnet (samma som i Ubuntu:
  små bokstäver, siffror och `-`), profilen och gärna ett namn för listan. Ställ sedan in det som skiljer datorn
  från profilen. Den visas som *Väntar på installation* tills den har hämtat sina inställningar.

**Det som måste vara ifyllt i admin innan installationen**

Datorn hämtar *allt* härifrån vid start. Saknas något fungerar den delvis eller inte alls, och det syns först efteråt. Öppna datorn under *Teknik → Det datorn får vid start*
och kontrollera att raderna nedan finns, antingen från profilen eller från grundinställningarna (*Alla datorer*). Annars lägger du till dem där, så att nästa dator får dem automatiskt:

| Inställning | Varför | Om den saknas |
|---|---|---|
| `PUBLICOM_PROFILE`, `COMPUTER_TYPE` | Vilken sorts dator (gästdator, sökdator, skylt, kiosk) | Fel läge vid start |
| `PUBLICOM_BRANCH` (normalt `stable`) | Gren som kod och skript hämtas från | Datorn använder `stable` |
| `REMOTE_CONFIG_URL` | Adressen datorn hämtar sina inställningar från | Datorn behåller gamla inställningar |
| `HEARTBEAT_URL` | Dit statusrapporten skickas | Produktionsservern (`apps.lib.kth.se`). En testdator måste ha sin egen adress |
| `PUBLICOMTOOLS_URL` | Adress till publicomtools (webbinloggning, EZproxy-regler) | Produktionsservern (`apps.lib.kth.se`). En testdator måste ha sin egen adress |
| `POLICY_FILE` | Webbläsarens regler (`policies_guest.json` eller `policies_search.json`) | Datorn väljer grundpolicyn för sin typ, men sätt den uttryckligen |
| `SCREENSAVER`, `SCREENSAVER_IDLE`, `SCREENSAVER_FILES` (gäst- och sökdator) | Skärmsläckaren | **Av som standard**: ingen skärmsläckare |
| `SESSION_IDLE` (öppen gästdator), minuter | Återställer sessionen efter inaktivitet | **0 = av som standard**: inget återställs efter användning |
| `SSH_ALLOW_FROM` | Vilka som får nå SSH | Brandväggen blir för sträng eller för öppen |
| Typspecifika: *Resurs i bokningssystemet*, *Inloggningsskärm* (gästdator), *Adresser* (skylt), *Tjänster* (kiosk) | Det datorn ska visa | Tom eller fel startsida |

Lägg dessutom in i admin: **datorn med rätt värdnamn** (annars 404 vid första hämtningen) och **dess profil**. En helt ny dator ärver allt från profilen och grundinställningarna,
så det är där de gemensamma värdena ska ligga, inte på varje dator.

**Att ha med sig**

- [ ] USB-minne med **Ubuntu Server 24.04.x amd64** från ubuntu.com. Välj uttryckligen 24.04, inte
      "senaste LTS". Server, inte Desktop. amd64, inte arm64.
- [ ] Värdena till `.secrets` (se steg 4).
- [ ] BIOS-lösenordet.

## 2. BIOS/UEFI

Görs i datorns egen BIOS/UEFI-meny (oftast F2, F10, F12 eller Del vid påslag). Det här är det yttersta
skyddet: med tillgång till BIOS kan man starta från ett USB-minne och kringgå allt annat.

- [ ] **Administratörslösenord** (Supervisor/Setup password) satt och antecknat på säker plats
- [ ] **Start endast från den inbyggda disken**, övriga enheter borttagna ur startordningen
- [ ] **Start från USB avstängt** (men **slå på det under installationen**, annars startar inte installationsminnet; stäng av det efteråt)
- [ ] **Start från nätverk avstängt** (PXE / Network boot)
- [ ] **Startmeny vid påslag avstängd eller lösenordsskyddad** (Boot menu, ofta F12)
- [ ] **Secure Boot på**
- [ ] Gärna: **tyst uppstart** (Quiet boot)
- [ ] Gärna: **starta efter strömavbrott** (Restore on AC power loss: On)

## 3. Installera Ubuntu

- [ ] Ubuntu Server 24.04 med användaren `kthb` och **OpenSSH**. Värdnamnet ska vara datorns namn i admin, enligt [namnstandarden](#namn-på-en-dator) nedan (`publicom01`, `publicom02`, …).
- [ ] Eventuellt wifi: `sudo nmcli dev wifi connect "KTH-IoT" password "<lösenord>"`
- [ ] SSH fungerar från KTH-nätet: `ssh kthb@<dator>`

Lägg **inte** till `systemd.unified_cgroup_hierarchy=0` (behövdes för 22.04, fungerar inte på 24.04).

**Installera i UEFI-läge, aldrig Legacy/CSM.** Installeras datorn i Legacy och du sedan byter till UEFI startar den inte, och då måste den installeras om. Därför:

- Ha UEFI på (och Secure Boot på) *innan* du startar installationen, och gör USB-minnet UEFI-startbart (balenaEtcher, eller Rufus med GPT och UEFI).
- Välj USB-minnets **UEFI-post** i startmenyn (F12), inte posten utan "UEFI".
- Finns en gammal post som **Windows Boot Manager** kvar tar den över startordningen. Ta bort den efter installationen (`sudo efibootmgr`, sedan `sudo efibootmgr -b <nr> -B`), så att bara `ubuntu` finns kvar.
- Kontroll efteråt: `ls /sys/firmware/efi && echo UEFI` ska skriva UEFI.

**Nätverket under installationen.** Hittar installeraren ingen adress är det oftast kabeln eller switchporten: prova en annan kabel och port, och titta med `ip -br link`. Man kan fortsätta utan
nätverk och ordna det efteråt. `half duplex` i `ethtool <nätverkskort>` är ett varningstecken (dålig kabel eller port).

### Namn på en dator

Värdnamnet är datorns **identitet** i publicomtools (`PUBLICOM_HOST`, annars `hostname`) och ska aldrig behöva ändras (det går inte att byta i admin). Allt beskrivande (plats, roll,
vad den används till) sätts i admin som *Visningsnamn* (`COMPUTER_NAME`), eftersom det ändras över tid när en dator flyttas eller byter profil.

- **Standard: `publicom01`, `publicom02`, …** Löpnummer med två siffror och inledande nolla (färre än 100 datorer), så att sorteringen blir rätt.
- Bara gemener, siffror och bindestreck (det DNS och `hostname` tillåter). Ingen typ eller plats i värdnamnet (inte `publicom-skylt3` eller `publicom-entre`).
- Löpnumret är ett inventarienummer: skriv det på en etikett på datorn och i inventarielistan, så att man vet vilken som är vilken när man står vid den.
- Nästa lediga nummer är det högsta i admin plus ett. Återanvänd aldrig ett nummer för en annan dator.

Sätt namnet vid installationen, så att det blir rätt från början. **Värdnamnet går inte att byta i admin:** det är postens nyckel, och statusrapporter,
besök och tjänststatistik hänger på den. Admin kan bara ändra *label*, ett namn i admin-listan (och *Visningsnamn* i datorns panel), men inte värdnamnet.

- **Befintliga datorer** (t.ex. `gc3`) behåller sitt värdnamn. Ge dem ett beskrivande namn med *label* och *Visningsnamn* i admin. Standarden gäller nya datorer.
- **Byter du ändå värdnamn** på en dator som är installerad: datorn rapporterar då under det nya namnet och dyker upp som en **ny post** i admin, utan
  historik och utan de inställningar som ligger på den gamla posten (profilen sätter du om). Den gamla posten blir tyst och ligger kvar som arkiv.
  Gör det därför bara för en testdator eller en dator vars historik inte behövs.

```bash
sudo hostnamectl set-hostname publicom01
grep -n "<gamla namnet>" /etc/hosts          # ändra raden om den finns
sudo reboot
```

Samtidigt behöver **DNS och DHCP** (KTH:s IT) ändras: posten för det gamla namnet (t.ex. `gc3.lib.kth.se`) ska peka på det nya, annars fungerar inte
`ssh kthb@<dator>`. Datorn hämtar sedan `PUBLICOM_HOST` från publicomtools vid nästa inställningshämtning.

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
  **Den finns inte i admin.** Det är en hemlighet som delas av alla Linux-datorer och som ligger i serverns miljö, så den visas aldrig i gränssnittet. Hämta den så här:
  - **Från en dator som redan fungerar:** `sudo grep '^PUBLICOM_DEVICE_TOKEN=' /usr/local/bin/secrets/.secrets`
  - **Från servern:** i `publicomtools.env` (eller `.env`) i katalogen där publicomtools körs (där `docker-compose.yml` ligger).
  - **Saknas den helt** (ny server): skapa en med `openssl rand -hex 32` och lägg samma värde på servern och i datorns `.secrets`. Byts den på servern måste alla
    datorer få det nya värdet i sin `.secrets`.
  Håll den hemlig: den som har den kan hämta inställningar och rapportera status för alla Linux-datorer (Android-surfplattor har egna tokens). Lägg den inte i git och skicka den inte i chatt eller e-post.
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

- [ ] `systemctl is-failed init.service allowlist_from_ezproxy.service`: båda ska svara `inactive` eller `active`, inte `failed`
- [ ] **En omstart till** ska ge samma resultat **utan** att du gör något för hand. Behöver något köras manuellt efteråt är något fel i inställningarna (se felsökningen nedan)

I admin (senast fem minuter efter första starten):

- [ ] Datorn är **OK** i datoröversikten och har hört av sig de senaste minuterna
- [ ] *Kraschade tjänster* är tom, *Inställningsversion* stämmer med admin och *Kod* visar rätt gren
- [ ] Under *Teknik* stämmer *Det datorn får vid start* med det du förväntar dig

Sist: stäng av start från USB i BIOS igen.

Den fullständiga checklistan för att prova en ny version på riktig hårdvara finns i [Test på riktig dator](hardvarutest.md).

## Felsökning

| Symptom | Sannolik orsak | Kontroll och åtgärd |
|---|---|---|
| Hämtningen av inställningar ger 404 | Datorn finns inte i admin, eller värdnamnet stämmer inte | `hostname` mot admin. Lägg till datorn (steg 1) |
| 401 | Fel `PUBLICOM_DEVICE_TOKEN` | Jämför `.secrets` med servern (steg 4) |
| Datorn rapporterar aldrig | `HEARTBEAT_URL` saknas i inställningarna | *Det datorn får vid start* i admin, lägg till den i grundinställningarna |
| `init.service` faller, "Could not resolve host" | DNS inte uppe vid start | `getent hosts apps.lib.kth.se`, kabel och port. `init.sh` väntar och provar tre gånger |
| Fel eller ingen policy | `POLICY_FILE` saknas eller `init.service` föll | `journalctl -u init.service -b` |
| Skärmen är inte roterad | Inställningen kom efter att sessionen startade | Ny session: omstart, *Hämta nya inställningar nu* eller `sudo pkill -U guest` |
| "Hämta nya inställningar nu" händer inget | Datorn används och väntar (skylt väntar aldrig) | Statusrapportens *Väntar* visar varför; väntar tills den varit ledig i 2 minuter |
| Datorn startar inte efter installationen | Installerad i Legacy, eller Windows Boot Manager först | Avsnittet om UEFI ovan |

**Vad kräver ny session?** Skärmens riktning och andra X-inställningar tas bara med av en ny gästsession (omstart, *Hämta nya inställningar nu* eller `pkill -U guest`).
Spellistor, schema och sidor i skylten läses av skalet och behöver ingen ny session.
