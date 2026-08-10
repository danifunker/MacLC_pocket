#!/usr/bin/env python3
"""Patch the Mac LC ROM (checksum 350EACF0) to skip the POST RAM test.

StartTest1 (USTStartup.a) decides between the full destructive RAM march and
the fast warm-start path by comparing the warm-start flag (stored 4 bytes
below the RAM chunk table) against 'WLSC':

  40846558:  0C83 574C 5343   cmpi.l  #'WLSC',d3     ; warm start?
  4084655E:  6600 0016        bne.w   $40846576      ; no  -> full RAM march
  40846562:  ...              bsr6    $40846746      ; yes -> quick read check
  4084656A:  4A80 6600 0008   tst.l d0 / bne.w $40846576
  40846570:  4247             clr.w   d7
  40846572:  6000 00BC        bra.w   $40846630      ; skip test, rejoin boot

Patch: replace the cmpi.l at ROM offset 0x46558 with `bra.s $46570`
(60 16), unconditionally taking the stock warm-start path. The 8 bytes
behind the branch become dead code; nothing else references them.

The header checksum (offset 0, sum of all big-endian words from offset 4)
is recomputed so the ROM checksum POST test still passes.
"""
import struct
import sys

PATCH_OFFSET = 0x46558
OLD = bytes.fromhex("0c83574c5343")  # cmpi.l #'WLSC',d3
NEW = bytes.fromhex("6016")          # bra.s *+0x18 -> 0x46570 (warm-start path)


def checksum(data: bytes) -> int:
    s = 0
    for (w,) in struct.iter_unpack(">H", data[4:]):
        s = (s + w) & 0xFFFFFFFF
    return s


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else "boot0.rom"
    dst = sys.argv[2] if len(sys.argv) > 2 else "boot0_skipramtest.rom"

    data = bytearray(open(src, "rb").read())
    if data[PATCH_OFFSET : PATCH_OFFSET + len(OLD)] != OLD:
        sys.exit(f"{src}: bytes at {PATCH_OFFSET:#x} don't match the expected "
                 f"cmpi.l #'WLSC' — wrong or already-patched ROM")

    data[PATCH_OFFSET : PATCH_OFFSET + len(NEW)] = NEW
    struct.pack_into(">I", data, 0, checksum(data))

    open(dst, "wb").write(data)
    print(f"{dst}: patched @ {PATCH_OFFSET:#x}, "
          f"new header checksum {checksum(data):08X}")


if __name__ == "__main__":
    main()
