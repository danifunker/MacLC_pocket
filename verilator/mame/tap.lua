-- tap.lua — reusable MAME memory-access tap for comparing the LC core to MAME.
--
-- Installs a read and/or write tap on the maincpu (68020) program space over an
-- address range and logs frame / PC / offset / data to a file.  Use it to learn
-- what value MAME's hardware returns where our core diverges (see docs/mame_compare.md).
--
-- Configure via environment variables (all optional):
--   TAP_LO    : range low  (hex or dec), default 0xf40000  (VRAM top-left)
--   TAP_HI    : range high, default 0xf40003
--   TAP_MODE  : "r", "w", or "rw" (default "w")
--   TAP_OUT   : output file, default /tmp/mame_tap.txt
--   TAP_FILT  : only log when (offset & ~0) <= this (hex/dec); default = TAP_HI
--   MAX_FRAME : exit after this many frames, default 1100
--
-- Run via:  run_mame.sh -autoboot_script verilator/mame/tap.lua
--
-- GOTCHAS (the reason this script exists — see docs/mame_compare.md):
--  * Install the tap on the FIRST register_frame_done, NOT machine_reset /
--    register_start: those fire before the autoboot script is loaded, so the
--    tap never installs (silent 0 hits).
--  * Keep the tap handle in a Lua table so it is not garbage-collected.
--  * The debugger's printf/logerror do NOT reliably reach any sink when headless;
--    write to a file from the tap callback instead (this script).

local function envnum(name, dflt)
	local v = os.getenv(name)
	if not v then return dflt end
	return tonumber(v) or dflt
end

local TAP_LO   = envnum("TAP_LO",   0xf40000)
local TAP_HI   = envnum("TAP_HI",   0xf40003)
local TAP_MODE = os.getenv("TAP_MODE") or "w"
local TAP_OUT  = os.getenv("TAP_OUT")  or "/tmp/mame_tap.txt"
local TAP_FILT = envnum("TAP_FILT", TAP_HI)
local MAX_FRAME= envnum("MAX_FRAME", 1100)

local f = io.open(TAP_OUT, "w")
local frame = 0
local installed = false
local cpu, space
local taps = {}   -- keep references alive

local function logacc(kind, off, data, mask)
	if off > TAP_FILT then return end
	local pc = 0
	pcall(function() pc = cpu.state["CURPC"].value end)
	f:write(string.format("F%05d %s off=%08X data=%08X mask=%08X pc=%08X\n",
	                      frame, kind, off, data, mask, pc))
	f:flush()
end

local function setup()
	cpu = manager.machine.devices[":maincpu"]
	space = cpu.spaces["program"]
	f:write(string.format("# tap lo=%08X hi=%08X mode=%s\n", TAP_LO, TAP_HI, TAP_MODE))
	if TAP_MODE:find("r") then
		taps[#taps+1] = space:install_read_tap(TAP_LO, TAP_HI, "RD",
			function(off, data, mask) logacc("RD", off, data, mask) end)
	end
	if TAP_MODE:find("w") then
		taps[#taps+1] = space:install_write_tap(TAP_LO, TAP_HI, "WR",
			function(off, data, mask) logacc("WR", off, data, mask) end)
	end
	f:flush()
end

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then installed = true; setup() end
	if frame >= MAX_FRAME then f:flush(); manager.machine:exit() end
end)
