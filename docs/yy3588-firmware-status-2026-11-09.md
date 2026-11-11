# YY3588 ore-edk2-boot firmware: status and debugging log (2026-11-09)

Development notes from the private working tree (local branches, no CI).

## Where things are

| What | Where |
|---|---|
| Firmware branch | `ore-edk2-boot-yy3588`, branch `yy3588` (HEAD `75d25d93da`). Worktrees `-ddr`, `-usb`, `-hwfix`, `-usbhost`, `-ui`, `-pmic` are all merged. |
| bt0 (our first stage) | `boards/rk3588/yy3588/bt0` |
| RK806 / DDR / handoff code | `crates/rk3588` (`src/rk806.rs`, `src/ddr/`, `src/handoff`) |
| fastboot | `crates/rk3588-fastboot`, `crates/dwc3-udc`, `crates/fastboot` |
| EDK2 board overlay | `boards/rk3588/yy3588/overlay/edk2-rockchip/Platform/Youyeetoo/YY3588/` |
| edk2-rk3588 patches | `patches/yy3588/edk2-rk3588-yy3588/0001`–`0005`, pinned in `patches/yy3588/pin.env` |
| Ready-to-run files | `firmware-out/` (`SHA256SUMS`, `README.md`, `FASTBOOT.md`, `hw-logs/`) |
| Serial logs | `serial-logs/`, captured with `./serial-log.sh <label>` (screen session `yy3588-uart`, picocom 1500000) |
| Mainline U-Boot A/B test | `firmware-out/uboot-ab/` (patch, config fragment, FIT source, base commit); build tree is a scratch clone of `~/src/u-boot` |
| Independent review of this doc | `docs/yy3588-investigation-2026-11-09.md` (corrections folded in below) |

## Works on hardware

- **Stepping stone over MaskROM USB**, no eMMC writes. The chain is rkbin DDR init → our bt0 → TF-A v2.15 → EDK2. Load it with `rkdeveloptool db YY3588_rkbinddr_draminfo_loader.bin`.
- **dram-info mode.** The board has LPDDR4X, 4 channels × 2 ranks of x8 dies, 32 GiB, Micron (MR5 0xFF, MR8 0x58). The OS_REG decode matches the blob's banner.
- **USB fastboot in bt0** on the USB-C OTG port (DWC3 3.00a). `fastboot boot <fit>` boots EDK2 from RAM. Use the padded `yy3588-fit-DEBUG.itb` / `yy3588-fit-RELEASE.itb`.
- **EDK2** reaches its menu on HDMI and on serial. The garbled-repaint loop is fixed by patch 0005.
- **RK806 PMIC over SPI2** reads correctly once read the Linux way (header, then receive-only): chip 0x8062. It is ACTIVE with all 21 rails enabled.

## Resolved: serial input (2026-11-09 05:50)

With a different USB port and serial adapter, the echo, the pull-setting effect and the garbled output all disappeared (`serial-logs/2026-11-09-0549-railhunt.log`: 0 echo bytes, every kill-test line printed). Serial keyboard input then worked in EDK2 (RELEASE FIT via `fastboot boot`). The serial symptoms came from the previous port/adapter setup, not from bt0, TF-A or EDK2. No firmware change was needed. The vendor FCR/MCR values (`75d25d93da`) and EDK2 patch 0004 stay in.

Still open: the USB keyboard (carrier `VCC3V3_SYS` off). `0a6f9820f8` drove the vendor boot-on GPIOs (GPIO2_C5, GPIO2_C1, GPIO1_D2) high; the rail stayed ABSENT after each.

## Open problems

1. **No serial input in EDK2.** TX works. Typed keys never arrive intact: of the 567 bytes EDK2 saw, 566 were 0xFF (a lone start-bit pulse) and one was 0xDF. The RX pad receives a clean copy of the board's own TX output (see corrections below).
2. **No USB keyboard in EDK2.** The GL3523 USB3 hub, upstream on TYPEC1 = USB3OTG1 (0xFC400000) / u2phy1 / USBDP1, is never seen: u2phy1 linestate 0, ccs 0. Cause (per the review): the carrier's 3.3 V rail `VCC3V3_SYS` is off, and the GL3523 takes all its 3.3 V from it. EDK2's USB PHY and DWC3 setup is correct.
3. Both work under the vendor Android image with the same adapter (PL2303), cable and header. The adapter and wiring have been ruled out.

