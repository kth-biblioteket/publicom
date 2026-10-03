# Test på riktig dator

Checklista för att testa en ny version (t ex grenen `pilot`) på en riktig dator innan den rullas ut.
Det som går att testa i en VM är redan gjort där. Här testas det som kräver riktig hårdvara: grafik, utskrift,
USB, BIOS/GRUB, ström, nattliga uppdateringar och inloggning mot ref.

Datorn installeras som gästdator med inloggning mot **ref**: inställningarna kommer från publicomtools på
ref (`https://apps-ref.lib.kth.se/publicomtools`) och koden från grenen som testas (normalt `pilot`).
Installationen följer [Installera en dator](installera.md); här står det som skiljer och vad som ska kontrolleras.

Kryssa i och skriv anteckningar under varje avsnitt.

## 1. Före besöket

- [ ] Testdator av samma modell som i drift. Modell: ______ Processor: ______ Grafik: ______
- [ ] USB-minne med Ubuntu Server **24.04.x amd64** (från ubuntu.com). Välj uttryckligen **24.04**,
      inte "senaste LTS" (26.04 räknas nu som senaste och är otestad — bl a CUPS 3.x som tagit bort
      drivrutinsbaserad utskrift). **Server**, inte Desktop. **amd64** (Intel/AMD), inte arm64.
- [ ] Externt testkonto i Alma på ref (användarnamn och lösenord)
- [ ] `BOOKING_API_KEY` för ref (bookingsystem-api), VNC-lösenord
- [ ] GRUB-lösenord med **bara a–z och siffror**, och hashen från `grub-mkpasswd-pbkdf2`
- [ ] Datorn finns i admin på **ref** med profilen *Gästdator* och ref-adresserna (inloggning, bokning,
      publicomtools, statusrapporter). En ny testdator registreras enligt [Installera, steg 1](installera.md#1-förbered),
      med `apps-ref` i adressen.
- [ ] `PUBLICOM_DEVICE_TOKEN` för ref
- [ ] Om grenen inte är pushad: kopia av koden (från repot på din dator):
  ```bash
  git archive --format=tar.gz --prefix=publicom/ <gren> > ~/publicom.tar.gz
  ```
  (`~/` lägger filen i din hemkatalog, inte i repot)
- [ ] En PDF att skriva ut
- [ ] Ett andra USB-minne med en fil på, för att testa att USB är blockerat

Anteckningar:

## 2. På plats: installation

- [ ] BIOS/UEFI enligt [checklistan](installera.md#2-biosuefi). Tillåt start från USB bara under installationen.
- [ ] Installera Ubuntu Server 24.04 med användaren `kthb` och OpenSSH. IP-adress: ______ Värdnamn: ______
- [ ] SSH fungerar från KTH-nätet: `ssh kthb@<ip>`

Resten av installationen kan göras över SSH, på plats eller på distans:

- [ ] Skapa `/usr/local/bin/secrets/.secrets` enligt [Installera, steg 4](installera.md#4-hemligheter) (med ref-token), ägare root och rättigheter 600
- [ ] Inställningar från ref och installation enligt [Installera, steg 5](installera.md#5-inställningar-och-installation),
      med `apps-ref.lib.kth.se` i adressen. För en gren som inte är pushad: kopiera `~/publicom.tar.gz` till `/tmp/` och
      installera från lokal kopia. Datorn startar om när den är klar, det tar en stund.
  (`tee ~/install.log` sparar hela utskriften — den scrollar snabbt förbi. Läs efteråt med
  `less ~/install.log` eller `grep -iE "error|warn|deprecat|fail" ~/install.log`. Kör lokalt vid
  datorn eller i `tmux` över SSH, så överlever installationen ett tappat nätverk.)
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

**Underhållsläge** (vanlig inloggningsprompt vid datorn, se README)
- [ ] Esc → `e`, lägg till `publicom.maintenance` sist på `linux`-raden, Ctrl-X: datorn startar till en textinloggning på tty1 i stället för kiosken (`guest.service` startar inte)
- [ ] Logga in som `kthb`, kontrollera att gästsessionen är avstängd: `systemctl is-active guest.service` ger `inactive`
- [ ] Vanlig omstart (utan parametern) startar kiosken som vanligt igen

**Inloggning (ref)**
- [ ] Fel lösenord ger meddelandet om fel användarnamn/lösenord
- [ ] Testkontot ger en session: användarnamn och tid kvar syns i panelen
- [ ] Bokningen syns i bokningssystemet på ref (`https://apps-ref.lib.kth.se/guestcomputers`)

**Grafik och fonter** (den minimala fontlistan i `install.sh` är standard och verifierad i VM, se att den räcker även på riktig hårdvara)
- [ ] Kartan över biblioteket (Wagnerguide) öppnas och går snabbt att använda
- [ ] Webbsidor visas med rätt typsnitt, inga rutor eller saknade tecken (t ex å ä ö, och sidor med andra skriftspråk)
- [ ] En PDF *visas* rätt i Chromium (öppna en PDF i webbläsaren): text syns med rätt typsnitt, inte rutor
- [ ] Skärmsläckaren visar profilens bilder (inte en testbild), och musen väcker skärmen. Sätt tillfälligt *Starta skärmsläckaren efter* till `00:01:00` på datorn i admin och starta om tjänsterna enligt [Drift](drift.md#vad-som-händer-vid-start). Återställ efteråt.

**Utskrift**
- [ ] Med *Utskrift* av i admin gör Ctrl+P ingenting; med den på visar Ctrl+P KTH-Print som förvald skrivare
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
- [ ] *Skärmens riktning* Stående (vänster) på datorn i admin, och omstart, ger roterad bild, och mus/touch fungerar rätt. Använd ärvt värde efteråt.

**Ström**
- [ ] Dra ur strömmen och sätt i den igen: datorn startar av sig själv (om BIOS är inställt för det)

Anteckningar:

## 4. På distans (SSH från KTH-nätet)

- [ ] VNC via tunnel: `ssh -L 5900:localhost:5900 kthb@<ip>`, sedan VNC-klienten mot `localhost:5900`
- [ ] Port 5900 går inte att nå direkt från en annan dator
- [ ] Efter en utloggning visar `tail /var/log/guest_cleanup.log` "API request successful" (bokningen avslutad)
- [ ] Rensning: spara en fil i `/home/guest` med Ctrl+S (i VNC), logga ut och kontrollera att den är borta: `sudo ls -A /home/guest`
- [ ] `sudo /usr/local/bin/deploy.sh /tmp/publicom` (eller en omstart) ger "0 filer ändrade"

**Dagen efter**
- [ ] `sudo cat /var/log/unattended-upgrades/unattended-upgrades.log`: uppdateringar har körts natten till idag
- [ ] `last reboot`: eventuell omstart skedde ca 03:30
- [ ] `systemctl list-timers 'apt-daily*'` och `snap refresh --time`: nattliga tider
- [ ] `systemctl --failed`: inga kraschade tjänster

**Publicomtools på ref**
- [ ] Datorn är OK i datoröversikten, utan *Gamla configfiler*, och *Teknik* visar rätt inställningar
- [ ] En ändring i admin (t ex *Utskrift*) slår igenom efter omstart, och *Väntar på omstart* försvinner
- [ ] Webbinloggning: *Inloggningsskärm* Webbversion i admin, inloggning, utloggning och att bokningen avslutas

Anteckningar:
