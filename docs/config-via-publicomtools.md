# Config via publicomtools

Plan för att flytta **konfigurationen** för gästdatorerna från statiska filer i GitHub till
publicomtools (databas + admin-UI), medan **koden** ligger kvar i publicom (GitHub) och rullas ut
manuellt. Hemligheter ligger kvar i `.secrets` lokalt på varje dator och hanteras aldrig här.

## Grundprincip

| Del | Var | Hur |
|-----|-----|-----|
| Kod | publicom (GitHub) | Versionshanterad, **manuell** deploy (`install.sh`/`deploy.sh`) |
| Config | publicomtools (DB + admin-UI) | Dynamisk, **device-autentiserad** hämtning vid boot |
| Hemligheter | `.secrets` på datorn | Lokalt, root 600, aldrig i config |

### Varför
- **Admin-UI istället för git push** för att ändra en inställning (`SESSION_IDLE`, `WEBSITES`, rotation …).
- **Autentiserad** hämtning i stället för publika råfiler i GitHub.
- publicomtools har redan grunden: `Computer`-modell, device-auth (`PUBLICOM_DEVICE_TOKEN`), admin-sida
  (KTH-inloggning), statussida.
- **Säkerhetsmässigt bäst av två världar:** koden sprids aldrig automatiskt, och en kapad
  config-källa kan inte köra kod — `load_config` läser `KEY=value` med `printf -v`, aldrig `source`.
  Värsta fall via publicomtools = felaktiga *inställningar*, aldrig RCE.

### Avvägningar
- Config-hämtning beror på att publicomtools är uppe. `safe_download` behåller lokal config vid fel
  → degraderat, inte trasigt.
- Config lämnar git-versionering (blir DB-state) → historik/återställning byggs i DB:n i stället.
- Merge-logiken (`base` + profil + host) flyttar från `build-configs.sh` in i publicomtools.
- Delad device-token: vem som helst med token kan be om vilken hosts config som helst. Configar är
  icke-känsliga, så acceptabelt; löses helt med per-dator-token om det byggs senare.

## Lagring

Hybrid: värden lagras som JSON-blob per lager (enkel lagring), en separat nyckel-katalog ger
metadata för UI och validering.

```prisma
model ConfigLayer {           // base + profiler
  id        String   @id @default(cuid())
  kind      String              // "base" | "profile"
  name      String              // "" för base, "signage"/"search"/… för profil
  values    Json                // { "SESSION_IDLE": "5", "SCREENSAVER": "false", ... }
  updatedAt DateTime @updatedAt
  @@unique([kind, name])
}

model Computer {              // finns redan (heartbeat/status) — utökas
  host            String  @id
  // ...befintliga status-fält...
  profile         String?             // vilken profil datorn ärver
  overrides       Json    @default("{}")  // host-specifika { KEY: "value" }
  configUpdatedAt DateTime?
  configUpdatedBy String?
}

model ConfigKey {            // KATALOG: metadata, inte värden
  key        String  @id     // "SESSION_IDLE"
  type       String          // "int" | "bool" | "string" | "csv" | "url" | "enum"
  enumValues String?         // "searchcomputer,signage,guestcomputer,grouproom"
  help       String?
  example    String?
}

model ConfigChange {         // historik/audit
  id        String   @id @default(cuid())
  target    String            // "base" | "profile:signage" | "host:gc3"
  snapshot  Json              // hela lagrets värden EFTER ändringen
  changedBy String
  changedAt DateTime @default(now())
  note      String?
}
```

### Merge (servern, samma logik som `build-configs.sh`)

```
effektiv(host):
  c   = Computer[host]
  bas = ConfigLayer(base).values
  pro = c.profile ? ConfigLayer(profile, c.profile).values : {}
  return { ...bas, ...pro, ...c.overrides,
           PUBLICOM_HOST: host,
           REMOTE_CONFIG_URL: "<publicomtools>/api/device/config?host=" + host }
```

Samma funktion driver både device-endpointen och admin-förhandsvisningen.

### Serialisering till datorn
Env-format, exakt som dagens `.config` (så `load_config` är oförändrad):
```
KEY="value"
```
- Värden dubbelciteras (t.ex. `WEBSITES` med flera URL:er).
- Inbäddade dubbelcitattecken förbjuds vid validering (håller serialiseringen trivial).

### Validering
Vid sparning valideras lagret mot `ConfigKey`-katalogen:
- Okänd nyckel → varning/blockering (fångar stavfel som i dag skeppas tyst).
- Typ/format → `int`, `bool`, `url`, `enum`.

### Historik
En `ConfigChange`-rad per sparning med hela lagrets JSON-snapshot + vem/när. Ger diff och
återställning (skriv tillbaka en tidigare snapshot). Configar är små → billigt.

## API

`GET /api/device/config?host=<host>` med `Authorization: Bearer <PUBLICOM_DEVICE_TOKEN>`
- Slår upp datorn, mergar lagren, returnerar env-format (`text/plain`).
- Returnerar bara config, aldrig hemligheter.
- Vid okänd host: 404 (datorn behåller då sin lokala config via `safe_download`).

## Klientändring (publicom, minimal)
- `init.sh`: läs `.secrets` (token) först, `host = hostname`, hämta config från publicomtools med
  `curl -H "Authorization: Bearer …"`. `safe_download` behålls (lokal fallback vid fel).
- `load_config` oförändrad.

## Admin-UI (publicomtools, bakom KTH-auth + `ADMIN_EMAILS`)
- Lista datorer (kopplat till statussidan).
- Redigera per dator: profil + overrides. Redigera `base` och profiler.
- Förhandsvisa effektiv config (merge) innan sparning.
- Ändringslogg med diff och återställning.
- Serverside-validering mot katalogen.

## Faser
1. **Modell + endpoint + seed** i publicomtools. Verifiera att endpointen ger identisk config som
   dagens `.config_gc3`.
2. **Peka gc3** på publicomtools-endpointen (`REMOTE_CONFIG_URL`), verifiera hämtning + fallback.
   Övriga datorer orörda (pekar på `main`).
3. **Admin-UI** för redigering + förhandsvisning + historik/diff/återställning.
4. **Migrera övriga datorer** en och en (peka om `REMOTE_CONFIG_URL`), i egen takt.
5. Pensionera `build-configs.sh` + git-configarna när allt är migrerat. Git-`stable` blir då
   enbart för kod (manuell deploy); `main` = utveckling.

## Säkerhet (sammanfattning)
- Config kan inte köra kod (`load_config`) → kapad publicomtools ger fel inställningar, aldrig RCE.
- Hämtning autentiserad (inte publikt läsbar).
- Availability: lokal fallback vid nedtid.
- Hemligheter aldrig i config.
- Admin-UI bakom KTH-auth + `ADMIN_EMAILS`, med validering och ändringslogg.
