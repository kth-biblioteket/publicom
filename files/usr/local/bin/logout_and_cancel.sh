#!/bin/bash

if zenity --question --text="Are you sure you want to log out?"; then
    /usr/local/bin/clean-up.sh
    # Orsaken till att besöket tog slut, för statistiken (visit_tracker.sh)
    echo logout > /tmp/publicom-end-reason
    pkill X
fi
