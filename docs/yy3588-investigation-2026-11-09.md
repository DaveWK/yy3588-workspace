# YY3588: serial RX and USB hub investigation (2026-11-09)

Read-only review of `docs/yy3588-firmware-status-2026-11-09.md` by six parallel lanes:
carrier schematic and rails, bt0 register audit, USB hub power path, serial-log decoding,
RK3588 IO-domain research, and the mainline U-Boot `serial_init` hang. Nothing was built,
run on hardware, or changed in any repository.

## Conclusions

1. **The PMUIO2-unpowered hypothesis in the status doc is not supported.**
   RK3588 has no software IO-voltage register, so there is nothing for bt0 or EDK2 to
   have missed. PMUIO2 pads demonstrably work in our chain: I2C0 to the RK8602 regulators
   runs on PMUIO2 pads (GPIO0_D1/D2) with no errors. The probable PMUIO2 rail (BUCK8
   `vcc_3v3_s3`) is on at its OTP default of 3.3 V.
2. **The USB hub is dead because the carrier's 3.3 V rail is off.** The GL3523 takes all
   its 3.3 V from `VCC3V3_SYS`, has an RC-only reset and no software enable. The carrier's
   5 V rail is up (the FE1.1s hub on USB20_HOST0 enumerates at high speed in every run), so
   the 1.2 V hub buck is also running. Everything else on `VCC3V3_SYS` is dead too: the
   RTL8211F (PHY ID 0), I2C6 (RTC timeouts), u2phy0 session-valid, and the HDMI HPD and DDC
   shifters. EDK2 never read an EDID; it shows a menu only because it fell back to
   640x480 DVI timing. EDK2's USB PHY and DWC3 setup is correct and needs no change.
3. **The serial RX pad is receiving the board's own TX output.** In every rxprobe run the
   RX FIFO holds a clean, correct-polarity copy of the line bt0 had just printed. The "RX
   FIFO full of error bytes" reading in the status doc is wrong: LSR 0xa1 is RFE+THRE+DR
   with BI/FE/PE/OE clear, and the FIFO is full because bt0 writes FCR=0x01 (FIFO on, no
   reset) so it accumulated the echo of ~228 lines of boot output.
4. **The TX "garbling" is host-side framing loss, not bit errors.** A simulation reproduces
   the garbage bytes exactly as the board's clean 8N1 output misframed after a short low
   pulse on the line. Zero bit flips, zero baud drift, identical bytes across four runs.
5. **TX lives or dies on the RX pad's pull setting.** Changing only GPIO0_B6 (RX) from its
   reset pull-down to none silences TX entirely (phases 2 and 3 of rxprobe produced no
   output at all; this was not recorded in the status doc). Pull-up on B5+B6 also kills TX
   in both bt0 and mainline U-Boot. The vendor chain writes the same pull-up and works.
   This is the one observation that still points at a pad-domain supply or a resistive
   TX-to-RX path, and it is the thing to measure.
6. **bt0 has no register-level bug on the UART2 path.** Every pad, mux, clock and UART write
   matches vendor U-Boot and the kernel in address, shift, write-mask and value. Only
   cosmetic differences remain (FCR 0x01 vs 0x07, MCR never written vs 0x03). MCR reads 0,
   so internal loopback is ruled out.

## Carrier power chain (schematic `docs/YY3588_V3.pdf`)

The PDF covers the carrier only; the RK3588 and RK806 sit on a core module behind a 316-pin
connector (p.5). Only `VCC_SYSIN` (4.0 V) and the control signal `PMIC_EXT_EN_OUT` (pin 9)
cross the connector for power.

```
RK806 EXT_EN (pin 39) -> PMIC_EXT_EN_OUT (conn pin 9)
  |- R372 10K -> U21 NB679 EN -> VCC5V0_SYS      [ON: FE1.1s ccs=1 ped=1 in every run]
  |      |- U9 SY8089 (EN tied to VIN) -> VDD1V2_HUB -> GL3523 core 1.2 V
  |      |- downstream USB VBUS via 0R, FE1.1s VDD5, HDMI +5 V
  |- R18  10K -> U2  NB680 EN -> VCC3V3_SYS      [OFF: every 3.3 V load dead]
         |- FB2 -> VCC3V3_HUB -> GL3523 AVDD33/DVDD33, RESET# RC (R173/C111), CHIPEN, VBUS_IN
         |- U3 XC6219 -> carrier VCC_1V8_S3/S0 -> HDMI HPD shifter
         |- I2C6 pull-ups, HDMI DDC shifters, RTL8211F, u2phy0 VBUSDET pull-up, J43 pin 4
```

