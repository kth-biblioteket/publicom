# Kiosk (pekskärm med förstasida)

Datortypen **Kiosk** (`COMPUTER_TYPE=kiosk`) är för pekskärmar där besökaren väljer bland bibliotekets tjänster.
Den motsvarar Android-appen PubLiKiosk och styrs av samma inställningar. Sökdatorer, gästdatorer och skyltar
påverkas inte.

## Hur det fungerar

`.xinitrc` startar skalet `electron-kiosk` i helskärm (Openbox med `rc-signage.xml`, ingen panel). Skalet körs med
Electron från `electron-login`, så ingen egen installation behövs. Det består av:

- **Förstasidan** med ett stort kort per tjänst (`HOME_MODE=launcher`), eller första tjänsten som hem med de
  övriga som flikar (`HOME_MODE=app`).
- **Sidvyn** som visar tjänsten, och **navigeringsramen** under den: Tillbaka, tjänstens namn och Startsida. Sidorna
  kan inte påverka ramen. Den kan stängas av med `NAVIGATION=false`.
- **Överlägg**: *Är du kvar?* före återställning, *Sidan kan inte öppnas här* med QR-kod (så att besökaren kan
  fortsätta på mobilen) och en felsida när en sida inte kan laddas.
- **Skärmtangentbord** som visas när ett textfält får fokus och fälls ner med *Fäll ner*, vid sökning och vid
  Startsida. Layouter för svenska och engelska (å, ä, ö), siffror och symboler, samt egna layouter för e-post- och sifferfält.
  Knappen längst ner till höger heter *Sök* bara i sökfält (`type="search"`, `role="searchbox"` eller `enterkeyhint`),
  annars *Retur*. Ett fokus som sidan själv sätter när den laddas visar inte tangentbordet.

**Inaktivitet** hanteras av skalet: efter `SESSION_IDLE` minuter utan aktivitet (minus `IDLE_WARNING` sekunder) visas
varningen, sedan rensas sessionen (cookies, cache, historik), språket återställs och förstasidan visas. Varken `xautolock` eller
`restart_x.sh` används. Besöksräkningen (`visit_tracker.py`) fungerar som förut.

## Inställningar

Nyckelkatalogen (`config/catalog.json`), gruppen *Kiosk*: `HOME_MODE`, `APPS`, `LAUNCHER_TITLE`, `LAUNCHER_SUBTITLE`,
`LAUNCHER_FOOTER` (och `_EN`), `START_LABEL`, `START_ICON`, `NAVIGATION`, `LANGUAGE`, `IDLE_WARNING`, samt de vanliga
`SESSION_IDLE`, `PRINTER`, `DOWNLOADS` och `WHITE_LIST` (utan EZproxy-listan, se nedan).

`APPS` har högst sex tjänster. Antingen en JSON-lista:
```
[{"name":"Sök böcker","url":"https://…","icon":"search","scope":"","desc":"…","nameEn":"…","descEn":"…"}]
```
eller en post per rad: `Namn|https://adress/|ikon|område|beskrivning|namn_en|beskrivning_en`. Bara namn och
https-adress krävs. Ikonerna är Lucide: `house`, `search`, `map`, `map-pin`, `calendar`, `book-open`, `library`, `info`,
`circle-help`, `printer`, `monitor`, `user`, `clock`, `graduation-cap`.

Utan `APPS` används `WEBSITES` som tjänster, så att en kiosk utan nya inställningar ändå visar något.

## Förstasidans nederkant

Längst ner kan förstasidan ha ett **informationsfält** (upp till fyra fält) och en **meddelanderad** ovanför. Samma nycklar
som i Android-appen PubLiKiosk, så att publicomtools redigerare delas.

- `LAUNCHER_FIELD_1` till `_4`: en rad `Etikett|typ|värde|Label`. Typ `text` (värdet visas som det står), `url` (värdet är en
  https-adress som svarar med ren text) eller `clock` (klockan, HH:mm; värde behövs inte). Ogiltiga rader (okänd typ, tom text,
  adress som inte är https) ignoreras. Finns något fält döljs textraden `LAUNCHER_FOOTER`.
