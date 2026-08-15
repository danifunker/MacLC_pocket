-- pram_depth.lua — PRAM colour-boot experiment (2026-08-14 ledger, RESUME 08-14f).
--
-- Question: does the LC ROM accept a saved 8bpp video-mode record (XPRAM
-- 0x58=$83, monitor-match 0x59/0x5A=$A2/$02) and open the boot screen in
-- 8bpp — and does the answer change with VRAM size (512K native vs 256K SIMM)?
--
-- Oracle: writes to the pseudovia VIDEO CONFIG register (offset 0x10 of
-- $F26000-$F27FFF; v8.cpp via2_video_config_w). data&7 = depth code
-- 0=1bpp 1=2bpp 2=4bpp 3=8bpp 4=16bpp. Every write is logged with its PC.
-- (ScreenRow at $106 is NOT a depth witness — the LC line stride is fixed
-- per VRAM size regardless of depth.)
--
-- Env:
--   MONTYPE   : monitor sense forced at frame 1 (default 0x02 = 512x384)
--   V256      : "1" = model the 256K VRAM SIMM via the validated write-alias
--               taps on the ROM size-probe tails (from vram_256k.lua)
--   MAX_FRAME : exit after N frames (default 1500), snapshot taken first
--   OUT       : log file (default /tmp/pram_depth.txt)
--
-- Seed nvram/maclc/egret with the 256 PRAM bytes BEFORE launching; MAME
-- loads it into the Egret's XPRAM at startup (and saves back on exit).
--
-- Run: verilator/mame/run_mame.sh -autoboot_script verilator/mame/pram_depth.lua
-- (tap.lua gotchas apply: install taps on first frame_done, keep handles.)

local function envnum(n, d) local v = os.getenv(n); return v and (tonumber(v) or d) or d end
local MONTYPE   = envnum("MONTYPE", 0x02)
local V256      = (os.getenv("V256") == "1")
local MAX_FRAME = envnum("MAX_FRAME", 1500)
local OUT       = os.getenv("OUT") or "/tmp/pram_depth.txt"

local f = io.open(OUT, "w")
local function log(s) print(s); f:write(s .. "\n"); f:flush() end

local frame = 0
local installed = false
local cpu, space
pram_depth_taps = {}          -- global: taps die if garbage-collected
local in_mirror = false

local DEPTH = {[0]="1bpp","2bpp","4bpp","8bpp","16bpp"}

-- ★ MONTYPE is set via cfg/maclc.cfg (value= on the :v8:MONTYPE port), NOT
-- field:set_value — on MAME 0.289 set_value(2) landed as raw value 1
-- (portrait) and the ROM sensed the wrong monitor (M1 run, 2026-08-14).
-- Here we only VERIFY what the ROM will sense: a read of $F26010 returns
-- montype<<3 (v8.cpp via2_video_config_r).
local function set_montype()
	local sensed = (space:read_u8(0xf26010) >> 3) & 0x0f
	log(string.format("[pd] sensed montype = 0x%02X (want 0x%02X)%s",
		sensed, MONTYPE, sensed == MONTYPE and "" or "  ★ MISMATCH — fix cfg/maclc.cfg"))
end

local VBASE = 0xf40000
local function alias_tap(start, len, label)
	pram_depth_taps[#pram_depth_taps + 1] = space:install_write_tap(
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
	log(string.format("[pd] v256 alias tap %06x..%06x (%s)", start, start + len - 1, label))
end

local function setup()
	cpu = manager.machine.devices[":maincpu"]
	space = cpu.spaces["program"]
	set_montype()
	if V256 then
		alias_tap(VBASE + 0x3ff00, 0x100, "lo_tail")
		alias_tap(VBASE + 0x7ff00, 0x100, "hi_tail")
	end
	-- video-config write tap: pseudovia decodes (offset & 0x13); reg 0x10.
	pram_depth_taps[#pram_depth_taps + 1] = space:install_write_tap(
		0xf26000, 0xf27fff, "vidcfg",
		function(addr, data, mask)
			if (addr & 0x13) ~= 0x10 then return end
			-- byte lane: pseudovia regs are byte-wide; take the addressed byte
			local shift = (3 - (addr & 3)) * 8
			local byte = (data >> shift) & 0xff
			local pc = 0
			pcall(function() pc = cpu.state["CURPC"].value end)
			log(string.format("[pd] F%05d VIDCFG <- %02X (depth=%s) pc=%08X",
				frame, byte, DEPTH[byte & 7] or "?", pc))
		end)
	log(string.format("[pd] vidcfg tap installed, V256=%s MONTYPE=0x%02X", tostring(V256), MONTYPE))
end

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then installed = true; setup() end
	if frame % 300 == 0 then
		local ds = space:read_u16(0xaf0)
		local sr = space:read_u16(0x106)
		log(string.format("[pd] f=%5d ScreenRow=%4d DSErrCode=%d", frame, sr, ds))
	end
	if frame >= MAX_FRAME then
		manager.machine.video:snapshot()
		log("[pd] done, snapshot taken")
		manager.machine:exit()
	end
end)
