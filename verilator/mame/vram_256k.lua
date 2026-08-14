-- vram_256k.lua — model a 256K VRAM SIMM in stock MAME maclc (no rebuild).
--
-- A 256K SIMM has no A18: the upper 256K of the 512K VRAM window aliases the
-- lower 256K. The LC ROM sizes VRAM with a wrap test (write '512K' to
-- +$7FFFC, '256K' to +$3FFFC, read +$7FFFC back — ROM $A04BC38), so aliasing
-- WRITES in the probe windows is enough to make the driver detect 256K and
-- build the 256K screen world (ScreenRow=512 instead of 1024, depths capped
-- at 8bpp).
--
-- VALIDATED 2026-08-14 on MAME 0.264 against System 7.1: ScreenRow=512,
-- clean boot to desktop, wrap test observed live at PC $A4BC4C/$A4BC58.
-- Three hard-won corrections from that run (do not regress them):
--   * install_write_tap callbacks receive the ABSOLUTE address, not a
--     window-relative offset — toggle A18 of (addr - window base).
--   * Tap only the 24-bit window $F40000-$FBFFFF. $50F40000 is outside the
--     68020 global address mask (0x80ffffff) in MAME and aliases to $F40000
--     anyway; installing there errors.
--   * A full-512KB write tap runs at ~1% speed. Tapping just the last 256
--     bytes of each half (the probe targets, which sit in scanout stride
--     padding) is sufficient and full speed.
--
-- ★ THE MAME DISPLAY WILL LOOK SQUASHED in this run: v8.cpp screen_update
-- hardcodes the 1024-byte stride, so it shows two guest rows per line once
-- the guest switches to 512-byte rows. IGNORE THE PICTURE — judge by the
-- guest's own memory (ScreenRow at $106).
--
-- Run: mame maclc ... -autoboot_script verilator/mame/vram_256k.lua -autoboot_delay 0

local cpu   = manager.machine.devices[":maincpu"]
local space = cpu.spaces["program"]

local VBASE = 0xf40000            -- 24-bit VRAM window base
local in_mirror = false
vram256k_taps = {}                -- global: taps die if garbage-collected

local function tap_window(start, len, label)
    vram256k_taps[#vram256k_taps + 1] = space:install_write_tap(
        start, start + len - 1, "v256_" .. label,
        function(addr, data, mask)
            if in_mirror then return end
            in_mirror = true
            local rel  = (addr - VBASE) & 0x7ffff
            local twin = VBASE + (rel ~ 0x40000)
            local old  = space:read_u32(twin & ~3)
            space:write_u32(twin & ~3, (old & ~mask) | (data & mask))
            in_mirror = false
        end)
    print(string.format("[v256] alias tap %06x..%06x (%s)", start, start + len - 1, label))
end

-- The ROM's size-probe targets: last 256 bytes of each 256K half.
tap_window(VBASE + 0x3ff00, 0x100, "lo_tail")
tap_window(VBASE + 0x7ff00, 0x100, "hi_tail")

local frames = 0
emu.register_frame_done(function()
    frames = frames + 1
    if frames % 60 == 0 then
        local sr = space:read_u16(0x106)   -- ScreenRow
        local ds = space:read_u16(0xaf0)   -- DSErrCode (40 = dsGreeting, normal)
        print(string.format("[v256] f=%5d  ScreenRow=%4d  DSErrCode=%d", frames, sr, ds))
    end
end)
