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
`restart_x.sh` används. Besöksräkningen (`visit_tracker.py`) fungerar som förut och skickar dessutom vilka tjänster som användes (se Besöksstatistik nedan).

## Inställningar

Nyckelkatalogen (`config/catalog.json`), gruppen *Kiosk*: `HOME_MODE`, `APPS`, `LAUNCHER_TITLE`, `LAUNCHER_SUBTITLE`,
`LAUNCHER_FOOTER` (och `_EN`), `LAUNCHER_PER_PAGE`, `START_LABEL` (och `_EN`), `START_ICON`, `NAVIGATION`, `LANGUAGE`, `IDLE_WARNING`, samt de vanliga
`SESSION_IDLE`, `PRINTER`, `DOWNLOADS` och `WHITE_LIST` (utan EZproxy-listan, se nedan).

`APPS` har högst 36 tjänster (i appläget sex). `LAUNCHER_PER_PAGE` (2, 4, 6, 8, 10 eller 12, standard 4) bestämmer hur många
som visas samtidigt; korten anpassar kolumner, rader och storlek efter antalet och skärmen (rutor eller breda rader, beskrivningen
döljs när korten blir små). Finns det fler tjänster blir det flera sidor med prickar under, som besökaren sveper mellan (med mus
räcker det att dra). Startsida går tillbaka till första sidan.
Antingen en JSON-lista:
```
[{"name":"Sök böcker","url":"https://…","icon":"search","scope":"","desc":"…","nameEn":"…","descEn":"…","urlEn":"https://…"}]
```
eller en post per rad: `Namn|https://adress/|ikon|område|beskrivning|namn_en|beskrivning_en|adress_en`. Bara namn och
https-adress krävs. Den engelska adressen (`urlEn`, åttonde delen) öppnas när besökaren valt English; är den tom eller inte https används den vanliga. Dess värd tillåts också. Ikonerna är Lucide version 1.48.0 (lucide.dev/icons, ISC): alla 2 118 namn, också de äldre aliasen (`circle-help`, `building-2`,
`book-marked`), används för tjänsternas `icon`, `START_ICON` och meddelandets ikon. Ikonerna ligger oförändrade i `icons.js` (genererad av
`tools/build-icons.js` ur paketet `lucide-static`; licensen i `icons-LICENSE.txt`), inget hämtas i drift. Ett okänt eller tomt namn ger `info`.

Utan `APPS` används `WEBSITES` som tjänster, så att en kiosk utan nya inställningar ändå visar något.

## Skalning

Skalets sidor (förstasidan, navigeringen, tangentbordet och överlägget) är ritade för **1280 px bredd när skärmen ligger** och **800 px när den
står** (höjden större än bredden) och skalas med skärmens bredd, som i PubLiKiosk. På en 1920 px bred liggande skärm blir navigeringsfältet
alltså 88 × 1,5 = 132 px högt med 90 px knappar. Zoomen på tjänsternas sidor (`INITIAL_SCALE`) är en egen sak.

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

## Zoom

`INITIAL_SCALE` (procent, 10–500, standard 100) sätter zoomen på tjänsternas sidor, utöver skalningen av skalets egna sidor. Vid
140 % har en tjänst ungefär 71 % så många CSS-pixlar att fylla, så responsiva sidor visar sin smalare layout. Zoomen sätts om efter
varje laddning, och nypzoom är avstängd. Förstasidan, navigeringen, tangentbordet och överlägget påverkas inte.

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

## Navigeringen och dialogerna på två språk

Som i PubLiKiosk visar ramen och dialogerna svenska och engelska samtidigt, utan språkknapp. Varje knapp har svenska fet överst och
engelska mindre och ljusare under; varje rad kortas för sig med … när den inte ryms, och engelskan utelämnas när den saknas eller
är lika med svenskan. Tillbaka heter Tillbaka / Back, startknappen Startsida / Home page (förstasidan) eller Hem / Home (första
tjänsten är hem); en egen `START_LABEL` visas på en rad, eller med engelska raden under om `START_LABEL_EN` är satt (en `START_LABEL_EN` utan `START_LABEL` ersätter bara engelska raden). Flikarnas engelska namn är tjänstens `nameEn`.

