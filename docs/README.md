# Notes

Written during the bring-up, in order. Start with the night handoff.

| File | What |
|---|---|
| [handoff-2026-11-10-night.md](handoff-2026-11-10-night.md) | state at end of 2026-11-10: board status, the J43 wiring fault, what was ruled out, RK806 restart codes, next steps |
| [handoff-2026-11-10.md](handoff-2026-11-10.md) | the 2026-11-10 log hour by hour, with every measurement |
| [yy3588-investigation-2026-11-09.md](yy3588-investigation-2026-11-09.md) | 2026-11-09 investigation |
| [yy3588-firmware-status-2026-11-09.md](yy3588-firmware-status-2026-11-09.md) | 2026-11-09 firmware status and debugging log |
| [vendor-sources.md](vendor-sources.md) | youyeetoo SDK repositories, images and documents used |
| [firmware-out/](firmware-out/) | notes that went with the built images: flashing, test procedure, the first MaskROM dram-info run |

These notes were written against the private development tree. Paths and
commit hashes in them map to this repository as follows:

| In the notes | Here |
|---|---|
| `ore-edk2-boot-yy3588/boards/rk3588/yy3588/bt0`, `crates/`, `tools/rk-*` | `firmware/oreboot/src/mainboard/youyeetoo/yy3588/{bt0,crates,tools}` |
| `ore-edk2-boot-yy3588/src/edk2-rk3588-yy3588`, `patches/yy3588/*`, `boards/rk3588/yy3588/overlay` | `firmware/edk2-rk3588` (patches and overlay applied) |
| `make yy3588*` in `ore-edk2-boot-yy3588/` | `make yy3588*` here |
| `../mk-*.sh`, `../mk-*.py`, `./serial-log.sh` | `scripts/` |
| `firmware-out/**/*.md` (README, FASTBOOT, hw-logs) | [firmware-out/](firmware-out/) |
| `firmware-out/` images, `vendor-downloads/`, `yy3588_*/` | not published (build outputs, vendor images, vendor SDK checkouts); rebuild with `make` |
| `docs/YY3588_V3.pdf`, `YY3588  TOP.dxf`, ... | youyeetoo's files, see vendor-sources.md |
| private commits up to `1f376d4fe6` | squashed into the `yy3588` branches of the two forks |

`docs/YY3588_V3.pdf` page references are to the youyeetoo YY3588 V3
schematic.
