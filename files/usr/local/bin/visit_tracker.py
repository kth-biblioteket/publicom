#!/usr/bin/env python3
"""Besök för användningsstatistiken i publicomtools.

Ett besök = från första riktiga tangent-, mus- eller pekhändelsen till den sista innan datorn varit
orörd i SESSION_IDLE minuter, eller innan besökaren loggade ut / tiden tog slut. Den inaktiva tiden
på slutet räknas inte.

Läser händelserna direkt från /dev/input (kärnan), inte X-serverns räknare för inaktivitet: den
nollställs också av programvara (skärmsläckaren, Chromium som spelar video, omstarter), vilket gav
besök på orörda datorer. Ett besök kräver dessutom aktivitet i minst två intervall om 5 sekunder.

Avslutade besök läggs i VISITS_FILE (en JSON-rad per besök) och skickas med nästa statusrapport
(heartbeat.sh), som tar bort dem när publicomtools har tagit emot dem. Inga användare, tangenter
eller adresser sparas, bara tider.

På kiosker (COMPUTER_TYPE=kiosk) får varje besök också apps: vilka tjänster som användes och hur många sekunder var.
Kiosken (electron-kiosk, usage.js) skriver varje byte av aktiv tjänst till APP_USAGE_FILE; här klipps tiden till besökets
start och slut och summeras per tjänst. Bara tjänstens konfigurerade adress och namn, tid på förstasidan räknas inte.

Körs av visit-tracker.service som root (krävs för /dev/input). Gör ingenting på skyltar.
"""

import fcntl
import glob
import json
import os
import re
import select
import struct
import sys
import time

CONFIG_FILE = "/usr/local/bin/config/.config"
VISITS_FILE = "/var/lib/publicom/visits.jsonl"
# Skrivs av logout_timer.sh (timeout) och logout_and_cancel.sh (logout) innan X avslutas
REASON_FILE = "/tmp/publicom-end-reason"
MAX_QUEUED = 500
# Skrivs av kiosken (guest) vid varje byte av tjänst: JSON-rader {t, url, name}, tomma url/name = förstasidan
APP_USAGE_FILE = "/tmp/publicom-app-usage"
MAX_APPS_PER_VISIT = 36
TICK = 5
RESCAN_EVERY = 30
MIN_ACTIVE_TICKS = 2

# struct input_event: struct timeval (två long), __u16 type, __u16 code, __s32 value
EVENT = struct.Struct("llHHi")
EV_KEY, EV_REL, EV_ABS = 1, 2, 3
# Enheter som skickar tangenthändelser utan att någon använder datorn
IGNORED_DEVICES = re.compile(r"Video Bus|Power Button|Sleep Button|Lid Switch|PC Speaker|HDA |HDMI|Headphone|WMI", re.I)


def log(message):
    print(message, flush=True)


def load_config(path):
    """KEY=value-rader som config_lib.sh läser dem (ett lager citattecken runt värdet tas bort)."""
    values = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line.rstrip("\n"))
                if m:
                    val = m.group(2)
                    # Bara ett lager, som load_config: citattecken i själva värdet behålls
                    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                        val = val[1:-1]
                    values[m.group(1)] = val
    except OSError:
        pass
    return values


