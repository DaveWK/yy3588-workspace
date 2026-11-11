#!/bin/bash
# Patch the vendor YY3588 kernel DTB (rk3588-yyt.dtb, vendor 6.1) for UEFI
# boot from the one-shot eMMC image. Labels are looked up in /__symbols__.
#
#   fiq_debugger  disabled  rk_fiqdbg_init hangs the vendor kernel on this
#                           board; the console is ttyS2 instead
#   uart2         okay      console=ttyS2,1500000n8
#   dsi0          disabled  no DSI panel attached
#   gmac1         clock_in_out "input" + gmac1_clkinout pinmux: the
#                           RTL8211F drives PHY0_CLKOUT125 into
#                           GMAC1_MCLKINOUT (schematic docs/YY3588_V3.pdf)
#   rgmii_phy     no reg    stmmac scans the MDIO bus for the PHY
#   --no-fusb302  fusb302@22 disabled: with the carrier 3.3 V rail down the
#                 vendor driver retries its I2C reads forever and the
#                 kernel never mounts root (diagnostic builds only)
#
# Usage: mk-yy3588-dtb.sh <rk3588-yyt.dtb> <out.dtb> [--no-fusb302]
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ] || { [ $# -eq 3 ] && [ "$3" != --no-fusb302 ]; }; then
    sed -n '2,17p' "$0" >&2
    exit 2
fi
in=$1
out=$2

sym() { fdtget -t s "$out" /__symbols__ "$1"; }

cp "$in" "$out"
fdtput -t s "$out" "$(sym fiq_debugger)" status disabled
fdtput -t s "$out" "$(sym uart2)" status okay
fdtput -t s "$out" "$(sym dsi0)" status disabled

gmac=$(sym gmac1)
clkinout=$(fdtget -t u "$out" "$(sym gmac1_clkinout)" phandle)
read -ra pins <<<"$(fdtget -t u "$out" "$gmac" pinctrl-0)"
fdtput -t s "$out" "$gmac" clock_in_out input
fdtput -t u "$out" "$gmac" pinctrl-0 "${pins[@]}" "$clkinout"
fdtput -d "$out" "$(sym rgmii_phy)" reg

if [ $# -eq 3 ]; then
    fusb=$(fdtget -l "$out" /i2c@fec80000 | grep '^fusb302@')
    fdtput -t s "$out" "/i2c@fec80000/$fusb" status disabled
fi
