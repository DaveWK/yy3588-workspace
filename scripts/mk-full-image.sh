#!/bin/bash
# One-shot eMMC image for the youyeetoo YY3588: firmware + ESP + Debian rootfs.
#
#   0 .. 16 MiB  firmware, copied from the edk2-rk3588 image from 32 KiB on:
#                idblock (rkbin DDR init + bt0) at 32 KiB, FIT (BL31 + EDK2)
#                at 1 MiB, UEFI variable store up to 8 MiB. The GPT sits in
#                front of it (sectors 0..33).
#   p1 "esp"     FAT32, 256 MiB at 16 MiB: systemd-boot, the vendor kernel
#                Image (RKNPU and RK1828 pcie-rkep built in), the vendor DTB
#                patched by mk-yy3588-dtb.sh (console ttyS2, no FIQ debugger).
#   p2 "rootfs"  10 GiB ext4 at 272 MiB, PARTUUID 614e0000-...-1d28000054a9
#                (the vendor layout's rootfs id); the rootfs grows its
#                filesystem to the partition on first boot (resize-helper).
#
# No root, no loop mounts: sgdisk, mkfs.vfat/mtools, dd, fdtput, ext2simg.
# Output: a sparse raw image and an Android sparse image (fastboot flash emmc
# <image>.simg, mk-disk-simg.py): only in-use rootfs blocks are written, the
# rest of the rootfs partition is skipped.
#
# NO_FUSB302=1 disables the USB-C controller in the DTB (mk-yy3588-dtb.sh
# --no-fusb302), for boards whose carrier 3.3 V rail is down.
#
# Usage: mk-full-image.sh <firmware.img> <kernel Image> <vendor rk3588-yyt.dtb> <rootfs.img> <systemd-bootaa64.efi> <out.img>
set -euo pipefail

if [ $# -ne 6 ]; then
    sed -n '2,23p' "$0" >&2
    exit 2
fi
fw=$1
kernel=$2
dtb=$3
rootfs=$4
sdboot=$5
out=$6

mib=$((1024 * 1024))
fw_from=$((32 * 1024))
esp_start=$((16 * mib))
esp_size=$((256 * mib))
root_start=$((esp_start + esp_size))
root_size=$((10 * 1024 * mib))
total=$((root_start + root_size + mib))
rootfs_partuuid=614e0000-0000-4b53-8000-1d28000054a9
cmdline="root=PARTUUID=$rootfs_partuuid rootfstype=ext4 rw rootwait console=tty1 console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfeb50000 irqchip.gicv3_pseudo_nmi=0 rcupdate.rcu_expedited=1 rcu_nocbs=all"

for f in "$fw" "$kernel" "$dtb" "$rootfs" "$sdboot"; do
    [ -f "$f" ] || { echo "missing input: $f" >&2; exit 1; }
done
fw_size=$(stat -c %s "$fw")
[ "$fw_size" -le "$esp_start" ] || { echo "firmware image larger than 16 MiB" >&2; exit 1; }
[ "$fw_size" -gt "$fw_from" ] || { echo "firmware image ends before 32 KiB" >&2; exit 1; }
[ "$(stat -c %s "$rootfs")" -le "$root_size" ] || { echo "rootfs larger than 10 GiB" >&2; exit 1; }

here=$(dirname "$(readlink -f "$0")")
work=$(mktemp -d "${out}.work.XXXXXX")
trap 'rm -rf "$work"' EXIT

dtb_args=()
[ "${NO_FUSB302:-0}" = 1 ] && dtb_args=(--no-fusb302)
"$here/mk-yy3588-dtb.sh" "$dtb" "$work/rk3588-yyt.dtb" "${dtb_args[@]}"

rm -f "$out"
truncate -s "$total" "$out"
# (sgdisk -q saves nothing in gdisk 1.0.10, so its chatter goes to /dev/null.)
sgdisk -o \
    -n "1:$((esp_start / 512)):$(((esp_start + esp_size) / 512 - 1))" -t 1:EF00 -c 1:esp \
    -n "2:$((root_start / 512)):$(((root_start + root_size) / 512 - 1))" -t 2:8300 -c 2:rootfs -u "2:$rootfs_partuuid" \
    "$out" >/dev/null
sgdisk -i 2 "$out" | grep -qi "$rootfs_partuuid" || { echo "GPT not written" >&2; exit 1; }

# Firmware: everything from 32 KiB on (idblock, FIT, variable store).
dd if="$fw" of="$out" bs=512 skip=$((fw_from / 512)) seek=$((fw_from / 512)) conv=notrunc status=none
# UEFI variable store (edk2-rk3588 FIT "nvdata": data-position 0x6C0000 in
# the FIT at 1 MiB, 0x30000 bytes): erased (0xFF) where the firmware image
# does not reach, as bt0's fastboot staging does (rk3588-fastboot fill).
nv_start=$((0x7C0000))
nv_end=$((0x7F0000))
if [ "$fw_size" -lt "$nv_end" ]; then
    from=$((fw_size > nv_start ? fw_size : nv_start))
    head -c $((nv_end - from)) /dev/zero | tr '\0' '\377' |
        dd of="$out" bs=1 seek="$from" conv=notrunc status=none
fi

# ESP.
esp=$work/esp.img
mkfs.vfat -F 32 -n ESP -C "$esp" $((esp_size / 1024)) >/dev/null
export MTOOLS_SKIP_CHECK=1
mmd -i "$esp" ::/EFI ::/EFI/BOOT ::/EFI/systemd ::/loader ::/loader/entries ::/dtb
mcopy -i "$esp" "$sdboot" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "$esp" "$sdboot" ::/EFI/systemd/systemd-bootaa64.efi
mcopy -i "$esp" "$kernel" ::/Image
mcopy -i "$esp" "$work/rk3588-yyt.dtb" ::/dtb/rk3588-yyt.dtb
# timeout 0: boot the default entry at once. With the carrier 3.3 V rail up
# the debug UART picks up noise, and stray input stops or quits a countdown
# menu (hold a key at start to get the menu).
printf 'default debian.conf\ntimeout 0\nconsole-mode keep\n' >"$work/loader.conf"
# EDK2's built-in DTB keeps the FIQ debugger, which hangs the vendor kernel:
# the one entry always loads the patched DTB from the ESP.
cat >"$work/debian.conf" <<EOF
title   Debian 12 (YY3588 vendor 6.1)
linux   /Image
devicetree /dtb/rk3588-yyt.dtb
options $cmdline
EOF
mcopy -i "$esp" "$work/loader.conf" ::/loader/loader.conf
mcopy -i "$esp" "$work/debian.conf" ::/loader/entries/
dd if="$esp" of="$out" bs=1M seek=$((esp_start / mib)) conv=notrunc,sparse status=none

# Rootfs.
dd if="$rootfs" of="$out" bs=1M seek=$((root_start / mib)) conv=notrunc,sparse status=none

sgdisk -p "$out" | sed -n '/^Number/,$p' >&2
ext2simg "$rootfs" "$work/rootfs.simg"
"$here/mk-disk-simg.py" "$out" "$root_start" "$work/rootfs.simg" "${out%.img}.simg"
(cd "$(dirname "$out")" && sha256sum "$(basename "$out")" "$(basename "${out%.img}.simg")")