Måtten ges för en skärm 1280 bred liggande eller 800 stående och skalas efter fönstrets bredd. Liggande ramen är 88 hög med knappar 60
höga och ikonen till vänster. Stående, eller med fler än fem knappar (Hem och fler än fyra tjänster som flikar), är ramen 116 hög med knappar 88 höga
och ikonen ovanför texten; Tillbaka är då 88 bred och övriga knappar lika breda. Dialogerna (Är du kvar?, Sidan kan inte öppnas här,
felsidan) har rubrik och brödtext på båda språken. Förstasidans egen språkknapp och korten är oförändrade.

## Fotrad som webbsida och attract loop

Två vyer som visar en hel webbsida. De är isolerade i `sandboxed-page.js`: ingen brygga mot skalet, ingen navigering (länkar,
omdirigeringar och nya fönster nekas), egen session utan delade kakor, inga behörigheter eller nedladdningar, ingen nypzoom, och
JavaScript bara om `*_JS` är på. Sidan och dess delresurser (bilder, film, typsnitt, skript) hämtas bara över https från tillåtna
värdar (`APPS`, `WHITE_LIST`); sidans egen värd måste alltså finnas där. Film utan ljud startar av sig själv, film med ljud gör det inte.

- **Fotrad** (`LAUNCHER_HTML_URL`, `_HEIGHT` 40–400 standard 100, `_JS`, `_TOUCH`): ersätter informationsfälten längst ner på
  förstasidan. Meddelanderaden ligger kvar ovanför. Går sidan inte att ladda (nätfel eller http-svar 400 eller högre) visas
  fälten som förut. Sidan ritas för 1280 pixlar bred (liggande) eller 800 (stående) och skalas efter fönstrets bredd, som övriga sidor.
  Tryck på fotraden gör inget om inte `LAUNCHER_HTML_TOUCH` är på. Sidan laddas om var `LAUNCHER_REFRESH`:e minut.
- **Attract loop** (`ATTRACT_URL`, `ATTRACT_AFTER` sekunder, standard 120, 0 = av, `ATTRACT_REFRESH` minuter, standard 10,
  `ATTRACT_JS`): när förstasidan står orörd så länge visas sidan i helskärm över den (aldrig i en tjänst, inte i appläget).
  Första trycket tar bort den, går inte vidare till något under och är ingen annan åtgärd; skalets inaktivitetsklocka startar bara om.
  Går sidan inte att ladda visas förstasidan som vanligt. När en tjänst öppnas släpps sidan, så att film och skript stannar.

## Besöksstatistik per tjänst

Varje besök i statusrapporten (`visits`) får på kiosker ett valfritt fält `apps`: `[{ "url": …, "name": …, "s": sekunder }]`, högst 36, flest
sekunder först. Kiosken skriver varje byte av aktiv tjänst (epoch-sekund, tjänstens adress enligt `APPS` och namn, tom när förstasidan visas)
till `/run/publicom-guest/app-usage` (en rad per byte, filen skrivs om atomiskt och begränsas till de senaste tre dygnen). Katalogen skapas av `/etc/tmpfiles.d/publicom-guest.conf` (ägare guest, 0700; `deploy.sh` kör `systemd-tmpfiles --create` vid varje start). `visit_tracker.py` läser den när ett
besök slutar, klipper tiden till besökets start och slut (slut = sista aktiviteten), summerar per tjänst och lägger `apps` på besöket. Hem-fliken i appläget
räknas som första tjänsten; tid på förstasidan räknas inte. Bara tjänstens vanliga adress (inte den engelska) och namn sparas, aldrig sidor eller andra
adresser. Eftersom gästen skriver filen och trackern läser den som root öppnas den utan att följa länkar och utan att blockera, och måste vara en vanlig fil som ägs av `guest` utan fler hårda länkar och högst 256 kB; annars skickas besöket utan `apps`. Besök utan uppgifter får inget `apps`. Gäst- och sökdatorer ändras inte.

## Skylt

