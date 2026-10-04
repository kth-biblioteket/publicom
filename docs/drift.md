# Drift

## Vad som händer vid start

Vid varje start kör `init.service` skriptet `init.sh`:

1. **Inställningarna** hämtas från publicomtools (`REMOTE_CONFIG_URL`, med `PUBLICOM_DEVICE_TOKEN`) och sparas i
   `/usr/local/bin/config/.config`. Om hämtningen misslyckas behålls den förra filen.
2. **Koden** hämtas av `deploy.sh` från GitHub-grenen i `PUBLICOM_BRANCH` (`stable`, eller `pilot` på gc3). Allt
   valideras (syntax, JSON) innan något installeras, och bara ändrade filer enligt `files.manifest` skrivs. Om
   grenen inte går att hämta eller något är fel ändras **ingenting**. Med `PUBLICOM_BRANCH` tom uppdateras koden inte alls.
3. **Skärmsläckarbilderna** i `SCREENSAVER_FILES` kopieras från `/usr/local/share/publicom/screensaver/` (de följer
   med koden). En tom lista ger KTH-bakgrunden. Saknas en bild lokalt hämtas den från GitHub; misslyckas det ändras ingenting.
4. **Chromiums grundpolicy** (`POLICY_FILE`) kopieras från `/usr/local/share/publicom/policies/` (följer med koden).

Sedan bygger `allowlist_from_ezproxy.service` den slutliga policyn utifrån inställningarna, och sist startar
`guest.service` (gästsessionen). **Ändrade inställningar gäller alltså från nästa omstart.**

Inställningarna har en version (`PUBLICOM_CONFIG_VERSION`). När en gästsession startar sparar `login_session.sh`
den i `/var/lib/publicom/config-version` och skickar en statusrapport direkt. I admin visas *Väntar på omstart*
tills datorns session kör samma version som admin visar (under *Teknik*: *Inställningsversion*).

**Utan omstart, från admin:** på en dator som *väntar på omstart* finns knappen **Hämta nya inställningar nu**.
Datorn får beskedet med nästa statusrapport (inom 5 minuter). `heartbeat.sh` startar då `publicom-reload.service`
(`reload_config.sh`), som väntar tills ingen använder datorn (ingen inloggad och ingen aktivitet på 2 minuter, högst
8 timmar) och sedan kör stegen ovan och startar en ny gästsession. Högst en gång per kvart. Följ det med
`journalctl -t publicom-reload`.

**Starta om från admin:** knappen **Starta om datorn…** på datorsidan. Samma väg: beskedet når datorn med nästa
statusrapport, `publicom-reboot.service` (`reload_config.sh reboot`) väntar tills ingen använder datorn och startar
sedan om den. Högst en gång per halvtimme. Begäran räknas som utförd när datorn har startat om efter den.

Utan omstart, för hand via SSH (avslutar en pågående gästsession):
```bash
sudo systemctl restart init.service allowlist_from_ezproxy.service && sudo systemctl restart guest.service
```
Några inställningar gäller bara vid installation: *SSH tillåts från* och *Försättsblad*.

Status för senaste deploy: `cat /var/lib/publicom/deployed` och `journalctl -u init`.

## Inställningarna

Inställningarna ändras i publicomtools, under *Datorer*, *Profiler* och *Grundinställningar*:

- **Grundinställningar** gäller alla datorer.
- **Profilen** (Sökdator, Gästdator, Grupprum, Skylt …) ändrar dem för en sorts dator.
- **Datorn** kan ha egna värden för enstaka inställningar.

Formuläret visar varifrån varje värde kommer, och granskningen visar vilka datorer en ändring påverkar. Alla
ändringar loggas och kan ångras. Datorn får den sammanslagna listan som `KEY="value"`-rader. Den läses med
`load_config` (`config_lib.sh`), som aldrig kör filen, så felaktiga inställningar kan aldrig köra kod.

