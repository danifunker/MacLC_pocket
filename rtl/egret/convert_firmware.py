#!/usr/bin/env python3
# Convert Egret ROM binary to hex format for Verilog $readmemh
#
# IMPORTANT: The ROM file is 4352 bytes (0x1100) and maps directly to
# CPU address range 0x0F00-0x1FFF. There is NO header to skip!
# The first 256 bytes (copyright notice) map to CPU 0x0F00-0x0FFF.

with open('341s0851.bin', 'rb') as f:
    data = f.read()

# ROM should be exactly 4352 bytes (0x1100) for full address range
if len(data) == 0x1100:
    print(f"ROM file is {len(data)} bytes - correct!")
elif len(data) == 0x1000:
    print(f"Warning: ROM is only 4KB, may be missing addresses 0x0F00-0x0FFF")
else:
    print(f"Warning: Unexpected file size: {len(data)} bytes (expected 0x1100)")

# Write all bytes to hex file - no header skip!
with open('egret_rom.hex', 'w') as f:
    for byte in data:
        f.write(f'{byte:02x}\n')

print(f"Converted {len(data)} bytes to egret_rom.hex")
print(f"ROM maps: CPU 0x0F00-0x{0x0F00 + len(data) - 1:04X}")
