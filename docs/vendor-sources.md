# youyeetoo sources used

Not included here; fetch them from youyeetoo.

## Documents

From youyeetoo's download area (linked from <https://wiki.youyeetoo.com/en/YY3588>):
`YY3588_V3.pdf` (carrier schematic, the page numbers in the notes),
`YY3588  TOP.dxf` / `BOT.dxf` (component placement, used for the J43 / J51
pin order), `YY3588  DEV KIT_V3.0.pcb`, `YY3588_MBV3.dsn`, STEP models,
`TOP位号.pdf` / `BOTTOM位号.pdf`.

## Images

| Image | Use |
|---|---|
| `yy3588_linux6.1_release_dsi0_v1.0_20251203.img` | stock Debian/Linux 6.1, source of the vendor kernel behaviour |
| `yy3588_android14.0_dsi0_hdmi_edp_dp-001.img` | stock Android 14; flashed with `upgrade_tool` v2.36 as the "is it our firmware?" control |
| `Armbian_26.8.1_Youyeetoo-yy3588_trixie_vendor_6.1.115_minimal.img` | Armbian, vendor 6.1.115 (`serial-logs/*armbian*`) |

## SDK repositories (github.com/youyeetoo, branch `rk1828`)

The vendor kernel `Image`, `rk3588-yyt.dtb` and Debian rootfs fed to
`scripts/mk-full-image.sh` were built from these commits:

| Repository | Commit |
|---|---|
| [yy3588_linux](https://github.com/youyeetoo/yy3588_linux) | `c27d44f862d0083901724135a83f4ea61c4d0dd9` |
| [yy3588_u-boot](https://github.com/youyeetoo/yy3588_u-boot) | `59d9f7d0d4c7304646bf063e006f78ac448402a7` |
| [yy3588_rkbin](https://github.com/youyeetoo/yy3588_rkbin) | `3e288fe814e059dd06833495f845cab04ac20a5c` |
| [yy3588_sdk-bsp](https://github.com/youyeetoo/yy3588_sdk-bsp) | `432f98619a051c1c510eb3b9ff6d66413b5dee13` |
| [yy3588_buildroot](https://github.com/youyeetoo/yy3588_buildroot) | `12b8c0635dc872dd73df053612fdcf15f5b2efed` |
| [yy3588_extras](https://github.com/youyeetoo/yy3588_extras) | `8def12d32cd977ae78c0efbddca923cf45c939c5` |

Kernel: `arch/arm64/boot/Image` and
`arch/arm64/boot/dts/rockchip/rk3588-yyt.dtb` of `yy3588_linux` (RKNPU and
the RK1828 `pcie-rkep` driver built in). Rootfs: `output/rootfs.img` of the
SDK build. `systemd-bootaa64.efi`: any aarch64 systemd-boot (e.g. Debian's
`systemd-boot-efi` package).

Mainline DT for reference:
[rk3588-youyeetoo-yy3588.dts](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/rockchip/rk3588-youyeetoo-yy3588.dts).
