-- vram_extent.lua — measure the OS's framebuffer write layout (the video oracle).
--
-- Taps EVERY CPU write into the V8 VRAM window ($F40000..$FBFFFF) from boot
-- through MAX_FRAME and reports, on exit, how wide and how tall the OS actually
-- writes the framebuffer:
--   * max byte-column within a 1024-byte scan line  (= rowBytes_pixels - 1)
--   * max scan line index                           (= screen height - 1)
--   * a coarse 64-byte-bucket histogram of the column distribution
--   * min/max absolute VRAM offset and total write count
--
-- WHY: the V8 hardware scans 1/2/4/8bpp at a FIXED 1024-byte stride starting at
-- VRAM offset 0 (see v8.cpp screen_update). So "max column" directly gives the
-- per-line pixel width the OS draws: 1bpp@640 -> 79, 4bpp@640 -> 319,
-- 8bpp@640 -> 639, 16bpp@512 -> 1022 (stride 1024 = 512 words). Capturing the
-- BOOT-time full-desktop fill reveals the true extent at the current depth.
--
-- The early boot VRAM clear/test writes the WHOLE 512KB (every column, every
-- line) and would mask the framebuffer width — so gate the measurement to a
-- frame window AFTER the clear, when the Finder is drawing the live desktop
-- (EXT_FROM..EXT_TO).
--
-- Env:
--   EXT_OUT   : output file           (default /tmp/vram_extent.txt)
--   EXT_FROM  : start counting at frame(default 0)
--   EXT_TO    : stop  counting at frame(default MAX_FRAME)
--   MAX_FRAME : exit after N frames    (default 2700)
--   VRAM_BASE : VRAM window base       (default 0xf40000)
--   VRAM_TOP  : VRAM window top        (default 0xfbffff)
--
-- Run: run_mame.sh -hard <hd.chd> -autoboot_script verilator/mame/vram_extent.lua

local function envnum(n, d) local v=os.getenv(n); return v and (tonumber(v) or d) or d end
local EXT_OUT   = os.getenv("EXT_OUT") or "/tmp/vram_extent.txt"
local MAX_FRAME = envnum("MAX_FRAME", 2700)
local EXT_FROM  = envnum("EXT_FROM", 0)
local EXT_TO    = envnum("EXT_TO", MAX_FRAME)
local VRAM_BASE = envnum("VRAM_BASE", 0xf40000)
local VRAM_TOP  = envnum("VRAM_TOP",  0xfbffff)

local frame = 0
local installed = false
local cpu, space
local taps = {}

local count   = 0
local min_off = math.huge
local max_off = -1
local max_line = -1         -- max (voff // 1024)
local colcnt = {}           -- [0..1023] write count per byte-column within the 1024B line
for i = 0, 1023 do colcnt[i] = 0 end

local function on_write(off, data, mask)
	if frame < EXT_FROM or frame > EXT_TO then return end
	local voff = off - VRAM_BASE
	if voff < 0 then return end
	count = count + 1
	if voff < min_off then min_off = voff end
	if voff > max_off then max_off = voff end
	local col  = voff % 1024
	local line = (voff - col) / 1024
	if line > max_line then max_line = line end
	colcnt[col] = colcnt[col] + 1
end

local function setup()
	cpu   = manager.machine.devices[":maincpu"]
	space = cpu.spaces["program"]
	taps[#taps+1] = space:install_write_tap(VRAM_BASE, VRAM_TOP, "VRAMWR",
		function(off, data, mask) on_write(off, data, mask) end)
end

local function report()
	local f = io.open(EXT_OUT, "w")
	f:write(string.format("# VRAM write extent over %d frames, window %08X..%08X\n",
	        frame, VRAM_BASE, VRAM_TOP))
	f:write(string.format("writes      = %d\n", count))
	if count == 0 then f:write("(no VRAM writes captured)\n"); f:close(); return end

	-- baseline = the one-time full-VRAM clear's per-column count, sampled deep
	-- off-screen (col 1000, never part of any framebuffer width). The displayed
	-- framebuffer columns get written MANY more times (redraws/pattern/cursor),
	-- so rowBytes = 1 + the largest column whose count clearly exceeds baseline.
	local baseline = colcnt[1000]
	local thresh = baseline + math.max(8, math.floor(baseline / 4))
	local fb_width = 0
	for c = 1023, 0, -1 do
		if colcnt[c] > thresh then fb_width = c + 1; break end
	end

	f:write(string.format("min_off     = 0x%05X (%d)\n", min_off, min_off))
	f:write(string.format("max_off     = 0x%05X (%d)\n", max_off, max_off))
	f:write(string.format("max_line    = %d  (clear writes all lines; height = monitor vres)\n", max_line))
	f:write(string.format("baseline    = %d  (per-col one-time clear count @col1000)\n", baseline))
	f:write(string.format("FB_WIDTH    = %d bytes/line  (= %d words; rowBytes the OS draws, 1024B stride)\n",
	        fb_width, math.floor((fb_width + 1) / 2)))
	f:write("col write-count histogram (64-byte buckets; excess over baseline = framebuffer):\n")
	for i = 0, 15 do
		local s = 0
		for c = i*64, i*64+63 do s = s + colcnt[c] end
		f:write(string.format("  [%2d] %4d..%-4d : %8d  (excess %+d)\n",
		        i, i*64, i*64+63, s, s - baseline*64))
	end
	f:close()
end

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then installed = true; setup() end
	if frame >= MAX_FRAME then report(); manager.machine:exit() end
end)