## What was tried, in order, and what it showed

### Serial

| Try | Result |
|---|---|
| Set the UART2 pins to pull `11` in bt0 (`d19d8b72ba`) | TX died. Reverted (`f7e7200e5d`). |
| EDK2 patch 0004: drop received bytes flagged BI/FE/PE | Garbage gone, but no valid input either |
| RX probe in bt0 (`a53b53f094`): dump the pad/UART state, then listen 5 s each with RX pull as-is, `00`, `10`, and Schmitt on | At start the RX FIFO was already full of error bytes (`lsr=0xa1 usr=0x1f rfl=64`). The board's TX garbled during every typing phase. No pad setting helped. |
| Vendor U-Boot/SPL source (`yy3588_u-boot`) | UART2 setup is identical to bt0. The SPL has no PMIC, regulator or GPIO-power code. Its only extra early writes are I2S MCLK input, eMMC drive strength, PCIe/SATA PHY resets, powering down USB2 PHY1–3, and an HDMI PHY reset. Nothing related to the UART or the rails. |
| Vendor kernel DTS (`rk3588-yyt.dts` and includes) | No GPIO enables the carrier 5 V/3.3 V rails; `vcc5v0_sys` is fixed and always on. No IO-domain node exists for RK3588. UART2 uses `uart2m0_xfer` with `pcfg_pull_up`. |
| radxa rkbin `develop-v2026.09` | Same DDR blob (v1.24) and SPL (v1.14) as ours; only BL31 is newer (1.58 vs 1.56). Nothing relevant. |
| Collabora notes and Collabora U-Boot (`collabora/u-boot`, branch `rockchip`) | Mainline plus FUSB302/TCPM and network fixes. The RK3588 pinctrl pull code matches. The useful clue: Rock 5B runs USB3OTG1 host through `u2phy1` + `usbdp_phy1`. |
| Mainline U-Boot v2026.10-rc4 MaskROM loader (DDR + SPL + FIT) | The transfer succeeded, but SPL printed nothing after the DDR init. |
| Mainline U-Boot proper booted by bt0 fastboot (`yy3588-uboot-ab.itb`, same TF-A as EDK2) | Runs every early init step, then goes silent in `serial_init`. The trace points inside the ns16550 probe and the clock driver never print. So it stops, or loses output, at the step before the driver probe: the pinctrl `default` state for the UART2 pins. |

### Corrections from the review (2026-11-09)

| This doc said | Corrected |
|---|---|
| RX FIFO full of error bytes at start (`lsr=0xa1 usr=0x1f rfl=64`) | LSR 0xa1 is RFE+THRE+DR with BI/FE/PE/OE clear. The FIFO holds a clean, correct-polarity copy of the line bt0 had just printed, accumulated over ~228 lines because bt0 wrote FCR=0x01 (no FIFO reset). Only some bytes carry FE. |
| TX garbled during every typing phase | Phases 2 (B6 pull `00`) and 3 (B6 pull `10`, also none) produced **no TX at all**. The garbage seen is the phase-4 announcement misframed by the host after a short low pulse: zero bit flips, zero baud drift, identical across four runs, with or without typing. |
| No pad setting helped | Schmitt on B6 made RX decode cleanly (it decodes the echo). Removing B6's pull-down killed TX. |
| Pull-up on TX/RX kills output, explained by a missing PMUIO2 supply | **Not supported.** RK3588 has no IO-voltage register, and PMUIO2 pads demonstrably work: I2C0 to the RK8602 regulators runs on GPIO0_D1/D2 without errors. BUCK8 `vcc_3v3_s3` (the probable PMUIO2 supply) is on at its 3.3 V OTP default. The clean echo needs a resistive TX-to-RX path and an RX node the adapter is not driving firmly; coupling inside the IO cell would be millivolts and inverted. |
| Carrier 3.3 V ABSENT is suspect / a symptom of the IO-supply problem | **Real.** `VCC3V3_SYS` is off: the GL3523, RTL8211F (PHY ID 0), I2C6 (RTC timeouts), u2phy0 VBUS-detect pull-up, HDMI HPD and DDC shifters and J43 pin 4 are all dead. EDK2 never read an EDID; it fell back to 640x480. The carrier 5 V rail is **on** (the FE1.1s on USB20_HOST0 enumerates in every run), although both rails share the `PMIC_EXT_EN_OUT` enable (R372 to the NB679 for 5 V, R18 to the NB680 for 3.3 V). Possible causes: R374 fitted making 5 V always-on, an enable level between the two thresholds, or an NB680 fault. Why it differs from Android is unexplained. |
| Mainline U-Boot hangs in `serial_init` | Not a hang. `pinctrl_select_state("default")` writes `PMU2_IOC GPIO0B_P` 0x5400 → 0x7C00 (B5/B6 = `11`, pull-up), byte for byte what bt0 `d19d8b72ba` did, and TX goes silent. The missing `T clk probe` trace is a red herring: `clock-frequency = <24000000>` in `rk3588s-u-boot.dtsi` skips the CRU lookup. |
| MaskROM misbehaves with the adapter connected | No control run without the adapter exists; unsupported so far. |