Skyltar (`COMPUTER_TYPE=signage`) körs av kioskskalet (utan inmatning). Sidorna visas i tur och ordning i helskärm:

- **Spellistor:** `SIGN_PAGES` är standardlistan, en JSON-lista `[{"url":"https://…","s":30}]` (eller en rad per sida, `adress|sekunder`). `s` är sekunder; saknas
  den gäller `SIGN_SECONDS` (standard 30, 5–3600). Tom standardlista visar första Startsidan. Sidornas värdar tillåts automatiskt.
- **Schema (`SIGN_SCHEDULE`):** väljer spellista efter tid: `{"lists":{"Dag":[…]},"slots":[{"list":"Dag","days":[1,2,3,4,5],"from":"08:00","to":"19:00"},{"list":"Bokrea","dates":["2026-10-20","2026-10-31"]}],"off":false}`.
  Veckodagar 1–7 (måndag–söndag), `from` ingår och `to` ingår inte (`24:00` är midnatt), `dates` är första och sista dag (båda ingår), och ett saknat fält gäller alltid. En rad med
  okänd lista eller `from` senare än `to` hoppas över. Av raderna som gäller just nu vinner den första med `dates`, annars den första utan. Gäller ingen rad (eller är listan tom)
  används `SIGN_PAGES`, och är `off` satt och ingen rad gäller blir skärmen svart. Enhetens lokala tid; schemat kontrolleras minst varje minut och vid byte av lista börjar skylten direkt på listans första sida.
  Saknas schemat eller går det inte att läsa används bara `SIGN_PAGES`.
- **Förladdning:** med flera sidor laddas nästa sida i en egen vy bakom den som visas, 10 sekunder före bytet (kortare om sidan visas kort tid), så att dess
  skript hinner rita klart. Bytet sker först när den nya sidan är laddad och haft 1,5 sekund på sig (högst 10 sekunders väntan), och den gamla vyn släpps efteråt.
- **Bara visa:** all inmatning ignoreras (inga klick, ingen scrollning, inget tangentbord) och länkar följs inte. Omdirigeringar till tillåtna värdar följs.
  `SIGN_JS` (standard på) styr JavaScript. Sidor kan vara uppladdade bilder, filmer och pdf-sidor som admin lagt hos publicomtools (vanliga adresser); okända fält i en sidpost ignoreras.
  `SIGN_RESOURCES` (standard `all`) styr varifrån delresurser (skript, stilmallar, typsnitt, bilder, anrop, film) får hämtas: `all` från vilken https-adress som helst, `allowed` bara från tillåtna
  webbplatser (`WHITE_LIST`, sidornas värdar). Själva sidan och omdirigeringar av den följer alltid tillåtna värdar, och navigering, nya fönster, nedladdningar och behörigheter nekas.
- **Felsida:** går en sida inte att ladda (nätverksfel eller http-svar 400 eller högre) visas en felsida utan knappar, och sidan laddas om av sig själv var 30:e
  sekund. Rotationen går vidare till nästa sida i vanlig tid.
- **Storlek:** sidorna ritas för skärmens verkliga storlek (`INITIAL_SCALE` gäller), inte för 1280 eller 800 pixlar som kioskens egna sidor.
- En enda sida laddas om med `SESSION_IDLE` minuters mellanrum (som den gamla skylten). Skyltar räknar inga besök.
- Skylten körs alltid av kioskskalet (ingen Chromium-reserv längre). Felsökning: `KIOSK_LOG_BLOCKED=1` loggar blockerade begäranden.

Kioskens egna inställningar (förstasida, tjänster, navigering, fotrad, attract loop) gäller inte skyltar.

## Vilka inställningar gäller vilken datortyp

Varje nyckel i `config/catalog.json` kan ha `types`: en lista över datortyperna (värdena i `COMPUTER_TYPE`) där den har någon betydelse. Saknas `types` gäller nyckeln alla.
Publicomtools döljer nycklar som inte gäller profilens datortyp (med ett val att visa alla). Grupprumsdatorer är sökdatorer. `tools/check.sh` kontrollerar att
bara kända datortyper används och att gruppen *Skylt* bara gäller skylt.
