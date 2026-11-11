# YY3588 handoff (2026-11-10, end of day)

Start here. The hour-by-hour log with every measurement is
`docs/handoff-2026-11-10.md`; this file is the state to resume from.

Firmware repo
`ore-edk2-boot-yy3588/`, branch `yy3588`, HEAD `1f376d4fe6`, working tree
clean. Board is powered off; the eMMC holds the
vendor-blob test image (see "On the eMMC").

## Board state in one paragraph

The SoM works: Debian boots, serial, adb over USB-C, HDMI, RTC, 32 GB, 8 CPUs.
The carrier does not: the 5 V rail (`VCC5V0_SYS`, U21 NB679) starts and drops
out or never starts, so USB-A and both hubs are dead; the gigabit PHY answers
MDIO and makes its 125 MHz clock but passes no signal to or from the cable
(no link, no RXC, so `Failed to reset the dma`); the 2.5G RTL8125 is not
detected. The 3.3 V rail (`VCC3V3_SYS`, U2 NB680) is up and was measured at
about 3.3 V. None of this moved with any firmware change tonight, with four
12 V supplies (2 A to 5 A), or with the full stock Android image. It needs a
multimeter; see "Next".

## The wiring fault (root cause of the earlier chaos)

J43 debug header, board edge toward you, left to right: **pin 4 VCC3V3_SYS,
pin 3 RX, pin 2 TX, pin 1 GND**. Until 17:22 the serial adapter's ground was
on the leftmost pin, i.e. on the 3.3 V rail. With USB-C also on the PC that
shorted the rail to ground: resets, "intermittent" rail, LEDs dying. Correct
hookup: adapter GND to the **rightmost** pin, adapter RX to the third pin
(board TX), adapter TX to the second, leftmost pin unconnected. J51 (blue
4-pin): pin 1 GND left, pin 4 `VCC5V0_SYS` right. Both derived from
`docs/YY3588  TOP.dxf` and confirmed on the board.

Other hardware facts found today (schematic `docs/YY3588_V3.pdf`):
- p.4: red/green LEDs run from the 5 V rail (lit = 5 V up; Linux turns them
  off unless `echo 1 > /sys/class/leds/work/brightness`). The "reset" button
  cuts the SoM's 4 V supply (EN of U23), it is a power cut. Both carrier
  regulators take EN from `PMIC_EXT_EN_OUT` through 10K (R372, R18).
- p.10: USB-A VBUS is the 5 V rail through 0R; both hubs need it.
- p.12: RTL8211F RGMII at 3.3 V, strapped address 1 (answers at 0 too),
  `PHY0_CLKOUT125` feeds `GMAC1_MCLKINOUT`, so `clock_in_out = "input"` in
  `mk-yy3588-dtb.sh` is the designed mode. Keep it.
- Switch 12 V at the wall with the barrel already plugged in; inserting the
  live plug causes an aborted first start (seen 8 times in the logs).

## What was ruled out tonight

| Suspect | Test | Result |
|---|---|---|
| Our flashing | vendor `upgrade_tool` v2.36 `ef` + `uf` of the Android image | boots to the vendor kernel, same dead carrier |
| Supply | 2 A, 2.5 A, vendor 3 A, 5 A | identical |
| Attached loads, plug bounce | bare board, wall switch | 3.3 V only, clean single start |
| DDR blob | rkbin v1.24 2112, v1.24 1848, vendor v1.18; 66 training runs compared; parameters diffed with `ddrbin_tool.py` | all train cleanly; vendor blob = stock parameters |
| BL31 | v1.56 and the vendor's v1.48 (exact build) | same |
| EDK2 clocks / voltages | MAX -> 1008 MHz, rail offset, ramp rate | same |
| PMIC config | compared every RK806 / RK860x write in vendor U-Boot and kernel with ours | no difference that touches the carrier enable; `EXT_EN` has no register |

RK806 restart codes (datasheet Rev 1.4; the vendor `rk806.h` order is wrong):
ON_SOURCE 0x74 = [7] PWRON [6] VDC [5] ABNORMAL [4] RESTART_RESETB
[3] PWRON_LP [2] PWRCTRL [1] DEV_RST [0] WDT; OFF_SOURCE 0x75 = [7] PWRCTRL
[6] VB_SYS_OV [5] TSD [4] SYNC [3] DEV_OFF [2] PWRON_LP [1] ABNORMAL
[0] VB_LO. The afternoon reset loop was `off=OFF_ABNORMAL on=ON_ABNORMAL`
(PMIC input below 2.7 V or above 6 V) at the kernel-image load, only with
5 V up / 3.3 V down. Not seen since the wiring fix. bt0 `diag` now prints
these decoded on every boot (`pmic rk806 power ...`).

## Firmware changes

Committed on `yy3588`:
- `705078b8a9` bt0 diag: RK806 power status lines.
- `d922fb6a31` + `f2cb026918` EDK2 CPU clusters at 1008 MHz (vendor U-Boot's
  value) instead of the RK3588Base MAX default. The first of the two
  (BOOTDEFAULT) made the kernel start 43 s slower; the second fixes it.

Committed later the same evening (three commits after `f2cb026918`), all tested on the board:
- EDK2 no longer writes RK806 BUCK7/8/10 (upstream table put them 25 mV
  high): `boards/rk3588/yy3588/overlay/.../RockchipPlatformLib.c`.
- EDK2 ramp rates: RK806 BUCK2 12.5 mV/us before its voltage write, RK860x
  slew code 4 at driver start: new
  `patches/yy3588/edk2-rk3588-yy3588/0006-*.patch`, `patches/yy3588/pin.env`
  (tree `22615352ec...`), board `README.md`. `src/edk2-rk3588-yy3588` has the
  patch content applied by hand; `make yy3588-sources` re-creates it.
