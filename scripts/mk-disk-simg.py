#!/usr/bin/env python3
"""Android sparse image of a whole-disk raw image whose last data partition
holds an ext4 filesystem, for fastboot flash emmc.

The rootfs part comes from `ext2simg` (e2fsprogs): only blocks the ext4
bitmaps mark as in use are written, free blocks are DONT_CARE, and the
partition beyond the end of the filesystem (it grows on first boot) is
skipped. Everything else in the raw image is written: RAW for data, zero FILL
for zero blocks. The last MiB (backup GPT) is written the same way.

bt0 writes zero fills one eMMC command per 4 KiB, so turning the empty part
of the rootfs partition into skips is what keeps the flash short.

Usage: mk-disk-simg.py <disk.img> <rootfs_start_bytes> <rootfs.simg> <out.simg>
"""
import struct
import sys

BLK = 4096
MAGIC = 0xED26FF3A
RAW, FILL, SKIP, CRC = 0xCAC1, 0xCAC2, 0xCAC3, 0xCAC4
TAIL = 1024 * 1024


def raw_chunks(data: bytes):
    """RAW runs for data blocks, zero FILL runs for zero blocks."""
    zero = bytes(BLK)
    out = []
    for i in range(0, len(data), BLK):
        blk = data[i:i + BLK]
        kind = FILL if blk == zero else RAW
        if out and out[-1][0] == kind:
            out[-1][1] += 1
            if kind == RAW:
                out[-1][2].extend(blk)
        else:
            out.append([kind, 1, bytearray(blk) if kind == RAW else bytearray(4)])
    return [(k, n, bytes(d)) for k, n, d in out]


def read_simg(path: str):
    """Chunks of a sparse image (CRC chunks dropped) and its block count."""
    with open(path, "rb") as f:
        hdr = f.read(28)
        magic, major, _minor, fhs, chs, bs, blocks, nchunks, _crc = struct.unpack("<IHHHHIIII", hdr)
        if magic != MAGIC or major != 1 or bs != BLK:
            raise SystemExit(f"{path}: not a v1 sparse image with {BLK}-byte blocks")
        f.seek(fhs)
        chunks = []
        for _ in range(nchunks):
            kind, _res, nblk, total = struct.unpack("<HHII", f.read(chs)[:12])
            body = f.read(total - chs)
            if kind == CRC:
                continue
            if kind not in (RAW, FILL, SKIP):
                raise SystemExit(f"{path}: chunk type {kind:#x}")
            chunks.append((kind, nblk, body))
    if sum(n for _, n, _ in chunks) != blocks:
        raise SystemExit(f"{path}: chunk blocks do not add up to {blocks}")
    return chunks, blocks


def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2
    disk_path, root_start, root_simg, out_path = sys.argv[1], int(sys.argv[2], 0), sys.argv[3], sys.argv[4]
    with open(disk_path, "rb") as f:
        f.seek(0, 2)
        disk = f.tell()
        if disk % BLK or root_start % BLK or not 0 < root_start < disk - TAIL:
            print("disk size / rootfs start not 4 KiB aligned or out of range", file=sys.stderr)
            return 1
        f.seek(0)
        head = f.read(root_start)
        f.seek(disk - TAIL)
        tail = f.read(TAIL)

    rootfs, root_blocks = read_simg(root_simg)
    gap = (disk - TAIL - root_start) // BLK - root_blocks
    if gap < 0:
        print("rootfs filesystem runs into the backup GPT", file=sys.stderr)
        return 1

    chunks = raw_chunks(head) + rootfs + [(SKIP, gap, b"")] + raw_chunks(tail)
    total = sum(n for _, n, _ in chunks)
    assert total * BLK == disk

    with open(out_path, "wb") as out:
        out.write(struct.pack("<IHHHHIIII", MAGIC, 1, 0, 28, 12, BLK, total, len(chunks), 0))
        for kind, nblk, data in chunks:
            out.write(struct.pack("<HHII", kind, 0, nblk, 12 + len(data)))
            out.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
