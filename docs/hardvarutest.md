# Test på riktig dator

Checklista för att testa en ny version (t ex branchen `kandidat-1`) på en riktig dator innan den rullas ut.
Det som går att testa i en VM är redan gjort där. Här testas det som kräver riktig hårdvara: grafik, utskrift,
USB, BIOS/GRUB, ström, nattliga uppdateringar och inloggning mot ref.

Datorn installeras som gästdator med inloggning mot **ref** (`config/hosts/test-hw.env`), med Electron.
Webbinloggning (`LOGIN_UI=web`) och statussidan testas när publicomtools finns på ref.

Kryssa i och skriv anteckningar under varje avsnitt.

## 1. Före besöket

- [ ] Testdator av samma modell som i drift. Modell: ______ Processor: ______ Grafik: ______
- [ ] USB-minne med Ubuntu Server 24.04.x (från ubuntu.com)
- [ ] Externt testkonto i Alma på ref (användarnamn och lösenord)
- [ ] `BOOKING_API_KEY` för ref (bookingsystem-api), VNC-lösenord
- [ ] GRUB-lösenord med **bara a–z och siffror**, och hashen från `grub-mkpasswd-pbkdf2`
- [ ] Kopia av koden (från repot på din dator):
  ```bash
  git archive --format=tar.gz --prefix=publicom/ kandidat-1 > publicom-kandidat-1.tar.gz
  ```
- [ ] En PDF att skriva ut
- [ ] Ett andra USB-minne med en fil på, för att testa att USB är blockerat

Anteckningar:

## 2. På plats: installation

- [ ] BIOS/UEFI enligt [checklistan i README](../README.md#biosuefi-checklista). Tillåt start från USB bara under installationen.
- [ ] Installera Ubuntu Server 24.04 med användaren `kthb` och OpenSSH. IP-adress: ______ Värdnamn: ______
- [ ] SSH fungerar från KTH-nätet: `ssh kthb@<ip>`

Resten av installationen kan göras över SSH, på plats eller på distans:

- [ ] Kopiera och packa upp koden:
  ```bash
  scp publicom-kandidat-1.tar.gz kthb@<ip>:/tmp/
  ssh kthb@<ip> "tar -xzf /tmp/publicom-kandidat-1.tar.gz -C /tmp"
  ```
- [ ] Skapa `/usr/local/bin/secrets/.secrets` enligt README (`VNC_PASSWORD`, `BOOKING_API_KEY`, `GRUB_PASSWORD_HASH`), med ägare root och rättigheter 600
- [ ] Config och installation (datorn startar om när den är klar, det tar en stund):
  ```bash
  sudo mkdir -p /usr/local/bin/config
  sudo cp /tmp/publicom/.config_test-hw /usr/local/bin/config/.config
  sudo PUBLICOM_SRC=/tmp/publicom /tmp/publicom/install.sh
  ```
- [ ] Efter omstarten:
  - `systemctl --failed`: inga kraschade tjänster
  - `lpstat -p -d`: KTH-Print finns och är standard
  - `snap connections chromium | grep cups`: `cups:cups`
  - `sudo ufw status`: bara SSH (22) från `130.237.0.0/16`
- [ ] Stäng av start från USB i BIOS igen

Anteckningar:

## 3. På plats: kontroller

**Uppstart och BIOS**
- [ ] Datorn startar direkt till inloggningsskärmen, utan meny eller text
- [ ] Esc vid start visar GRUB-menyn, och `e` kräver lösenordet (användare `kthb`)
- [ ] BIOS/UEFI kräver lösenord
- [ ] Datorn går inte att starta från installations-USB:n

**Inloggning (ref)**
- [ ] Fel lösenord ger meddelandet om fel användarnamn/lösenord
- [ ] Testkontot ger en session: användarnamn och tid kvar syns i panelen
- [ ] Bokningen syns i bokningssystemet på ref (`https://apps-ref.lib.kth.se/guestcomputers`)

**Grafik och fonter** (kontrollera fonter och PDF, det var skälet till ubuntu-desktop-tricket)
- [ ] Kartan över biblioteket (Wagnerguide) öppnas och går snabbt att använda
- [ ] Webbsidor visas med rätt typsnitt, inga rutor eller saknade tecken (t ex å ä ö, och sidor med andra skriftspråk)
- [ ] En PDF *visas* rätt i Chromium (öppna en PDF i webbläsaren): text syns med rätt typsnitt, inte rutor
- [ ] Skärmsläckaren visar bildspelet, och musen väcker skärmen. Sätt tillfälligt `SCREENSAVER_IDLE=00:01:00` i `/usr/local/bin/config/.config` och kör `sudo systemctl restart guest.service`. Återställ efteråt.

**Utskrift**
- [ ] Ctrl+P visar KTH-Print som förvald skrivare
- [ ] En sida kommer ut på skrivaren, med rätt typsnitt (inte rutor eller fel tecken)
- [ ] Skriv ut en PDF (inte bara en webbsida): utskriften får rätt typsnitt

**Filer och USB**
- [ ] En nedladdad PDF hamnar i Downloads (bokmärket Downloads → Files) utan dialogruta
- [ ] `file:///home/guest/` visar "This page is blocked"
- [ ] Ett USB-minne som sätts i monteras inte och syns inte

**Terminal**
- [ ] Ctrl+Shift+T och kthb-lösenordet ger ett skal
- [ ] Fel lösenord stänger fönstret efter cirka 4 s

**Utloggning och inaktivitet**
- [ ] Logout visar en bekräftelse mitt på skärmen och går tillbaka till inloggningen
- [ ] Nästa session har tom Downloads och ingen historik
- [ ] Efter cirka 4 min utan aktivitet visas en varning i panelen, efter 5 min loggas man ut

**Skärmrotation** (för skyltningsdatorer)
- [ ] `SCREEN_ROTATION=left` i `.config` och `sudo systemctl restart guest.service` ger roterad bild, och mus/touch fungerar rätt. Ta bort raden efteråt.

**Ström**
- [ ] Dra ur strömmen och sätt i den igen: datorn startar av sig själv (om BIOS är inställt för det)

Anteckningar:

## 4. På distans (SSH från KTH-nätet)

- [ ] VNC via tunnel: `ssh -L 5900:localhost:5900 kthb@<ip>`, sedan VNC-klienten mot `localhost:5900`
- [ ] Port 5900 går inte att nå direkt från en annan dator
- [ ] Efter en utloggning visar `tail /var/log/guest_cleanup.log` "API request successful" (bokningen avslutad)
- [ ] Rensning: spara en fil i `/home/guest` med Ctrl+S (i VNC), logga ut och kontrollera att den är borta: `sudo ls -A /home/guest`
- [ ] `sudo /usr/local/bin/deploy.sh /tmp/publicom` ger "0 filer ändrade"

**Dagen efter**
- [ ] `sudo cat /var/log/unattended-upgrades/unattended-upgrades.log`: uppdateringar har körts natten till idag
- [ ] `last reboot`: eventuell omstart skedde ca 03:30
- [ ] `systemctl list-timers 'apt-daily*'` och `snap refresh --time`: nattliga tider
- [ ] `systemctl --failed`: inga kraschade tjänster

**Senare, när publicomtools finns på ref**
- [ ] Heartbeat: `PUBLICOM_DEVICE_TOKEN` i `.secrets`, datorn syns på statussidan
- [ ] Webbinloggning: `LOGIN_UI=web` i `.config`, inloggning, utloggning och att bokningen avslutas

Anteckningar:
