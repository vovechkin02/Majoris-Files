#!/bin/bash
set -eu
base=artifacts/menu-relocation
for palette in light dark; do
    files=()
    for state in application network-sidebar trash-sidebar tag-sidebar preferences-network preferences-tags search-options operations-no-recovery recovery empty more-actions; do
        files+=("$base/screenshots/$state-$palette.png")
    done
    magick montage -font DejaVu-Sans -label '%t' "${files[@]}" -geometry 460x320+6+20 -tile 3x4 "$base/contact-$palette.png"
done
