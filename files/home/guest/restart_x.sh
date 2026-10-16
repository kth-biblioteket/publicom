#!/bin/bash
logger -t publicom-idle "Återställning efter inaktivitet"
/usr/local/bin/clean-up.sh
pkill -f chromium-browser
sleep 1
