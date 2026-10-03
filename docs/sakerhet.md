# Säkerhet

Vad en angripare kan göra och vad som skyddar mot det.

## Görs automatiskt av install.sh och deploy.sh

- **Inställningarna kan inte köra kod.** `.config` läses med `load_config` (`config_lib.sh`) i stället för `source`.
  En kapad publicomtools kan ge fel inställningar, men aldrig köra kod på datorn.
- **Inställningarna hämtas autentiserat** från publicomtools med `PUBLICOM_DEVICE_TOKEN`, inte som publika filer.
- **Chromium-policyn** (`allowlist_from_ezproxy.sh`): blockerar `file://` utom Chromiums egen katalog, blockerar
  `localhost`/`127.0.0.1`/`[::1]` (datorns CUPS 631 och VNC 5900), stänger av helskärm (F11), tillägg och
  utvecklarverktyg. Öppna gästdatorer, sökdatorer, grupprum och skyltar har en lista över tillåtna webbplatser.
  Grundpolicyn följer koden, så en GitHub-gren som inte nås kan inte låsa kvar en gammal policy.
- **CUPS:** webbgränssnittet av, ingen jobbhistorik eller sparade filer (alla gäster är användaren `guest`).
- **Gästens hem rensas** vid varje session (`clean-up.sh`). Chromium kör inkognito med ny profil.
- **Inga terminalprogram eller inställningspaneler.** Avahi och Bluetooth av. cron/at bara för root och kthb.
- **Brandvägg:** bara SSH från *SSH tillåts från*. VNC bara via SSH-tunnel. USB-lagring blockerad.
- **Automatiska säkerhetsuppdateringar**, med omstart 03:30 vid behov.
- **Inga GitHub-tokens på datorerna.** EZproxy-listan (privat repo) hämtas via publicomtools.

## Måste göras för hand

- **BIOS-lösenord, avstängd USB- och nätverksstart, GRUB-lösenord** ([Installera](installera.md#2-biosuefi)).
  Utan det kan man starta från USB och läsa `.secrets` och disken. Överväg diskkryptering och chassilås.
- **GitHub:** datorerna kör kod från `stable` (gc3 från `pilot`) som root vid varje start. Skydda grenarna
  (kräv granskning), kräv 2FA, ge skrivrätt till få personer.
- **SSH:** begränsa *SSH tillåts från* till admin-nätet, använd nycklar (lösenord som reserv). `kthb` spärras aldrig
  (medvetet), så gärna fail2ban som spärrar IP-adresser.
- **Bokningsnyckeln:** `BOOKING_API_KEY` ger skrivrätt i bokningssystemet och ligger på gästdatorer med Electron.
  Med webbinloggningen (`LOGIN_UI=web`) finns nyckeln bara på servern.
- **Delad device-token:** alla datorer har samma `PUBLICOM_DEVICE_TOKEN`. Den som har den kan hämta vilken dators
  inställningar som helst och skicka status i dess namn. Inställningarna är inte hemliga, men en token per dator vore bättre.
- **EZproxy-token** (`EZPROXY_GITHUB_TOKEN` i publicomtools): fine-grained, endast *Contents: Read* på `kth-biblioteket/ezproxy`.
  Den nuvarande (`publiccomputers`, användaren "kthbiblioteket") **går ut 23 november 2026**. Förnya i god tid.
- **Nät:** lägg publika datorer i ett eget nät (VLAN), så att interna tjänster inte nås bara för att trafiken kommer från KTH-nätet.

## Efterkontroll på datorn

```bash
sudo stat -c '%a %U' /usr/local/bin/secrets/.secrets   # 600 root
sudo grep -r NOPASSWD /etc/sudoers.d/                   # inget för guest
sudo grep -i '^WebInterface' /etc/cups/cupsd.conf       # No
sudo ufw status                                         # bara 22 från SSH_ALLOW_FROM
```
