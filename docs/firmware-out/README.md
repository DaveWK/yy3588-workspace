# YY3588 firmware outputs

Current set: `full/` (see `full/README.md` for layout, flashing and known
issues). Everything from the 2026-11-08/09 bring-up that is no longer used
is under `archive/2026-11-09-debug/` (its README lists what is what).
`android14-dsi0/` is the stock Android 14 image unpacked, for a vendor
restore with `rkdeveloptool`.

| File | Built from | Use |
|---|---|---|
| `full/YY3588_rkbinddr_fastboot_loader.bin` | `yy3588` @ `965a98f3ed` | `rkdeveloptool db`: DRAM up, prints the PMIC / carrier 3.3 V / clock lines, serves fastboot on USB-C (8-bit SDMA eMMC writes). `fastboot getvar carrier` / `pmic` / `emmc` read the board state over USB |
| `full/YY3588_rkbinddr_draminfo_loader.bin` | same build (`diag` feature) | as above plus the full RK806 rail dump and dram-info on serial; use it to look, not to flash |
| `full/yy3588-debian12-uefi-20261110.simg` | bt0 @ `47fab282dd` (`diag`), BL31 v1.56, EDK2 **DEBUG**, vendor 6.1 kernel, Debian 12, fusb302 on | **the one-shot eMMC image** (all diagnostics on) |
| `full/yy3588-debian12-uefi-20261109b.simg` | bt0 @ `cda6ed2e68`, BL31 v1.56, EDK2 RELEASE | rev b fallback (booted to GNOME) |
| `full/yy3588-debian12-uefi-20261109b-nofusb302.simg` | same, fusb302 disabled | only for a board whose carrier 3.3 V rail is down (fusb302 I2C retries block root mount) |
| `full/yy3588-fw-esp-ttys2.simg` | | firmware + ESP only update (keeps rootfs) |
| `full/YY3588_fw_rkbintfa_DEBUG-20261110.img` / `_RELEASE.img` | | firmware region alone (0 .. 6.2 MiB), current / rev b |

## Test procedure (2026-11-10): one pass, no serial juggling

The carrier 3.3 V rail (`VCC3V3_SYS`: USB hub, Ethernet PHY, RTC, fusb302,
HDMI DDC) was ON 09:44-15:26 on 2026-11-09 and OFF before and after, same
firmware; the serial adapter (back-feed, ground loop with OTG) is the prime
suspect. The 20261110 image prints everything needed on every boot, and the
loader answers `getvar carrier` over USB, so one flash and one boot tell
the story.

1. Board in MaskROM (recovery button at power-on), USB-C to the PC, serial
   unplugged. `rkdeveloptool ld` -> `Maskrom`.
2. `rkdeveloptool db full/YY3588_rkbinddr_fastboot_loader.bin`
   `fastboot getvar carrier` / `fastboot getvar pmic` -> note them.
3. `fastboot flash emmc full/yy3588-debian12-uefi-20261110.simg` (~2.5 min),
   `fastboot reboot`, unplug USB-C.
4. Plug serial in (GND, TX, RX), `./serial-log.sh 20261110-boot`, power
   cycle the board. Read in the log: bt0 `pmic ... 21/21 rails on`, the rail
   dump, `carrier 3.3 V: on|OFF`, `clocks: CPLL 750 -> 1500`, EDK2
   `3V3 rail probe`, `RealtekPhyInit: Found Realtek RTL8211F`, USB hub
   lines, systemd-boot, kernel, login.
5. On the board: `ip link` (end1 UP, jack LEDs), `lsusb` (GL3523 hub +
   devices), `i2cdetect -y 6` (RTC 0x51, fusb302 0x22),
   `dmesg | grep -i -E 'rtl8211|hym8563|fusb302|usb 5-'`.
6. If step 2 said ON but step 4 says OFF (or the reverse), the only change
   between them was the serial adapter: that is the answer, and the isolator
   fixes it. If both say OFF, power-cycle once more with serial unplugged
   and read `ip link` over the USB hub keyboard / HDMI instead.

Recovery: MaskROM is always reachable with the recovery button;
`rkdeveloptool ef` then the vendor image, or `android14-dsi0/` parts with
`rkdeveloptool wl`.

## 2026-11-10 evening: current set

Read `../docs/handoff-2026-11-10-night.md` first. The table above describes
the afternoon build; these supersede it.

| File | Built from | Use |
|---|---|---|
| `full/yy3588-fw-20261110h.simg` (`YY3588_fw_rkbintfa_DEBUG-20261110h.img`) | rkbin DDR v1.24 2112 MHz + bt0 diag (`yy3588` @ `6c635ac9ab`: PMIC power status, STIMER start) + BL31 v1.56 + EDK2 DEBUG @ `1f376d4fe6` (clusters 1008 MHz, no BUCK7/8/10 writes, ramp rates) | **firmware area only, flash this next** (8 MB, keeps the Debian partitions) |
| `full/yy3588-debian12-uefi-20261110h.simg` | that firmware + vendor 6.1 kernel + patched DTB + Debian 12 | full one-shot eMMC image |
| `full/YY3588_fw_vendor-ddr118-bl31v148_DEBUG-20261110g.img` | vendor DDR v1.18 + bt0 + vendor BL31 v1.48 + same EDK2 | comparison build; on the eMMC since 21:15 |
| `full/YY3588_fw_rkbintfa_DEBUG-20261110f-ddr1848.img` | rkbin DDR v1.24 1848 MHz + same EDK2 | comparison build, tested |
| `full/YY3588_fw_rkbintfa_DEBUG-20261110{b,c,d,e}.img` | intermediate steps | superseded |

Firmware-area images are turned into a fastboot image with
`../mk-fw-simg.py <fw.img> <out.simg>` (h is already converted). Serial wiring
for J43 changed on 2026-11-10: adapter ground goes on the **rightmost** pin
(see the handoff).
