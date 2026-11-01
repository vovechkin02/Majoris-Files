#!/bin/bash
set -eu
export GTK_A11Y=none ADW_DISABLE_PORTAL=1 GDK_BACKEND=x11 GSK_RENDERER=cairo GSETTINGS_BACKEND=memory
export MAJORIS_MENU_EVIDENCE="$PWD/artifacts/menu-relocation/screenshots"
export MAJORIS_MENU_THEME="$(realpath ../Majoris-Theme/theme/Majoris)"
mkdir -p "$MAJORIS_MENU_EVIDENCE"
openbox > /tmp/majoris-menu-openbox.log 2>&1 &
wm=$!
trap 'kill "$wm" 2>/dev/null || true' EXIT
build/menu-tests

if [[ "${MAJORIS_MENU_APPLICATION_ONLY:-0}" != 1 ]]; then
    MAJORIS_MENU_APPLICATION_ONLY=1 build/menu-tests -p /menus/context-and-presentation
    bash artifacts/menu-relocation/contact-sheets.sh
fi