bt0's UART2 path has no register-level bug: every pad, mux, clock and UART write matches vendor U-Boot and the kernel. The only differences were FCR 0x01 vs 0x07 and MCR unwritten vs 0x03; both now use the vendor values (`75d25d93da`). MCR read 0, so internal loopback is ruled out.

### Original finding: the pull encoding, and the (now unsupported) IO-supply hypothesis

- U-Boot and Linux mark every RK3588 GPIO bank `PULL_TYPE_IO_1V8_ONLY`. For that type, `00` = none, `01` = pull-down, `10` = none, `11` = pull-up. Our earlier notes had `01` = pull-up, which was wrong.
- After reset the UART pins read `PMU2_IOC GPIO0B_P = 0x5400`, so B5 (TX), B6 (RX) and B7 have **pull-downs**.
- Writing pull-**up** (`11`) to TX/RX kills the output in both our bt0 and mainline U-Boot. Android's pinctrl writes the same value and works.
- A pull-up should not silence a working TX driver. A missing or wrong IO supply for the pad domain (PMUIO2) explains all the symptoms together. The pads would then run on current leaking in from the adapter's TX line through the RX pad's protection diode:
  - TX garbles exactly while RX is driven low (when you type).
  - RX reads junk, and the UART sits BUSY with a full error FIFO.
  - A pull-up on TX/RX loads the leaked supply and output stops.
  - MaskROM misbehaves while the serial adapter (or USB-C) is connected.
- Under Android, the vendor U-Boot/kernel regulator setup would correct a rail that sits outside its DTS constraints. Nothing in our chain or in mainline U-Boot's early stage does that.
- The same missing supply would also explain the earlier "carrier 3.3 V ABSENT" probe result. Note that the J43 ESD parts (ESD5451N) clamp to ground, not to VCC, so the leak path would be inside the SoC pad.

### USB

| Try | Result |
|---|---|
| EDK2 USB clocks, PHY bring-up order and state dumps (`9eadfe2ff5`, `47420cef4a`) | All clocks on, USBDP1 locks; u2phy1 linestate 0. The hub is never seen. |
| Carrier 3.3 V probe at bt0 and EDK2 time | I2C6 SCL/SDA, GMAC1 MDIO and u2phy0 sessvld all read 0, so the probe says ABSENT. The vendor DTS shows no software rail enable, so this is suspect: possibly the same IO-supply problem. |
| Vendor DTS for USBDP1 | `rockchip,dp-lane-mux = <2 3>`: USB3 on lanes 0/1. `usbdrd_dwc3_1` is enabled. The mainline U-Boot A/B image includes `u2phy1` + `usbdp_phy1` + `usb_host1_xhci`, but it never got past `serial_init`. |

## Next step (built, not yet run; superseded by the section after this one)

`firmware-out/YY3588_rkbinddr_draminfo_loader.bin` (branch `96e81bcc20`) now prints every RK806 rail: VSEL, decoded mV and enable bit, read-only. Compare against the vendor DTS:

| Rail | Expected (DTS) |
|---|---|
| buck8 `vcc_3v3_s3` | 3.3 V |
| buck10 `vcc_1v8_s3` | 1.8 V |
| pldo4 `vcc_3v3_s0` | 3.3 V |
| pldo2 `vcc_1v8_s0` | 1.8 V |
| pldo6 `pldo6_s3` | 1.8 V |
| buck7 `vdd_2v0_pldo_s3` | 2.0 V |

