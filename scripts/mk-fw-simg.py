#!/usr/bin/env python3
"""Firmware (and optionally ESP) Android sparse image for the YY3588 eMMC
(fastboot flash emmc), for updating a board flashed with mk-full-image.sh.

Writes bytes 32 KiB .. 8 MiB of the user area (idblock, FIT, UEFI variable
store) and skips everything else, so the GPT (LBA 0..33) and the rootfs stay
as they are. The variable store window 0x7C0000..0x7F0000 is erased (0xFF)
where the firmware image does not reach. With <esp.img>, the ESP partition
(16 MiB, at most 256 MiB) is rewritten too: raw chunks for data, zero fills
for empty blocks.

Usage: mk-fw-simg.py <firmware.img> <out.simg> [esp.img]
"""
import struct
import sys

BLK = 4096
START = 32 * 1024          # idblock offset
END = 8 * 1024 * 1024      # end of the firmware window
NV_START, NV_END = 0x7C0000, 0x7F0000

ESP_START, ESP_MAX = 16 * 1024 * 1024, 256 * 1024 * 1024

RAW, FILL, SKIP = 0xCAC1, 0xCAC2, 0xCAC3


def esp_chunks(esp: bytes):
    """RAW runs for data blocks, FILL (zero) runs for empty blocks."""
    zero = bytes(BLK)
    out = []
    for i in range(0, len(esp), BLK):
        blk = esp[i:i + BLK]
        kind = FILL if blk == zero else RAW
        if out and out[-1][0] == kind:
            out[-1][1] += 1
            if kind == RAW:
                out[-1][2].extend(blk)
        else:
            out.append([kind, 1, bytearray(blk) if kind == RAW else bytearray(4)])
    return [(k, n, bytes(d)) for k, n, d in out]


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    fw = open(sys.argv[1], "rb").read()
    if len(fw) <= START or len(fw) > END:
        print(f"firmware image size {len(fw)} outside {START}..{END}", file=sys.stderr)
        return 1

    region = bytearray(fw[START:END].ljust(END - START, b"\0"))
    for off in range(max(len(fw), NV_START), NV_END):
        region[off - START] = 0xFF

    chunks = [
        (SKIP, START // BLK, b""),
        (RAW, (END - START) // BLK, bytes(region)),
        (SKIP, (ESP_START - END) // BLK, b""),
    ]
    disk = ESP_START
    if len(sys.argv) == 4:
        esp = open(sys.argv[3], "rb").read()
        if len(esp) % BLK or len(esp) > ESP_MAX:
            print(f"ESP image size {len(esp)} not 4 KiB aligned or over 256 MiB", file=sys.stderr)
            return 1
        chunks += esp_chunks(esp)
        disk += len(esp)
    total = sum(n for _, n, _ in chunks)
    assert total * BLK == disk

    with open(sys.argv[2], "wb") as out:
        out.write(struct.pack("<IHHHHIIII", 0xED26FF3A, 1, 0, 28, 12, BLK, total, len(chunks), 0))
        for kind, nblk, data in chunks:
            out.write(struct.pack("<HHII", kind, 0, nblk, 12 + len(data)))
            out.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
