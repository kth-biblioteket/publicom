#!/bin/bash

GUEST_HOME=$(readlink -f /home/guest/snap/chromium/current)

TARGET_DIRS=("Desktop" "Documents" "Downloads" "Music" "Pictures" "Public" "Templates" "Videos")

find "$GUEST_HOME" -maxdepth 1 -mindepth 1 \( -type f -o -type l \) -print0 \
  | xargs -0 rm -f --

for DIR in "${TARGET_DIRS[@]}"; do
  if [ -d "$GUEST_HOME/$DIR" ]; then

    # Delete everything (files, hidden files, subdirectories) in the target directory
    find "$GUEST_HOME/$DIR" -mindepth 1 -print0 \
      | xargs -0 rm -rf --

  fi
done

# Chromium-profilen (historik, cache m.m.) ska inte ligga kvar på disken efter sessionen.
# Samma sökväg som CHROMIUM_PROFILE i .xinitrc.
rm -rf /home/guest/snap/chromium/common/publicom-profile