Vilka inställningar som finns, med typ, enhet och standardvärde, står i `config/catalog.json` och i
publicomtools under *Inställningskatalog*. Se [Utveckling](utveckling.md#ny-inställning) för hur en ny läggs till.

## Webbläsarens regler

Chromium-policyn byggs i två steg vid varje start:

1. **Grundpolicyn** (`policies_search.json` eller `policies_guest.json`, inställningen *Webbläsarpolicy*) följer med koden.
2. **`allowlist_from_ezproxy.sh`** lägger på det som inställningarna styr, åt båda hållen:
   - *Utskrift* (`PRINTER`), *Tillåt nedladdningar* (`DOWNLOADS`), *Spara och välja filer* (`FILE_DIALOGS`)
   - **Gästdatorer med inloggning** (`ALMA_LOGIN=true`): inga webbplatser spärras, bara `file://` utom Chromiums egen katalog.
   - **Öppna gästdatorer** (allt som inte är sökdator eller skylt, med `ALMA_LOGIN=false`): *Tillåtna webbplatser* plus bibliotekets
     databaser från EZproxy-listan (`kth-biblioteket/ezproxy/db_stanzas.txt`, privat repo). Listan hämtas från publicomtools
     (`/api/device/ezproxy-stanzas`) med `PUBLICOM_DEVICE_TOKEN`; tokenen till ezproxy-repot finns bara på servern. Misslyckas
     hämtningen används senaste kopian i `/var/cache/publicom/db_stanzas.txt`.
   - **Sökdatorer, grupprum och skyltar**: bara *Tillåtna webbplatser*, allt annat spärras.
   - För alla: `localhost` (CUPS, VNC), helskärm och tillägg spärras.

Kontrollera på datorn:
```bash
jq '{PrintingEnabled, DownloadRestrictions, AllowFileSelectionDialogs, URLAllowlist}' /var/snap/chromium/current/policies/managed/policies.json
```
I Chromium visar `chrome://policy` vilka regler som gäller.

## Inloggning i Chromium (LOGIN_UI=web)

På gästdatorer med inloggning kan inloggningsskärmen visas som en webbsida i publicomtools i stället för i
Electron-appen. Väljs med *Inloggningsskärm* (`LOGIN_UI`): `electron` (standard) eller `web`.

1. När sessionen startar hämtar `login_session.sh` (root, `guest.service` ExecStartPre) en engångsbiljett från publicomtools
   och installerar en **inloggningspolicy** där allt är blockerat utom publicomtools och formuläret för att registrera konto.
2. `.xinitrc` visar inloggningssidan i Chromium i kioskläge.
3. Inloggningen (Alma) och bokningen görs av publicomtools. `login_agent.sh` (root) frågar publicomtools varannan sekund.
   När någon har loggat in installerar den gästpolicyn igen och skriver bokningen till `/run/publicom/session.json`.
4. `.xinitrc` stänger inloggningssidan och startar sessionen i en ny Chromium med ny profil.
5. Vid utloggning ber `session_cleanup.sh` publicomtools avsluta bokningen. API-nyckeln till bokningssystemet finns bara på servern.

Kräver `PUBLICOMTOOLS_URL` i inställningarna och `PUBLICOM_DEVICE_TOKEN` i `.secrets`. **Svarar publicomtools inte används
Electron som reserv**, därför ska `BOOKING_API_KEY` finnas kvar i `.secrets` så länge Electron finns som reserv.

Kontrollera: `journalctl -t publicom-login -n 10` och `journalctl -u publicom-login-agent`.

## Gästens filer

Inget som en gäst har sparat får finnas kvar till nästa användare.

- `clean-up.sh` (vid sessionsstart och utloggning) tar bort allt i `/home/guest` utom det som `files.manifest` installerar
  och det som sessionen behöver (`KEEP_HOME`, `KEEP_CONFIG` i skriptet). Chromiums hemkatalog i snap töms.
- `session_cleanup.sh` (root, efter sessionen) tömmer Chromiums privata `/tmp`.
- En ny fil i `/home/guest` måste läggas till i `KEEP_HOME`/`KEEP_CONFIG`, annars tas den bort vid varje session. `tools/check.sh` kontrollerar det.

## Statussidan (heartbeat)

Varje dator skickar status till publicomtools var 5:e minut (`heartbeat.sh` via `heartbeat.timer`): senaste deploy,
uptime, om gästsessionen körs, kraschade tjänster, ledigt diskutrymme och om en omstart väntar. Admin visar det i
klartext under *Att göra*.

- Adressen är *Adress för statusrapporter* (`HEARTBEAT_URL`), token är `PUBLICOM_DEVICE_TOKEN`. Utan token skickas ingenting.
- Datorn identifieras med `PUBLICOM_HOST` (värdnamnet i admin), som publicomtools skickar med i inställningarna.
- Kontrollera: `journalctl -u heartbeat.service -n 5`. Skicka direkt: `sudo systemctl start heartbeat.service`.

## Automatiska uppdateringar

- **Säkerhetsuppdateringar** installeras av `unattended-upgrades` (bara `-security`): paketlistor ca 01:30, installation ca 02:30.
- Kräver en uppdatering omstart startar datorn om **kl. 03:30**, även med gästsessionen igång.
- **Chromium (snap)** uppdateras bara mellan 02:00 och 04:00.
- Datorn behöver vara påslagen på natten. Är den avstängd körs uppdateringen när den startas, och en eventuell omstart sker natten efter.
- Senaste körningen: `/var/log/unattended-upgrades/unattended-upgrades.log`.

## Fjärråtkomst

- `install.sh` slår på `ufw`: allt inkommande nekas utom SSH (port 22) från *SSH tillåts från* (standard `130.237.0.0/16`).
- VNC lyssnar bara lokalt (`x11vnc -localhost`). Anslut via SSH-tunnel och peka VNC-klienten mot `localhost:5900`:
  ```bash
  ssh -L 5900:localhost:5900 kthb@<dator>
  ```
- **Terminal i gästsessionen:** Ctrl+Shift+T öppnar `xterm` med `su -l kthb`, så den kräver kthb-kontots lösenord. Fel lösenord
  stänger fönstret efter 4 s (`pam_faildelay`). Kontot låses aldrig.

## Underhållsläge och GRUB

`install.sh` döljer GRUB-menyn, tar bort recovery-poster och startar tyst. Med `GRUB_PASSWORD_HASH` kräver det lösenord
(användare `kthb`) att ändra menyposter eller använda GRUB:s kommandorad. Kontrollera:
```bash
sudo grep -E "^set superusers|^menuentry" /boot/grub/grub.cfg
```

Normalt finns ingen textinloggning på datorn. För att få en vid datorn, t ex om gästsessionen är trasig:

1. Håll **Esc** vid uppstart för att visa GRUB-menyn.
2. Tryck **`e`** på den vanliga menyposten och ange GRUB-lösenordet.
3. Lägg till ` publicom.maintenance` sist på raden som börjar med `linux`.
4. Tryck **Ctrl-X**.

Datorn startar då utan gästkiosken och ger en textinloggning på tty1 (`publicom-maintenance-login.service`).
Nästa vanliga omstart är oförändrad.

## Felsökning

| Symptom | Titta på |
|---|---|
| Inställning i admin har inte slagit igenom | Har datorn startat om? *Väntar på omstart* i admin. `journalctl -b -u init.service` |
| Webbläsaren tillåter/spärrar fel | `chrome://policy`, `journalctl -b -u allowlist_from_ezproxy` |
| Skärmsläckaren visar fel bilder | `ls /usr/local/bin/screensaver/`, *Bilder i skärmsläckaren* i admin |
| Ny kod har inte kommit ut | `cat /var/lib/publicom/deployed`, `PUBLICOM_BRANCH` i admin, `journalctl -b -u init.service \| grep -i deploy` |
| Datorn syns inte i admin | `journalctl -u heartbeat.service -n 5`, `PUBLICOM_DEVICE_TOKEN` i `.secrets` |
| Gästsessionen startar inte | `systemctl status guest.service`, `systemctl --failed`, underhållsläge |
