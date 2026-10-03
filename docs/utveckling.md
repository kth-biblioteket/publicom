# Utveckling och release

## Grenarna

| Gren | Vem kör den | Hur den ändras |
|---|---|---|
| `stable` | Alla datorer i drift (Ubuntu 24.04) | **Manuell release**: flyttas fram när ändringen är testad på piloten |
| `pilot` | Pilotdatorn gc3 och testdatorer | Ny kod hamnar här först |
| `main` | Den gamla flottan (Ubuntu 22, `.config_*` i roten) | **Fryst.** Ändras inte förrän den sista gamla datorn är ominstallerad |

Varje dator laddar ner koden från sin gren vid varje start (`deploy.sh`). **En push till `stable` är därför en
utrullning till alla datorer** vid deras nästa omstart, och görs medvetet.

Vilken gren en dator kör styrs av inställningen *Programversion (git-gren)* (`PUBLICOM_BRANCH`) i publicomtools,
per dator eller profil. Tom betyder att datorn inte uppdaterar koden alls.

## Arbetsgång

1. Gör ändringen på en egen gren från `pilot`. Kör `tools/check.sh`.
2. Testa i en VM eller på en testdator. För en gren som inte är pushad: installera från lokal kopia, se
   [Installera](installera.md#5-inställningar-och-installation), eller kör `sudo /usr/local/bin/deploy.sh /tmp/publicom`.
3. Merga till `pilot` och pusha. gc3 får ändringen vid nästa omstart. Kontrollera den på gc3 och i admin.
4. **Release:** när piloten är godkänd, flytta `stable` till samma commit:
   ```bash
   git push origin pilot:stable
   ```
   Det måste vara en fast-forward. Gå aldrig förbi `pilot`.
5. Datorerna hämtar ändringen vid nästa omstart. Följ upp i admin (datoröversikten, *Att göra*).

Skydda `pilot` och `stable` på GitHub (kräv granskning, få personer med skrivrätt): datorerna kör koden som root.

## Filer på datorerna

- Allt som installeras står i `files.manifest`: rättigheter, ägare, målsökväg och eventuell källa i repot.
  En ny fil i `files/` måste läggas till där.
- Chromiums grundpolicyer (`policies_*.json`) och skärmsläckarbilderna (`screensaver/`) installeras också via manifestet,
  till `/usr/local/share/publicom/`, så att de alltid följer koden. En ny bild i `screensaver/` måste läggas i manifestet.
- `deploy.sh` validerar allt innan något installeras och skriver bara ändrade filer.

## Ny inställning

En inställning skapas i koden här, och admin får veta om den via katalogen.

1. Skriv koden som läser nyckeln (läs den alltid via `load_config`, aldrig `source`). Bestäm vad som gäller när den inte är satt.
2. Lägg till nyckeln i `config/catalog.json` **i samma commit**: `key`, svenskt `label`, `group`, `type`
   (`bool`, `int`, `string`, `csv`, `url`, `enum`), och vid behov `options`, `unit`, `separator`, `default`,
   `help`, `example`, `advanced` (tekniska inställningar som döljs som standard).
3. `tools/check.sh` kontrollerar att varje nyckel i katalogen läses av koden.
4. I publicomtools: *Inställningskatalog* → **Hämta från stable** efter releasen (eller **Läs in från fil…** med
   `config/catalog.json` innan dess). Granska de nya, ändrade och borttagna nycklarna och uppdatera.
5. Nyckeln syns direkt i formulären, i rätt grupp, som *Inte satt, programmets standard gäller*. Ingen ändring i publicomtools behövs.

En borttagen nyckel raderar inga värden i admin. De visas som *Används inte längre* tills någon tar bort dem.

## Kontroller (CI)

`tools/check.sh` kontrollerar:
- skriptens syntax (och `shellcheck` om det finns), JSON och Electron-koden
- att `load_config` i `install.sh` och `config_lib.sh` är lika
- att `files.manifest` stämmer med `files/`, och att alla skärmsläckarbilder finns i manifestet
- att `/home/guest`-filer behålls av `clean-up.sh`
- inställningskatalogen: att varje nyckel i `config/` finns i katalogen och läses av koden
- (gamla flottan) att `.config_*` är genererade från `config/`

Kör den innan commit. Samma kontroller körs i GitHub Actions (`.github/workflows/ci.yml`). Merga inte till `pilot` eller
`stable` om de misslyckas.

## Gamla flottan

Tills den sista gamla datorn är ominstallerad finns de gamla configfilerna kvar:
`config/base.env`, `config/profiles/`, `config/hosts/` och de genererade `.config_*` i roten (`tools/build-configs.sh`).
De gamla datorerna läser `.config_*` och `policies_*.json` från `main`, därför får **`main` inte ändras**.
När alla är ominstallerade tas filerna bort och `main` kan bli utvecklingsgren igen.