- bt0 `mmio::stimer_start()` (bt0 `src/mmio.rs`, `src/main.rs`): starts the
  SoC timer when bt0 runs straight out of the BootROM. Needed for own DDR;
  no-op after the rkbin blob.

## Own DDR init

Resumed at Dave's request (it was paused on 11-09). RAM-only loader
`ore-edk2-boot-yy3588/out/yy3588/YY3588_ownddr_loader.bin` (bt0
`--features own-ddr,diag`, packed as 471 and 472; build commands in the long
log). First run hung on the stopped timer; with `stimer_start` it reads the
PMIC, then channel 0 fails: `dq_fail=0xffff`, MR5-8 read 0 (expected MR8
0x58). Log: `serial-logs/2026-11-10-2110-ownddr-first-contact.txt`. The DRAM
does not answer on the command bus yet. Licence guard still applies: no
values from the rkbin blob or register dumps of it. A failed run leaves the
board stuck in bt0; power-cycle.

## Images (`firmware-out/full/`, SHA256SUMS updated)

| File | Contents | Status |
|---|---|---|
| `YY3588_fw_rkbintfa_DEBUG-20261110h.img` / `yy3588-fw-20261110h.simg` | **the one to flash next**: rkbin DDR v1.24 2112 MHz + bt0 diag (`6c635ac9ab`) + BL31 v1.56 + EDK2 with all fixes | built, not yet flashed; same sources as tested build e |
| `yy3588-debian12-uefi-20261110h.simg` (+ `.img`) | full one-shot eMMC image with that firmware, vendor kernel, patched DTB, Debian 12 | built, not yet flashed |
| `YY3588_fw_vendor-ddr118-bl31v148_DEBUG-20261110g.img` | vendor DDR v1.18 + bt0 + BL31 v1.48 + EDK2 fixes | **on the eMMC now**, boots |
| `...-20261110f-ddr1848.img` | rkbin v1.24 1848 MHz + EDK2 fixes | tested, boots |
| `...-20261110e.img` | as h but the older bt0 build | superseded by h |
| `...-20261110d.img`, `c`, `b` | steps on the way (1008 MHz; slow BOOTDEFAULT; PMIC status only) | superseded |
| `yy3588-debian12-uefi-20261110.simg` | afternoon full image (EDK2 MAX clocks) | superseded by h |
| `YY3588_rkbinddr_fastboot_loader.bin` | MaskROM RAM flasher (`fastboot getvar carrier` / `pmic`) | current |

Loader blocks kept in `ore-edk2-boot-yy3588/out/yy3588/`:
`idblock-rkbinddr.bin` (v1.24 2112, current), `idblock-rkbinddr-1848.bin`,
`idblock-vendor-ddr118.bin`. Vendor blobs and parameter dumps:
`yy3588_extras/image-inputs/rkbin-ddr/` (DDR v1.18 from the stock loader,
`rk3588_bl31_v1.48.elf` from rockchip-linux/rkbin `0f8ac86`).

## On the eMMC

Debian partitions from the 17:31 flash (ESP DTB = clock-input variant) with
firmware area image g (vendor DDR v1.18 + BL31 v1.48). To go back to rkbin
v1.24 + BL31 v1.56 without touching Debian:

```
cd ~/src/yy3588-workspace/firmware-out
rkdeveloptool db full/YY3588_rkbinddr_fastboot_loader.bin
fastboot getvar carrier; fastboot getvar pmic
fastboot flash emmc full/yy3588-fw-20261110h.simg     # 8 MB, 2 s
fastboot reboot
```

Full reflash instead: `fastboot flash emmc full/yy3588-debian12-uefi-20261110h.simg`
(about 2.5 min).

## Tools set up today

- Serial: `./serial-log.sh <label>` (PL2303 on /dev/ttyUSB0, 1.5 Mbaud). If
  the adapter re-enumerates the logger goes deaf: `screen -S yy3588-uart -X
  quit` and start it again. Current log
  `serial-logs/2026-11-10-2034-20261110-eve.log`.
- adb over USB-C works on Debian, root shell,
  `io -4 -r/-w` for registers. PHY registers through the MAC: MDIO address
  reg `0xfe1c0200`, data `0xfe1c0204` (examples in the long log).
- No-meter voltmeter: Luckfox Pico Max,
  `GPIO1_C7_d` as a pulled-down input read with `io -4 -r 0xff530070` bit 23,
  1N4007 diodes in series as a ladder (true 3.3 V passes three diodes, not
  four). Its ADC pins are 1.8 V only; never put a rail on them.

## Next

1. **Multimeter** (decides everything about the carrier). Power off:
   resistance 5 V rail to ground, 5 V to 3.3 V (J51 pin 4, J43 pin 4).
   Power on: 12 V at the board, `PMIC_EXT_EN_OUT` at R18 / R372, U21 output,
   U2 output, PHY supplies. If U21's EN is high and its output is low, the
   5 V regulator or a short on its rail is the fault.
2. Flash image h (commands above) and confirm it boots like build e.
3. If the carrier is beyond repair: a replacement carrier; the SoM is fine.
4. Own DDR: find why channel 0 gives no MRR data (clock / reset / CKE
   sequencing, CA bus, PHY init) against the TRM and the two U-Boot RFCs.
5. Optional: fix the upstream `SpiLib/RK806.c` selector base (0xA1 -> 0xA0)
   as a patch instead of avoiding it in the board table.