def device_name(path):
    try:
        with open(f"/sys/class/input/{os.path.basename(path)}/device/name", encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def open_devices(current):
    """Öppna nya indataenheter (t ex en mus som kopplats in) och stäng de som försvunnit."""
    paths = set(glob.glob("/dev/input/event*"))
    for path in list(current):
        if path not in paths:
            os.close(current.pop(path))
    for path in paths - set(current):
        if IGNORED_DEVICES.search(device_name(path)):
            continue
        try:
            current[path] = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            pass
    return current


def read_app_events(path=APP_USAGE_FILE):
    """Händelserna som kiosken skrev, sorterade på tid: [(t, url, name)]. Tom lista om filen saknas eller är trasig."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)  # filen ägs av gästen: följ inga länkar
        with os.fdopen(fd, encoding="utf-8", errors="replace") as f:
            data = f.read(1_000_000)
    except OSError:
        return []
    events = []
    for line in data.splitlines():
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if not isinstance(o, dict):
            continue
        t, url, name = o.get("t"), o.get("url", ""), o.get("name", "")
        if isinstance(t, bool) or not isinstance(t, (int, float)) or not isinstance(url, str) or not isinstance(name, str):
            continue
        events.append((float(t), url[:500], name[:100]))
    events.sort(key=lambda e: e[0])
    return events


def app_usage(events, start, end):
    """Sekunder per tjänst mellan start och slut: [{url, name, s}], flest först, högst 36, 0 s utelämnas.
    Tillståndet vid start är den senaste händelsen före den; tid på förstasidan (tom url) räknas inte."""
    if not events or end <= start:
        return []
    cur_url, cur_name = "", ""
    i = 0
    while i < len(events) and events[i][0] <= start:
        cur_url, cur_name = events[i][1], events[i][2]
        i += 1
    totals = {}

    def add(url, name, a, b):
        if url and b > a:
            entry = totals.setdefault(url, [0.0, name])
            entry[0] += b - a
            entry[1] = name or entry[1]

    pos = start
    while i < len(events) and events[i][0] < end:
        t, url, name = events[i]
        add(cur_url, cur_name, pos, t)
        pos, cur_url, cur_name = t, url, name
        i += 1
    add(cur_url, cur_name, pos, end)
    apps = [{"url": u, "name": v[1], "s": int(round(v[0]))} for u, v in totals.items()]
    apps = [a for a in apps if a["s"] >= 1]
    apps.sort(key=lambda a: -a["s"])
    return apps[:MAX_APPS_PER_VISIT]


def queue_visit(start, end, reason, apps=None):
    os.makedirs(os.path.dirname(VISITS_FILE), exist_ok=True)
    with open(VISITS_FILE + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(VISITS_FILE, encoding="utf-8") as f:
                lines = f.read().splitlines()
        except OSError:
            lines = []
        visit = {"start": int(start), "end": int(end), "reason": reason}
        if apps:
            visit["apps"] = apps
        lines.append(json.dumps(visit))
        # Utan nät i flera dagar: behåll bara de senaste
        lines = lines[-MAX_QUEUED:]
        tmp = VISITS_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp, VISITS_FILE)


def take_reason():
    try:
        with open(REASON_FILE, encoding="utf-8") as f:
            reason = re.sub(r"[^a-z]", "", f.read(20))
        os.remove(REASON_FILE)
        return reason or None
    except OSError:
        return None


def main():
    config = load_config(CONFIG_FILE)
    if config.get("COMPUTER_TYPE") == "signage":
        log("Skylt: räknar inga besök")
        while True:
            time.sleep(3600)

    try:
        idle_minutes = int(config.get("SESSION_IDLE") or 5)
    except ValueError:
        idle_minutes = 5
    idle_limit = idle_minutes * 60 if idle_minutes > 0 else 300

    devices = open_devices({})
    log(f"Följer {len(devices)} indataenheter, besök slutar efter {idle_limit} s utan aktivitet")
    rescanned = time.monotonic()

    started = None  # tid (epoch) för första aktiviteten i besöket
    last_input = None  # tid för senaste aktiviteten
    active_ticks = set()  # 5-sekundersintervall med aktivitet under besöket

    kiosk = config.get("COMPUTER_TYPE") == "kiosk"

    def end_visit(reason):
        nonlocal started, last_input, active_ticks
        if started is None:
            return
        if len(active_ticks) < MIN_ACTIVE_TICKS:
            log(f"Ignorerade kort aktivitet {time.strftime('%H:%M:%S', time.localtime(started))} (inget besök)")
        else:
            queue_visit(started, last_input, reason, app_usage(read_app_events(), started, last_input) if kiosk else None)
        started, last_input, active_ticks = None, None, set()

    while True:
        if time.monotonic() - rescanned > RESCAN_EVERY:
            devices = open_devices(devices)
            rescanned = time.monotonic()
        readable = []
        if devices:
            try:
                readable, _, _ = select.select(list(devices.values()), [], [], TICK)
            except (OSError, ValueError):
                devices = open_devices({})
                continue
        else:
            time.sleep(TICK)

        now = time.time()
        human = False
        for fd in readable:
            try:
                data = os.read(fd, EVENT.size * 64)
            except OSError:
                continue
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, ev_type, _, _ = EVENT.unpack_from(data, i)
                if ev_type in (EV_KEY, EV_REL, EV_ABS):
                    human = True

        if human:
            if started is None:
                started = now
            last_input = now
            active_ticks.add(int(now // TICK))

        # Utloggning eller att tiden tog slut: besöket är slut direkt (klicket på Logga ut hör till
        # det), nästa besökare börjar ett nytt
        reason = take_reason()
        if reason:
            end_visit(reason)
        elif started is not None and now - last_input >= idle_limit:
            end_visit("idle")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