Run:

```
./serial-log.sh rails
cd firmware-out && rkdeveloptool db YY3588_rkbinddr_draminfo_loader.bin
```

If a supply rail sits off its DTS value, programming it in bt0 (as `ddr_rails` already does for BUCK5/NLDO2) is the candidate fix for both the serial input and the hub.

## Next run: RX probe v2 and the rail dump (built, not yet run)

`firmware-out/YY3588_rkbinddr_draminfo_loader.bin` (`75d25d93da`) has both the rail dump and the RX probe v2. It runs before fastboot, about 10 s:

1. **echo:** reset the FIFOs, stay silent 1 s and count RX bytes, then print `rxprobe echo: ABC...789` and print what RX caught.
2. **bridge:** B5/B6 as GPIO with TX silent. Drive B5 low/high and read B6 under each B6 pull, and read both as inputs. B6 following B5 means a resistive B5–B6 path. B6 high while B5 is low means the adapter is driving RX.
3. **kill:** one pull change on one pin at a time (B6 up, B5 up, B6 none, B5 none), each with a known line printed under it, then restored. A missing `rxprobe kill [...] THE QUICK BROWN FOX` line names the setting that kills TX.
4. **type:** 5 s listen with clean FIFOs.

Run it twice: once as wired, and once with the adapter's TX lead lifted from J43 pin 3. In the second run, a nonzero `rx caught` count or echo means the echo path is on the board side.

```
./serial-log.sh probe2
cd firmware-out && rkdeveloptool db YY3588_rkbinddr_draminfo_loader.bin
```

An Android capture with the same leads (`./serial-log.sh android`, type a few keys) would make the "Android works" control current; there is none in `serial-logs/` yet.

Multimeter checks that would settle the 3.3 V rail question are listed in the review doc (J43 pin 4, `PMIC_EXT_EN_OUT` at R18/R372, U2 EN/PG, whether R374/R17 are fitted).

## Mistakes made along the way

- I claimed the serial adapter re-enumerated. It hadn't; I was reading the tty's mtime.
- I blamed the PL2303 adapter and the wiring. Both were ruled out by Android working.
- I read the RK806 echo as loopback. The configure step clears LBK.
- I used the TRM/Linux-default pull encoding for RK3588. RK3588 uses the 1V8-only table (`11` = pull-up).
- I read the full RX FIFO as error bytes; it was the board's own output echoed back.
- I recorded the rxprobe phases 2/3 as "garbled" when they produced no TX at all.
- I proposed a missing PMUIO2 supply; the review showed PMUIO2 pads working (I2C0) and no IO-voltage register on RK3588.
- I treated the carrier 3.3 V ABSENT result as suspect; it is real and is the USB hub cause.

## Correction (2026-11-10): the carrier 3.3 V rail is not permanently off

The rail state changed between sessions on 2026-11-09 with the same firmware chain:

| Session (serial-logs/) | bt0 probe | Evidence |
|---|---|---|
| 02:51 – 07:38 (`*-run`, `railhunt`, `uboot-ab*`) | ABSENT / OFF | u2phy0 sessvld 0 although booted over MaskROM USB |
| 09:44 – 15:26 (`0944-run`, `1054/1056-cru-*`, `1145-no-pcie3`, `1526-vendor-kernel`) | **on** (scl=1 sda=1 mdio=1 sessvld=1) | EDK2: `RealtekPhyInit: Found Realtek RTL8211F GbE PHY` (1145 log, twice) |
| 19:01 (`1901-armbian`, Armbian U-Boot + vendor kernel, and our bt0) | OFF | only root hubs enumerate, no PHY |

So the "why does Android differ" question is really "what differed physically between 07:38, 09:44 and 19:01": power source (DC jack vs USB-C PD), USB-C cable/port, cold power-cycle vs warm reset, attached peripherals. The Android DTB (`rk3588-yyt-lp4-v10`, extracted from `yy3588_android14.0_*-001.img`) has no rail enable either; its only extra GPIO regulator is `vcc_camera1` on GPIO1_B2, which the schematic routes to the camera header and BTB only. The ethernet link LEDs are a sufficient meter: lit with a cable in = rail on.
