# First hardware run: MaskROM draminfo loader (2026-11-09)

`rkdeveloptool db YY3588_rkbinddr_draminfo_loader.bin` (built from `yy3588` at
`e51a7022e4`), UART2 M0 on J43 at 1500000 8N1. Excerpt; the per-channel `dram-info ctl`
and `dram-info phy` register dumps (1248 entries) are omitted here. Those are values the
rkbin blob programmed: comparison/debug only, never to be copied into our own init.

## rkbin DDR init banner (identification)

```
DDR a4ba73facc cym 26/06/26-12:04:20,fwver: v1.24
LPDDR4X, 2112MHz
channel[0] BW=16 Col=10 Bk=8 CS0 Row=18 CS1 Row=18 CS=2 Die BW=8 Size=8192MB
channel[1] BW=16 Col=10 Bk=8 CS0 Row=18 CS1 Row=18 CS=2 Die BW=8 Size=8192MB
channel[2] BW=16 Col=10 Bk=8 CS0 Row=18 CS1 Row=18 CS=2 Die BW=8 Size=8192MB
channel[3] BW=16 Col=10 Bk=8 CS0 Row=18 CS1 Row=18 CS=2 Die BW=8 Size=8192MB
Manufacturer ID:0xff
CH0 RX Vref:31.0%, TX Vref:21.8%,21.8%
CH1 RX Vref:28.5%, TX Vref:21.8%,21.8%
CH2 RX Vref:29.4%, TX Vref:21.8%,21.8%
CH3 RX Vref:29.4%, TX Vref:22.8%,21.8%
change to F1: 528MHz / F2: 1068MHz / F3: 1560MHz / F0: 2112MHz
stride=0x2, ddr_config=0x4
hash ch_mask0-1 0x20 0x40, bank_mask0-3 0xa00 0x1400 0x2800 0x0, rank_mask0 0x401000
out
```

## bt0 (stepping stone)

```
yy3588 bt0 stepping-stone (rkbin DDR init, DEV ONLY) at EL3
pmic rk806 chip_name=0x00
dram: Handoff LPDDR4X 32768 MiB (pairs 16384 + 16384)
dram-info osreg raw=3a561a56,300010f5,3a561a56,300010f5
dram-info pair=0 osreg version=3 type=LPDDR4X channels=2 size_mib=16384
dram-info pair=0 osreg ch=0 rank=2 col=10/10 bank_bits=3 row=18/18 bw_bytes_log2=1 dbw=2 row_3_4=0 size_mib=8192
dram-info pair=0 osreg ch=1 rank=2 col=10/10 bank_bits=3 row=18/18 bw_bytes_log2=1 dbw=2 row_3_4=0 size_mib=8192
dram-info pair=1 osreg version=3 type=LPDDR4X channels=2 size_mib=16384
dram-info pair=1 osreg ch=0 rank=2 col=10/10 bank_bits=3 row=18/18 bw_bytes_log2=1 dbw=2 row_3_4=0 size_mib=8192
dram-info pair=1 osreg ch=1 rank=2 col=10/10 bank_bits=3 row=18/18 bw_bytes_log2=1 dbw=2 row_3_4=0 size_mib=8192
dram-info mr ch=0 rank=0 mr0=0xbb mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0b
dram-info mr ch=0 rank=1 mr0=0x3b mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0b
dram-info mr ch=1 rank=0 mr0=0xbb mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0b
dram-info mr ch=1 rank=1 mr0=0x3b mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0b
dram-info mr ch=2 rank=0 mr0=0xbb mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0b
dram-info mr ch=2 rank=1 mr0=0x3b mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0b
dram-info mr ch=3 rank=0 mr0=0xbb mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0d
dram-info mr ch=3 rank=1 mr0=0x3b mr5=0xff mr6=0x07 mr7=0x00 mr8=0x58 mr12=0x24 mr14=0x0d
dram-info end entries=1248 record=0x1f0000
dram: quick check ok (1 MiB at 0x4000000)
fastboot: BootROM boot source 0xa (USB)
fastboot: USB-C OTG (USB3OTG0), 18d1:4ee0, download buffer 0x10000000 + 0x20000000
[usb] usb2phy0 status 0x0000: sessvld 0 vbusvalid 0 linestate 0
[usb] dwc3 GSNPSID 0x5533300a
[usb] device controller running, waiting for the host
[usb] high speed
[usb] high speed
[usb] configured
```

## What it established

- Board DRAM: LPDDR4X, 4 channels x16, dual rank, x8 (byte-mode) dies, col 10 / 8 banks /
  row 18, 8 GiB per channel, 32 GiB total. MR5 0xFF = Micron. MR8 0x58 = x8 I/O,
  32 Gb density (per die channel). MR6 0x07 / MR7 0x00 revision.
- Verified on hardware: BootROM → bt0 at DRAM 0x0 at EL3; UART console; OS_REG decoder
  (matches the blob's banner exactly); MRR through the DDRCTL after the blob; quick memtest;
  boot-source ID 0xa (USB) survives the DDR init; DWC3 bring-up and enumeration
  (configured by the host).
- Not working: RK806 SPI read (`chip_name=0x00`).
- Differs from the model: DWC3 GSNPSID 0x5533300a = revision 3.00a (model assumed 3.30a).
