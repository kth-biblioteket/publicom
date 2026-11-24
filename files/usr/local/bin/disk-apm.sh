#!/bin/bash
# Stänger av hårddiskens energisparläge som parkerar läshuvudena (APM). Anropas av udev
# (/etc/udev/rules.d/60-publicom-disk-apm.rules) för varje disk, och av deploy.sh efter ändring.
# Roterande bärbara diskar parkerar annars huvudena var minut när datorn går dygnet runt, och
# diskens parkeringsbudget (ca 600 000 cykler) tar slut på några år. SSD-diskar hoppas över.
# Användning: disk-apm.sh <enhet>   t.ex. disk-apm.sh sda
dev="$1"
[[ "$dev" =~ ^sd[a-z]+$ ]] || exit 0
[ "$(cat "/sys/block/$dev/queue/rotational" 2>/dev/null)" = "1" ] || exit 0
command -v hdparm > /dev/null || { logger -t publicom-disk "hdparm saknas, kan inte stänga av APM på /dev/$dev"; exit 0; }
if hdparm -B 254 "/dev/$dev" > /dev/null 2>&1; then
    logger -t publicom-disk "APM 254 satt på /dev/$dev (parkering av)"
else
    logger -t publicom-disk "disken /dev/$dev stöder inte APM, ingen ändring"
fi
exit 0
