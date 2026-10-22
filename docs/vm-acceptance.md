# Majoris VM acceptance procedure

**Not executed in this environment.** Use snapshots of the intended Majoris ISO,
a Windows 11 client and a standard non-root desktop account. Record ISO/package
hashes, versions, session type, exact steps, observed results and logs per scenario.
A pass requires the expected result, not merely no application crash. Restore the
snapshot after privileged policy and fault-injection scenarios.

1. Install the built package with dependencies and review `testparm`, portal and
   service registrations described in platform-integration.md. Log in fresh with
   Majoris desktop identity. Open a directory through desktop/default MIME,
   FileManager1 and shell search; confirm Majoris branding and no competing manager.
   Verify existing personal MIME choices survive package installation.
2. In native Majoris Notepad and two separate Flatpak callers exercise Open single,
   multiple, folder, Save, SaveFiles, cancellation and caller exit. Test X11 and
   Wayland sessions with exported parent handles: dialog modal to the correct
   parent, correct focus on close, no focus theft from the other caller. Verify
   selected document grants and denial of an unrelated secret file.
3. On real SMB, SFTP and WebDAV servers Open large files, compare SHA256, edit Save
   and overwrite twice; inspect original server bytes from a second client. Cancel
   downloads and sever the network mid-transfer. Check private pending cleanup,
   retained import lifetime after chooser exit, explicit copy labeling and no
   remote Save success when FUSE is unavailable. Repeat against the real cloud
   adapter with online-only, cached, pinned, quota and offline states.
4. Create a graphical Samba share; verify Windows enumeration, then Hide and verify
   omission while the explicit UNC path still works. Exercise R/F/D for two SMB
   accounts and guests; combine with restrictive POSIX mode and ACLs. Changing a
   hidden share's ACL must preserve both policy and visibility. Edit outside the
   app, rename/remove a shared folder and disconnect clients; verify reload,
   emblems, bounded owner-scoped client status and no administrator-share mutation.
5. With authorized and denied Polkit sessions exercise start/stop/password/share
   operations. With firewalld active check runtime and permanent owned policy
   creation/removal, reboot persistence and last-share cleanup. Confirm home/work
   ingress only and unchanged public/admin rules. Repeat inactive, absent and
   unmanaged nftables cases: no activation/rewrite or misleading success.
6. For USB storage, MTP/PTP and optical media remove/unmount while browsing, while
   a chooser has a selection, during import and before Save acceptance. Test busy
   eject, permissions, encrypted unlock and disk-image mount/unmount. Selection
   and grants must not silently move to another mount; errors must be recoverable.
7. Exercise file and directory replacement, merge, move, batch rename cycles and
   persistent Undo/Redo on the target filesystem. Kill/restart at journal phases;
   verify old data or complete new data and recoverable backups. On a disposable
   small filesystem fill space during replacement; verify original and source.
8. Preview a real-camera RAW corpus, rotated HEIC/AVIF, alpha, tagged ICC/PQ/HLG,
   static and animated GIF/WebP/AVIF (including timing and reduced motion). Compare
   orientation/colors with a trusted color-managed viewer; SDR tone mapping is the
   implemented HDR path. Exercise malformed inputs and monitor worker limits.
9. Play MP4/H.264, HEVC, WebM/MKV and MP3/AAC/FLAC/Opus through physical speakers;
   verify sound, synchronization, pause/seek/volume/mute, resize, switch-preview
   cancellation and GPU behavior. Verify tagged metadata/artwork and thumbnails.
   Open formatted DOCX/XLSX/PPTX; confirm isolation and accurate fallback labeling.
10. Create/extract encrypted multipart archives locally and on SMB/SFTP/WebDAV;
    compare hashes, cancel, disconnect, remove/corrupt a middle volume and supply
    wrong passwords. Partial sets must be refused. Validate any stranded set with
    `7z t` before resolving an incomplete marker; never discard unidentified files.
11. On a fully indexed large home tree record directory enumeration counts for a
    known filename search. Covered roots must not be recursively scanned. Repeat
    mixed covered/remote, paused/unavailable index, explicit exhaustive and Unicode
    substring cases. Record main-loop responsiveness for 10k/100k item browsing.
12. Save clockwise/counterclockwise JPEG/PNG rotations; inspect real file dimensions,
    orientation/ICC/metadata. Confirm quality fallback prompt where required and
    byte-identical Undo/Redo after restart. Reject externally modified originals.
13. Exercise grouped Grid with many groups/items, resize wide/narrow and large font,
    Shift-click/range keys, sort, Tags regroup, rename and directory updates. No
    clipped tiles, stale labels, duplicate items or lost selection. With a screen
    reader traverse toolbar, headings, files, Properties, chooser and dialogs.
14. Enable/disable/restart/uninstall an external column provider, alter metadata,
    sort a large directory and navigate during RPC. Slow/invalid providers must
    remain bounded. With a real Nearby transport transfer to a peer, verify bytes,
    cancel, lose peer and exit provider. Without a provider show unavailable.

Record each result as PASS, FAIL or UNVERIFIED with evidence. Outstanding FAIL or
UNVERIFIED platform requirements remain release gates; fixture passes do not
convert them to production acceptance.
