-- vram_256k.lua — model a 256K VRAM SIMM in stock MAME maclc (no rebuild).
--
-- A 256K SIMM has no A18: the upper 256K of the 512K VRAM window aliases the
-- lower 256K. The LC ROM sizes VRAM with a wrap test (write '512K' to
-- +$7FFFC, '256K' to +$3FFFC, read +$7FFFC back — ROM $A04BC38), so aliasing
-- WRITES is enough to make the driver detect 256K and build the 256K screen
-- world (ScreenRow=512 instead of 1024, depths capped at 8bpp).
--
-- ★ THE MAME DISPLAY WILL LOOK WRONG (sheared/doubled) in this run: MAME's
-- v8 screen_update still scans the 512K fixed-1024 layout. IGNORE THE
-- PICTURE. The verdict comes from the console heartbeat below:
--   ScreenRow=512  -> the ROM detected 256K and switched layouts (the fix
--                     mechanism works in real ROM code)
--   DSErrCode stays 0 past ~30 s of guest boot -> no Illegal Instruction
--   DSErrCode=3    -> the games disk still dies = theory wrong, report back
--
-- Run (games disk attached as the SCSI HD as usual):
--   mame maclc ... -autoboot_script verilator/mame/vram_256k.lua
--
-- Control run: same command WITHOUT this script — expect ScreenRow=1024
-- machine, games disk boots fine (the 512K/MiSTer-equivalent behavior).

local cpu   = manager.machine.devices[":maincpu"]
local space = cpu.spaces["program"]

local in_mirror = false
local taps = {}

local function tap_range(base, label)
    local t = space:install_write_tap(base, base + 0x7ffff, "v256_" .. label,
        function(offset, data, mask)
            if in_mirror then return end
            in_mirror = true
            local twin = offset ~ 0x40000
            local old  = space:read_u32(twin & ~3)
            space:write_u32(twin & ~3, (old & ~mask) | (data & mask))
            in_mirror = false
        end)
    taps[#taps + 1] = t
    print(string.format("[v256] write-alias tap installed at %08x (%s)", base, label))
end

-- 32-bit window (what the ROM probe uses) and the 24-bit mirror.
tap_range(0x50f40000, "32bit")
tap_range(0x00f40000, "24bit")

local frames = 0
emu.register_frame_done(function()
    frames = frames + 1
    if frames % 60 == 0 then
        local sr = space:read_u16(0x106)   -- ScreenRow
        local ds = space:read_u16(0xaf0)   -- DSErrCode
        print(string.format("[v256] f=%5d  ScreenRow=%4d  DSErrCode=%d",
                            frames, sr, ds))
    end
end)
