# Archived 2026-11-10: one-off loaders and images from the 2026-11-08/09 bring-up

Nothing here is current. Kept for the record (what ran on the board that day,
`serial-logs/` refer to these by name).

| Dir | What |
|---|---|
| `stepping-stone/` | first builds (`yy3588` at `e51a7022e4` and earlier): rkbinddr DEBUG/RELEASE eMMC images, skeleton image, bt0 pieces, idblocks, FITs, closure reports, the mainline U-Boot A/B loaders (`YY3588_upstream_uboot_loader.bin`, `yy3588-uboot-ab.itb`), their README/FASTBOOT.md/SHA256SUMS |
| `superseded-91bc254f6a/` | the set before that |
| `ab-no-uart-pull/` | draminfo loader with UART2 pulls off (serial RX A/B test; cause turned out to be the adapter/port) |
| `uboot-ab/` | source bits for the U-Boot A/B FIT |
| `hw-logs/` | first MaskROM run excerpt |
| `full/` | superseded one-shot images: `*-20261109.*` (rev a), `yy3588-fw-esp-{update,debug,vendorkernel}.simg`, the BL31/TF-A A/B FITs, the 1-bit PIO fastboot loader, an older draminfo loader, and the script copies of that day |
| `Armbian_*.simg` | Armbian 26.8.1 vendor-kernel image converted to sparse, booted 2026-11-09 19:01 for comparison |
