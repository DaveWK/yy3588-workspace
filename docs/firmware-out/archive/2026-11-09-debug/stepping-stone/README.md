# YY3588 ore firmware build outputs (2026-11-09)

Built from the development tree `ore-edk2-boot-yy3588`,
branch `yy3588` at `e51a7022e4` (stepping stone + own DDR init + USB fastboot merged).
The earlier set built at `91bc254f6a` is in `superseded-91bc254f6a/`. `fit-RELEASE.itb`,
`idblock.bin`, `yy3588-bt0.bin`, `YY3588_skeleton_DEBUG.img` and the closure reports are
from that earlier build (unchanged by the merges except bt0 internals). Nothing here has
run on hardware yet.

| File | What |
|---|---|
| `YY3588_rkbinddr_DEBUG.img` / `_RELEASE.img` | **DEV ONLY, contains the rkbin DDR blob.** Stepping stone: rkbin DDR init → our bt0 → TF-A BL31 → EDK2 (no OP-TEE). idblock at 0x8000, FIT at 0x100000 |
| `YY3588_rkbinddr_draminfo_loader.bin` | **DEV ONLY.** MaskROM loader for `rkdeveloptool db`: rkbin DDR init + bt0 that prints dram-info over UART, then serves USB fastboot (`fastboot boot`/`stage`+`continue` runs TF-A + EDK2 from RAM; `fastboot flash` writes eMMC). See `FASTBOOT.md` |
| `YY3588_rkbinddr_boot_loader.bin` | **DEV ONLY.** MaskROM loader that reruns bt0's eMMC → BL31 → EDK2 path (needs the FIT on eMMC) |
| `YY3588_skeleton_DEBUG.img` | No-blob image (own bt0 without DDR init yet): for the closure check only, will not boot |
| `yy3588-bt0*.bin`, `idblock*.bin`, `fit-RELEASE.itb` | the pieces the images are made from (`-dram`: stepping stone, `-usb`: dram-info + fastboot, `-ownddr`: our own DDR init, no loader/image built for it yet) |
| `FASTBOOT.md` | host-side fastboot commands and how bt0 enters fastboot |
| `closure-*.txt/json` | `check-closure rk3588 --report` results (stepping stone: 1 rkbin DDR blob; skeleton: 0) |
| `build.log` | local container build log |

Serial console: header J43 (pin 2 board TX, pin 3 board RX, pin 1 GND (verify), pin 4 3.3 V: leave
unconnected), 3.3 V TTL, 1500000 8N1.

Hardware test sequence and recovery: the top-level README (Flash). Back up the first 8 MiB of eMMC
(`rkdeveloptool rl 0 0x4000 emmc-first-8MiB.bin`) before writing anything; writing the
stepping-stone image replaces the vendor loader.

## YY3588_upstream_uboot_loader.bin (A/B test, 2026-11-09)

Mainline U-Boot v2026.10-rc4 (`211de43d0f9`), `generic-rk3588_defconfig` plus
MaskROM image, EHCI/OHCI/xHCI, USB keyboard, preboot `usb start; usb tree;
setenv stdin serial,usbkbd`, bootdelay -1 (stops at the prompt). DT: rk3588-generic switched to full rk3588.dtsi, plus EHCI/OHCI 0/1 and USB3OTG1 host (u2phy1 + usbdp_phy1 dp-lane-mux <2 3>, as the Rock 5B usb_host1_xhci) for the GL3523 hub.
rkbin DDR init as our loader, BL31 = rkbin v1.56. Console UART2 M0 1500000.
Purpose: does serial input / a USB keyboard work in an open chain on this board?
`rkdeveloptool db YY3588_upstream_uboot_loader.bin`

## yy3588-uboot-ab.itb (A/B test via bt0 fastboot, 2026-11-09)

YY3588_upstream_uboot_loader.bin did not start (SPL silent after the DDR init).
This FIT skips SPL: bt0 (draminfo loader) `fastboot boot`s the same TF-A as
yy3588-fit-*.itb plus mainline U-Boot proper (`u-boot.bin` with DTB, at
0x800000, named `edk2` so bt0 hands it BL33). Source: uboot-ab/ (its, config fragment, trace patch, base commit).
`rkdeveloptool db YY3588_rkbinddr_draminfo_loader.bin` then
`fastboot boot yy3588-uboot-ab.itb`.
