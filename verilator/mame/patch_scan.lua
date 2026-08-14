-- patch_scan.lua — find the Gestalt-family RAM patch in MAME's guest RAM and
-- print the words around the suspect offset, as ground truth for mystery B.
--
-- Our core loads this routine with $0000 at guest $C01A, which desynchronises
-- the instruction stream into `andi.l #imm,-(A6)`; that predecrement unbalances
-- the LINK/UNLK frame so the epilogue RTS returns to $400E6C (the boot-blocks
-- 'LK' signature) and dies with an illegal instruction. MAME boots the same
-- image cleanly, so whatever MAME has at that word is what it SHOULD be.
--
-- Anchor: the routine body, known byte-for-byte from our guest RAM dump:
--     2078 02A6   movea.l ($2A6).w,A0     <- our $C01C
--     BC90        cmp.l   (A0),D6
--     6312        bls     +$12
--     2038 02AE   move.l  ROMBase,D0
--
-- NOTES (MAME 0.289):
--   * `print` is invisible under -video none — log to a file.
--   * A naive 6-word compare over the heap is ~1M Lua->C calls per pass and
--     starves the emulation; prefilter on the first word.
--
-- Run: mame maclc ... -autoboot_script verilator/mame/patch_scan.lua -autoboot_delay 0

local space = manager.machine.devices[":maincpu"].spaces["program"]
local LOG   = "/Users/dani/repos/MacLC_pocket/scratch/mame_patch.txt"

local ANCHOR = { 0x2078, 0x02a6, 0xbc90, 0x6312, 0x2038, 0x02ae }
local SCAN_LO, SCAN_HI = 0x1000, 0x80000
local done, frames = false, 0

local function log(s)
    local f = io.open(LOG, "a"); f:write(s .. "\n"); f:close()
end

local function scan()
    for a = SCAN_LO, SCAN_HI - 16, 2 do
        if space:read_u16(a) == ANCHOR[1] then           -- cheap prefilter
            local ok = true
            for i = 2, #ANCHOR do
                if space:read_u16(a + 2 * (i - 1)) ~= ANCHOR[i] then ok = false break end
            end
            if ok then
                log(string.format("anchor at MAME %06X  (= our guest $C01C)", a))
                -- Full routine dump, laid out against OUR addresses so the
                -- two hexdumps can be diffed word for word.
                local base = a - 0x1C            -- MAME addr of our $C000
                for r = 0, 0x180 - 1, 16 do
                    local ws = {}
                    for k = 0, 14, 2 do
                        ws[#ws+1] = string.format("%04X", space:read_u16(base + r + k))
                    end
                    log(string.format("  %06X: %s", 0xC000 + r, table.concat(ws, " ")))
                end
                log(string.format("==> the word at our $C01A reads %04X in MAME",
                    space:read_u16(a - 2)))
                return true
            end
        end
    end
    return false
end

-- ★ keep the subscription in a GLOBAL: a local is garbage-collected and the
-- callback silently never fires (same trap as the taps in vram_256k.lua).
patchscan_sub = emu.add_machine_frame_notifier(function()
    if done then return end
    frames = frames + 1
    if frames > 200 and (frames % 120) == 0 then
        if scan() then
            log("FOUND after " .. frames .. " frames")
            done = true
        end
    end
    if frames > 20000 then
        log("anchor never appeared after " .. frames .. " frames")
        done = true
    end
end)
log("=== patch_scan started ===")
