# YY3588 one-shot eMMC image

## 2026-11-10 evening: `yy3588-debian12-uefi-20261110h.simg` (current)

Same layout and inputs as the 20261110 image below, with the firmware area
replaced by `YY3588_fw_rkbintfa_DEBUG-20261110h.img`:

| Part | Build |
|---|---|
| idblock | rkbin DDR init v1.24 (2112 MHz) + bt0 `yy3588` @ `6c635ac9ab` (built before the commit, same sources), features `stepping-stone,diag` (adds the decoded `pmic rk806 power ...` lines and the STIMER start) |
| BL31 | Rockchip rkbin v1.56, no OP-TEE |
| EDK2 | DEBUG (`build-20261110h.log`): CPU clusters 1008 MHz as vendor U-Boot, RK806 BUCK7/8/10 left at their power-on values, BUCK2 ramp 12.5 mV/us and RK860x slew code 4 programmed before the voltage steps |
| kernel / DTB / rootfs | unchanged from 20261110 |

`yy3588-fw-20261110h.simg` is the firmware area alone (keeps the partitions).
Not yet booted: it is a rebuild of the tested 20261110e sources with the
current bt0. Other firmware-area images in this directory (b to g) are the
evening's test builds; `../README.md` lists them.

## 2026-11-10: `yy3588-debian12-uefi-20261110.simg` (afternoon build, superseded)

Same layout as rev b below, rebuilt with every bring-up fix and all
diagnostics on, eth/USB enabled as the evidence says they should be:

| Part | Build |
|---|---|
| idblock bt0 | `ore-edk2-boot-yy3588` `yy3588` @ `47fab282dd`, features `stepping-stone,diag`: full RK806 rail dump, carrier 3.3 V probe, dram-info report, CPLL 1500 / GPLL 1188 / PPLL 1100 MHz, on every boot over UART2 |
| BL31 | Rockchip rkbin v1.56 (`--open-tfa false`), no OP-TEE |
| EDK2 | **DEBUG** build (`build-20261110.log`): GMAC1 + RTL8211F, USBDP0/1, USB host (EHCI/OHCI/xHCI), rail probe lines (`YY3588 PWR [..] 3V3 rail probe`), PCIe 3.0 left to the kernel, no boot-menu countdown, no RK806 PWRCTRL1 function |
| kernel / DTB | vendor 6.1 `Image` (sha256 2e7390bb…), `rk3588-yyt.dtb` patched: FIQ debugger off, UART2 on, dsi0 off, GMAC1 clock from the PHY, MDIO scan, **fusb302 enabled** |
| rootfs | Debian 12 from `yy3588_sdk-bsp/output/rootfs.img`, as rev b |
| firmware alone | `YY3588_fw_rkbintfa_DEBUG-20261110.img` (0 .. 6.2 MiB, for `mk-fw-simg.py`) |

Flash (board in MaskROM, USB-C to the PC, serial unplugged):

```
rkdeveloptool db YY3588_rkbinddr_fastboot_loader.bin
fastboot getvar carrier          # on / OFF: the carrier 3.3 V rail, before flashing
fastboot flash emmc yy3588-debian12-uefi-20261110.simg
fastboot reboot
```

Expected on serial after a power-on: bt0 banner with `pmic ... 21/21 rails
on`, the rail dump, `carrier 3.3 V: on`, dram-info, `clocks: CPLL 750 ->
1500 ...`, then EDK2 DEBUG output (`RealtekPhyInit: Found Realtek RTL8211F`
and the USB hub on USB3OTG1 when the rail is on), systemd-boot, kernel.

Fallback: rev b below (`20261109b.simg`, RELEASE EDK2, boots to GNOME when
the rail is on; `-nofusb302` when it is off).

## 2026-11-09 rev b: `yy3588-debian12-uefi-20261109b.simg`

`yy3588-debian12-uefi-20261109b.simg` (Android sparse, for fastboot; the raw
`.img` is archived). Built by `mk-full-image.sh` (copies of
`mk-full-image.sh`, `mk-yy3588-dtb.sh`, `mk-disk-simg.py` here; the
workspace copies are the source).