Both enables share one signal on the schematic, yet 5 V is up and 3.3 V is down. So one of:
(a) `PMIC_EXT_EN_OUT` is low and the fitted board has R374 (U21 EN to VIN) populated, making
5 V always-on; (b) the enable sits at a level above U21's threshold but below U2's; (c) U2 is
in fault. `EXT_EN` on the RK806 is a strap/OTP-sequenced pin; no public register field drives
it and neither the vendor kernel, vendor U-Boot nor bt0 writes anything for it. Why it would
differ between Android and our MaskROM-USB chain is unexplained and needs the meter.

Debug header J43 (p.16): pin 1 GND, pin 2 `UART2_TX_M0_DEBUG`, pin 3 `UART2_RX_M0_DEBUG`,
pin 4 `VCC3V3_SYS`. TX and RX run straight to connector pins 29/31 with only ESD5451N clamps
to ground. No level shifter, series or pull resistors. The carrier design assumes PMUIO2 is
3.3 V (I2C6 pull-ups, CC_INT_L pull-up and J43 pin 4 all on `VCC3V3_SYS`).

## RK3588 IO domains (documentation)

- The pull table for every RK3588 bank is `PULL_TYPE_IO_1V8_ONLY`: 00 none, 01 down,
  10 none, 11 up. Confirmed in mainline Linux, U-Boot and the vendor kernel. The status
  doc's correction is right, and the reset value 0x5400 is pull-down on B5/B6/B7.
- No RK3588 IO-domain driver, binding or VSEL register exists. Each 1.8/3.3 V domain has
  two supply balls (`PMUIO2_1V8` and `PMUIO2`); the board picks the voltage by which net is
  populated. Rock 5B feeds PMUIO2 from `vcc_1v8_s3` (1.8 V debug UART). NanoPC-T6 and
  Orange Pi 5 feed it 3.3 V. The YY3588 core-module schematic is not available; the carrier
  design implies 3.3 V.
- RK806 datasheet defaults: BUCK8 3.3 V (seq 6), BUCK10 1.8 V (seq 3), PLDO2/PLDO6 1.8 V,
  PLDO4 3.3 V. Enable state comes from OTP `POWER_EN0..5`. Our dumps show all 21 rails
  enabled; voltages other than the DDR rails are still unread.

## Serial evidence, corrected

| Status-doc claim | What the logs show |
|---|---|
| RX FIFO full of error bytes at start | Full of the board's own echoed output; head byte clean, BI never set, only FE on some bytes |
| TX garbled during every typing phase | Phases 2 and 3 produced no TX at all; the garbage is the phase-4 announcement misframed, identical with or without typing |
| No pad setting helped | Schmitt made RX decode cleanly (it decodes the echo); removing B6's pull-down killed TX |
| MaskROM misbehaves with adapter connected | No control run without the adapter exists; unsupported |
| 1.8 V pads with a 3.3 V adapter | Possible but contradicts the carrier design and the BUCK8 default; rail dump settles it |

EDK2's input path did see bytes: 566 of 567 "keys" were 0xFF (a lone start-bit pulse), one
was 0xDF. Typed characters never arrived intact.

The clean echo cannot come from shared-rail coupling inside the IO cell: decoupling limits
the swing to millivolts per bit, and back-feeding through the RX pad would invert it. A
clean 43-byte copy at 1.5 Mbaud needs a resistive TX-to-RX path and an RX node the adapter
is not driving firmly. A permanent header bridge would also break Android's console, so a
wiring fault is only viable if the leads changed after the Android test, which has no
capture to date it.

## Mainline U-Boot `serial_init` hang

It is the same pull-up write, not a hang. All three traced runs end at a clean
`ic serial_init` with zero trailing bytes. The next code is `device_probe(uart2)`, whose
`pinctrl_select_state("default")` applies `uart2m0_xfer` with `pcfg_pull_up`. The mux
writes are idempotent with the debug UART's; the only new write is `PMU2_IOC GPIO0B_P`
0x5400 -> 0x7C00 (B5/B6 = 11), byte-for-byte what bt0 commit `d19d8b72ba` did. The
`T ns16550 probe` trace sits after that write, so it cannot be seen. The `T clk probe`
trace never fires because `clock-frequency = <24000000>` in `rk3588s-u-boot.dtsi` skips
the CRU lookup entirely, so its absence is a red herring. Baud is unchanged (24 MHz / 16 /
1.5 Mbaud = divisor 1, same as the debug UART), and a wrong divisor would give garbage, not
silence. Latent but unrelated: if the CRU were probed, `rk3588_clk_init` would reprogram
CPLL/GPLL with an unbounded lock wait.

