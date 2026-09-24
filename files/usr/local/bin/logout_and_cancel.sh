#!/bin/bash

if zenity --question --text="Are you sure you want to log out?"; then
    /usr/local/bin/clean-up.sh
    pkill X
fi
