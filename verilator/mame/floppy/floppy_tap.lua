-- floppy_tap.lua — capture every CPU access to the VIA1 and SWIM/IWM windows of
-- MAME's `maclc`, in execution order, so we can reconstruct the drive-sense
-- (drive-ID) reads the Sony driver performs.  See docs/handoff_mame_floppy_driveid_2026-06-13.md.
--
-- Why a raw bus log + offline reconstruction (not a smart in-Lua decoder):
--   * The sense register index is {ca2,ca1,ca0,SEL}.  ca0/ca1/ca2 + q6/q7 are
--     IWM soft-switches inside $F16000-$F17FFF (toggled by *any* access — read OR
--     write — to base+(n<<9)); SEL/HDSEL is VIA1 Port-A bit5 ($F00000 window).
--     The two interleave, so we need ONE time-ordered log of both windows.
--   * The status (sense) read returns the sense bit in D7.  We capture the real
--     byte MAME returns, so post-processing just has to know *which* register was
--     addressed at that instant.
--
-- Env:
--   TAP_OUT   : output file (default /tmp/floppy_tap.txt)
--   MAX_FRAME : exit after this many frames (default 1200)
--
-- Run via run_floppy.sh (which sets -autoboot_script to this file).

local TAP_OUT   = os.getenv("TAP_OUT")  or "/tmp/floppy_tap.txt"
local MAX_FRAME = tonumber(os.getenv("MAX_FRAME") or "1200") or 1200

local VIA_LO,  VIA_HI  = 0xF00000, 0xF01FFF
local SWIM_LO, SWIM_HI = 0xF16000, 0xF17FFF

local f = io.open(TAP_OUT, "w")
local frame = 0
local seq = 0
local installed = false
local cpu, space
local taps = {}  -- keep handles alive (GC guard)

local function pcnow()
	local pc = 0
	pcall(function() pc = cpu.state["CURPC"].value end)
	return pc
end

-- VIA/SWIM live on the upper byte of the 68020's 32-bit longword (even Mac
-- addresses -> bits [31:24], mem_mask=0xFF000000).  Extract the active byte lane.
local function byte_of(data, mask)
	if (mask & 0xFF000000) ~= 0 then return (data >> 24) & 0xFF end
	if (mask & 0x00FF0000) ~= 0 then return (data >> 16) & 0xFF end
	if (mask & 0x0000FF00) ~= 0 then return (data >>  8) & 0xFF end
	return data & 0xFF
end

local function logacc(region, kind, off, data, mask)
	seq = seq + 1
	f:write(string.format("%08d F%05d %s %s off=%06X byte=%02X mask=%08X pc=%08X\n",
	                      seq, frame, region, kind, off & 0xFFFFFF, byte_of(data, mask), mask & 0xFFFFFFFF, pcnow()))
end

local function setup()
	cpu = manager.machine.devices[":maincpu"]
	space = cpu.spaces["program"]
	f:write(string.format("# floppy_tap VIA=%06X-%06X SWIM=%06X-%06X\n", VIA_LO, VIA_HI, SWIM_LO, SWIM_HI))
	taps[#taps+1] = space:install_read_tap (VIA_LO,  VIA_HI,  "VIArd",  function(o,d,m) logacc("VIA",  "RD", o, d, m) end)
	taps[#taps+1] = space:install_write_tap(VIA_LO,  VIA_HI,  "VIAwr",  function(o,d,m) logacc("VIA",  "WR", o, d, m) end)
	taps[#taps+1] = space:install_read_tap (SWIM_LO, SWIM_HI, "SWIMrd", function(o,d,m) logacc("SWIM", "RD", o, d, m) end)
	taps[#taps+1] = space:install_write_tap(SWIM_LO, SWIM_HI, "SWIMwr", function(o,d,m) logacc("SWIM", "WR", o, d, m) end)
	f:flush()
end

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then installed = true; setup() end
	if frame >= MAX_FRAME then f:flush(); manager.machine:exit() end
end)