Discriminator (not applied): delete `pinctrl-0` and `pinctrl-names` from `&uart2` in the
U-Boot dtsi and reboot. If `T ns16550 probe` and the banner appear, the pull-up write is
confirmed. A finer variant keeps `uart2m0_xfer` but overrides both pins to
`pcfg_pull_none`. Note `firmware-out/ab-no-uart-pull/` holds only a bt0 loader, not a
mainline U-Boot image, so this discriminator has not been run.

## Measurements that settle it

Multimeter, board idle in bt0 fastboot (draminfo loader), adapter connected unless noted:

1. **J43 pin 4 to pin 1.** ~0 V in our chain and 3.3 V under Android confirms `VCC3V3_SYS`
   is off. Then measure `PMIC_EXT_EN_OUT` at R18/R372, U2 EN (pin 11), U2 PG (pin 3), and
   check whether R374 and R17 are fitted.
2. **J43 pin 2 (board TX, idle) to pin 1.** This is the PMUIO2 level as the TX driver sees
   it. 3.3 V: pads healthy. ~1.8 V: wrong domain voltage. Below ~2.8 V: starved domain.
3. **Lift the adapter's TX lead, re-measure pin 2, and rerun the draminfo loader.** If TX
   output stops or pin 2 drops, the pads are being fed through pin 3. If the start dump
   still shows `rfl=64`, the TX-to-RX echo is board-side. Pin 3 should read ~0 V
   (pull-down); if it tracks TX, the path is on the board or module.
4. **Board unpowered:** resistance pin 2 to pin 3, continuity adapter TX lead to pin 3.
5. **Confirm nothing is connected to J43 pin 4.** If the adapter's VCC lead is on it, the
   adapter is back-feeding the unpowered carrier 3.3 V net.
6. **Boot Android without touching the leads, type, capture with `serial-log.sh`.** Makes
   the Android control current; there is no Android capture in `serial-logs/`.

Software cross-checks, no hardware risk:

- Run the already-built rails dump (`96e81bcc20`) and compare BUCK8, BUCK10, PLDO2, PLDO4,
  PLDO6 against 3.3/1.8/1.8/3.3/1.8 V.
- Under Android, read RK806 registers 0x00-0x05, 0x5D, 0x62, 0x63, 0x72, 0xC3, 0xDD via
  regmap debugfs and diff against `serial-logs/2026-11-09-0341-run.log:75`.
- bt0: write FCR=0x07 and MCR=0x03 (vendor values); after 1 s of silence read RFL. Zero
  means the full FIFO was only the echo.
- bt0 rxprobe v2 (TX silent during measurement, results printed afterwards): B5/B6 as GPIO,
  drive B5 and read B6 under each pull (bridged if B6 follows B5); set pull-up on B6 alone,
  then B5 alone, each followed by a known TX string, to learn which pin's pull-up kills TX.
- EDK2: extend `PowerRailProbe` (RockchipPlatformLib.c:488-513) to log the FC800000 EHCI
  CCS/PED bits as "5 V present" and the HDMI HPD level, so each log shows the 5 V-on /
  3.3 V-off split without relying on PMUIO2 pad reads.

## Fixes implied

- **USB hub:** bring up `VCC3V3_SYS`. Where that is done depends on measurement 1; if
  `PMIC_EXT_EN_OUT` is low, the lever is in the RK806 (OTP power sequence or a PWRCTRL pin
  function), to be set in bt0 before TF-A. No EDK2 USB change is needed.
- **Serial:** no firmware change is justified yet. Land FCR=0x07 in bt0 for hygiene. The
  real fix waits on measurements 2 to 4.
- **Status doc:** update the four corrected readings above and record that B6 pull
  none/bus-hold kills TX.

## Lane artifacts

Lanes created scratch renders in `/tmp/yy3588sch`, `/tmp/yyhub` and
`.scratch-rxlane/` in the workspace; all three were deleted after the reports were read.
Two GPT-6 Astra lanes failed on a ChatGPT usage limit and were rerun on Opus 5.5.