- `LAUNCHER_MESSAGE`, `LAUNCHER_MESSAGE_EN`: raden ovanför fälten. `LAUNCHER_MESSAGE_URL`: en https-adress som ger texten. Tom
  text från adressen döljer raden, inget svar ger den fasta texten. `LAUNCHER_MESSAGE_STYLE`: `info` (blå), `warning` (gul, standard) eller `alert` (röd).
- `LAUNCHER_MESSAGE_ICON`: ikonen före texten i meddelanderaden: `none` (ingen) eller samma ikoner som `START_ICON` (standard `info`).
  Färgen visar graden, så ikonen kan vara densamma.
- `LAUNCHER_REFRESH`: minuter mellan hämtningarna (1–60, standard 1), bara medan förstasidan visas.

Adresserna hämtas av skalet självt, **bara över https mot en tillåten värd** (en tjänst i `APPS` eller `WHITE_LIST`, så en kiosk som
ska visa text från `apps.lib.kth.se` måste ha den värden i `WHITE_LIST`), utan omdirigeringar, med 5 sekunders tidsgräns, högst
2 kB och högst 300 tecken. Svaret visas alltid som **ren text**, aldrig som HTML. Misslyckas en hämtning ligger den senaste texten
kvar i en timme, därefter visas ett streck (fält) eller den fasta texten (meddelande). De engelska etiketterna (fjärde delen) och
`LAUNCHER_MESSAGE_EN` följer språkknappen.

Korten ovanför behåller sin form: ikonrutan krymper med kortets höjd (minst 48 px) i stället för att klippas.

## Tillåtna webbplatser

Chromium-policyerna (`policies_*.json`) gäller inte Electron. Skalet tillåter bara **https** mot värdar från `APPS` och
`WHITE_LIST` (`allowlist_from_ezproxy.sh` skriver `WHITE_LIST` till `/var/lib/publicom/allowed-hosts.txt`), inklusive
underdomäner. **EZproxy-listan ingår inte** i en kiosk: den har hundratals domäner, även stora delade, och är för bred när besökaren
kan följa länkar. En förlagssida som kiosken ska nå läggs i `WHITE_LIST`. Utan `WHITE_LIST` gäller bara tjänsternas egna värdar. En http-länk till en tillåten värd öppnas som https. Länkar som vill öppna ett nytt fönster
öppnas i samma vy. Allt annat (andra värdar, `file:`, `data:` …) blockeras och visar arket med QR-kod.

## Utskrift, nedladdningar och behörigheter

- **Utskrift** blockeras om inte `PRINTER=true` (Ctrl+P och `window.print()`).
- **Nedladdningar** blockeras om inte `DOWNLOADS=true`. `FILE_DIALOGS` gäller inte kiosker.
- Webbsidor får inga behörigheter (kamera, plats, notiser) och ingen nypzoom.

## Kontrollera på datorn

```bash
journalctl -b -t login_session ; tail -n 20 /tmp/guest_login.log
cat /var/lib/publicom/allowed-hosts.txt
```

## Utveckling

Skalets rena logik (`config.js`, `policy.js`, `idle.js`, `strings.js`) testas med `node --test tools/kiosk-test/skal.test.js`
(körs av `tools/check.sh`). Skalet går att köra i ett fönster på en Mac eller Linux med Electron 39:

```bash
electron files/usr/local/bin/electron-kiosk/main.js --windowed --config provfil.config --hosts /finns/inte
```

`provfil.config` är en vanlig `.config` med `KEY="värde"`-rader. `APPS` som JSON ligger som rå JSON mellan citattecknen.
Se [Hårdvarutest](hardvarutest.md) för checklistan på en riktig dator.

## Inte med i första versionen

Inloggade gäster (Alma) och öppna gäster, fält i iframes är inte provade med riktiga tjänster, och `FILE_DIALOGS`.