| Region | Contents |
|---|---|
| 0 .. 16 MiB | GPT; idblock at 32 KiB = rkbin DDR init v1.24 + bt0 (`ore-edk2-boot-yy3588` `yy3588` at `cda6ed2e68`: CPLL 1500 / GPLL 1188 / PPLL 1100 MHz set in bt0); FIT at 1 MiB = Rockchip BL31 v1.56 + EDK2 RELEASE (PCIe 3.0 x4 left to the kernel, no boot-menu countdown); UEFI variable store 0x7C0000..0x7F0000 erased |
| p1 `esp` 256 MiB | systemd-boot (Debian bookworm 252.39-1~deb12u2), `/Image` (vendor 6.1, RKNPU + RK1828 pcie-rkep built in), `/dtb/rk3588-yyt.dtb` = vendor DTB patched by `mk-yy3588-dtb.sh` |
| p2 `rootfs` 10 GiB | Debian 12 rootfs from `yy3588_sdk-bsp/output/rootfs.img`, PARTUUID 614e0000-0000-4b53-8000-1d28000054a9; grows to 10 GiB on first boot |

DTB patches (`mk-yy3588-dtb.sh`): FIQ debugger off (it hangs the vendor
kernel), UART2 on, dsi0 off, GMAC1 125 MHz clock from the RTL8211F
(`clock_in_out = "input"` + `gmac1_clkinout`), MDIO scan for the PHY.
systemd-boot `timeout 0`, one entry, always the ESP DTB. Kernel command line:
`root=PARTUUID=... rw rootwait console=tty1 console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfeb50000 ...`.

`yy3588-debian12-uefi-20261109b-nofusb302.simg`: the same with the fusb302
USB-C controller disabled (`NO_FUSB302=1`). For a board whose carrier
3.3 V rail is down: there the vendor fusb302 driver retries its I2C reads
forever and the kernel never mounts root. Tested on the board: boots to GNOME.

## Flash (erases everything on the eMMC)

Board in MaskROM, USB-C to the PC, **debug serial unplugged** (serial and
USB-C on the same PC reset the board and drop the CH340):

```
rkdeveloptool db YY3588_rkbinddr_fastboot_loader.bin
fastboot flash emmc yy3588-debian12-uefi-20261109b.simg
fastboot reboot
```

About 2 min 20 s. The loader (bt0 `yy3588` at `965a98f3ed`; `fastboot getvar
carrier` / `pmic` read the carrier 3.3 V rail and the RK806 over USB) writes the eMMC
over an 8-bit bus at 49.5 MHz by SDMA (~46 MB/s) and TRIMs zero fills; the
rootfs part of the image holds only in-use blocks (`ext2simg`).
`fastboot getvar emmc` shows the bus mode; on a failure it steps down
(8-bit PIO, 25 MHz, 4-bit, 1-bit PIO) and `getvar emmc-error` shows why.
`YY3588_rkbinddr_fastboot_loader-pio1bit.bin` is the previous loader (1-bit
12 MHz PIO, ~3 MB/s, over an hour for the old image).

`YY3588_fw_rkbintfa_RELEASE.img` is the firmware part alone (0 .. 6.2 MiB).

## Update firmware + ESP only (keeps GPT and rootfs)

`mk-fw-simg.py <firmware.img> <out.simg> [esp.img]` rewrites 32 KiB .. 8 MiB
(idblock, FIT, erased variable store) and optionally the ESP, and skips the
rest. `yy3588-fw-esp-ttys2.simg` = current firmware + the ESP of the
nofusb302 image. Flash as above.

## Known issues

- The carrier 3.3 V rail (`VCC3V3_SYS`) is session-dependent (ON 09:44 to
  15:26 on 2026-11-09, OFF before and after, same firmware): no USB devices,
  no Ethernet link, fusb302 / hym8563 / es8388 I2C timeouts when OFF. The
  debug serial adapter (back-feed, ground loop with OTG) is the suspect;
  test procedure in `../README.md`.
- EDK2 does not initialise PCIe 3.0 x4 (RK1828 slot): its first DBI read
  stalls. The kernel brings the slot up.
- The day's superseded files moved to `../archive/2026-11-09-debug/full/`.
