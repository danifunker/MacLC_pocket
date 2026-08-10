-- scsi_trace.lua — one-pass MAME ground-truth capture for the 7.x boot death
-- at dack_beats=14592 (docs/handoff_mame_trace_71boot.md, Runs 1-4 combined).
--
-- Installs, on maincpu program space:
--   * rw tap on $8-$B            : bus-error vector traffic. Writes = the ROM
--     blind-transfer primitive installing/restoring its temp handler (2 writes
--     per call). Reads NOT from the primitive's save (`move.l $8.w,-4(a6)` at
--     ~$A08CFA) = a bus-error exception actually dispatching (the CPU fetches
--     the vector through this space).  Replaces berr_count.dbg, which relies
--     on debugger printf (no capturable sink headless — mame_compare gotcha 4).
--   * read taps on $A14880-$A14887 and $A14908-$A1490F : instruction fetches
--     of the ROM warm-restart entries our core's bogus "reboot" lands in
--     (Run 4). Cold boot may hit them once early; later hits = soft restart.
--   * rw tap on $F06000-$F07FFF  : the SCSI pseudo-DMA (DACK) window. Every
--     access logged with a running BYTE counter (mask ff=1, ffff=2,
--     ffffffff=4; our dack_beats are 16-bit strobes ~= bytes/2), emu time,
--     frame, pc (Run 2).
--   * write tap on $F10000-$F11FFF : NCR5380 register writes — CDB bytes
--     (reg0 after selection), ICR bit7 = bus reset (Run 3). Reads are only
--     counted per-frame per-reg (phase-poll volume, logged as NR lines).
--   * read tap on $60-$67 (autovectors 1) : count only — validates that
--     exception vector fetches are visible to taps (interrupts fire
--     constantly, so this MUST count; if 0, the V8-read method is void).
--
-- Env: TR_OUT (log file, default /tmp/scsi_trace.txt), MAX_FRAME (default
-- 9000), SNAP_EVERY (default 300), IDLE_EXIT (frames with no DACK access
-- after which we snapshot+exit, default 1800, 0=off; armed after frame 2000).
--
-- Run:  verilator/mame/run_mame.sh -hard disk.hd -autoboot_script \
--         verilator/mame/scsi_trace.lua  (plus -snapname/-snapshot_directory)
--
-- Gotchas honored (docs/mame_compare.md): install taps on first
-- register_frame_done; keep tap refs in a table; write to a file, flushed
-- per frame (NOT per line — the DACK window sees millions of accesses).

local function envnum(n, d) local v=os.getenv(n); return v and (tonumber(v) or d) or d end
local TR_OUT     = os.getenv("TR_OUT") or "/tmp/scsi_trace.txt"
local MAX_FRAME  = envnum("MAX_FRAME", 9000)
local SNAP_EVERY = envnum("SNAP_EVERY", 300)
local IDLE_EXIT  = envnum("IDLE_EXIT", 1800)

local f = io.open(TR_OUT, "w")
local frame, installed = 0, false
local cpu, space, taps = nil, nil, {}
local lowtaps = {}           -- low-mem taps: killed by v8.cpp install_ram/rom
                             -- remaps (overlay clear, RAM config) — reinstalled
                             -- periodically; see reinstall_lowmem()
local buf = {}
local dack_bytes, dack_accs, last_dack_frame = 0, 0, 0
local irqvec_reads = 0
local ncr_rd = {}            -- per-frame read counts by reg
local timefn = nil

local function emit(s) buf[#buf+1] = s end

local function now()
	if not timefn then
		if pcall(function() return emu.time() + 0 end) then
			timefn = function() return emu.time() end
		elseif pcall(function() return manager.machine.time:as_double() end) then
			timefn = function() return manager.machine.time:as_double() end
		else
			timefn = function() return -1 end
		end
	end
	return timefn()
end

local function pc()
	local v = 0
	pcall(function() v = cpu.state["CURPC"].value end)
	return v
end

local function maskbytes(mask)
	local n = 0
	for i = 0, 3 do
		if (mask >> (i*8)) & 0xff ~= 0 then n = n + 1 end
	end
	return n
end

-- v8.cpp switches the overlay and RAM config with space.install_ram/install_rom,
-- which REPLACES the dispatch entries our low-memory taps wrap (the taps over
-- $8/$60 silently die at overlay clear). Remove+reinstall them periodically.
local function reinstall_lowmem()
	for _, t in ipairs(lowtaps) do pcall(function() t:remove() end) end
	lowtaps = {}

	-- vector $8 (bus error) traffic
	lowtaps[#lowtaps+1] = space:install_read_tap(0x8, 0xb, "v8r", function(off, data, mask)
		emit(string.format("V8 RD t=%.6f F=%d off=%X data=%08X mask=%08X pc=%08X",
		                   now(), frame, off, data, mask, pc()))
	end)
	lowtaps[#lowtaps+1] = space:install_write_tap(0x8, 0xb, "v8w", function(off, data, mask)
		emit(string.format("V8 WR t=%.6f F=%d off=%X data=%08X mask=%08X pc=%08X",
		                   now(), frame, off, data, mask, pc()))
	end)

	-- autovector fetch counter (method validation: must count once interrupts
	-- are enabled, else low-mem taps are dead/vector reads invisible)
	lowtaps[#lowtaps+1] = space:install_read_tap(0x60, 0x67, "av1", function(off, data, mask)
		irqvec_reads = irqvec_reads + 1
	end)
end

local function setup()
	cpu = manager.machine.devices[":maincpu"]
	space = cpu.spaces["program"]

	f:write(string.format("# scsi_trace install F=%d t=%.6f max_frame=%d\n",
	                      frame, now(), MAX_FRAME))

	reinstall_lowmem()

	-- ROM warm-restart entry fetches (Run 4)
	taps[#taps+1] = space:install_read_tap(0xa14880, 0xa14887, "rst1", function(off, data, mask)
		emit(string.format("RST RD t=%.6f F=%d off=%08X pc=%08X", now(), frame, off, pc()))
	end)
	taps[#taps+1] = space:install_read_tap(0xa14908, 0xa1490f, "rst2", function(off, data, mask)
		emit(string.format("RST RD t=%.6f F=%d off=%08X pc=%08X", now(), frame, off, pc()))
	end)

	-- DACK / pseudo-DMA window (Run 2)
	taps[#taps+1] = space:install_read_tap(0xf06000, 0xf07fff, "dackr", function(off, data, mask)
		emit(string.format("D %d RD t=%.6f F=%d off=%08X data=%08X mask=%08X pc=%08X",
		                   dack_bytes, now(), frame, off, data, mask, pc()))
		dack_bytes = dack_bytes + maskbytes(mask)
		dack_accs = dack_accs + 1
		last_dack_frame = frame
	end)
	taps[#taps+1] = space:install_write_tap(0xf06000, 0xf07fff, "dackw", function(off, data, mask)
		emit(string.format("D %d WR t=%.6f F=%d off=%08X data=%08X mask=%08X pc=%08X",
		                   dack_bytes, now(), frame, off, data, mask, pc()))
		dack_bytes = dack_bytes + maskbytes(mask)
		dack_accs = dack_accs + 1
		last_dack_frame = frame
	end)

	-- NCR5380 register writes (Run 3); reads counted per frame
	taps[#taps+1] = space:install_write_tap(0xf10000, 0xf11fff, "ncrw", function(off, data, mask)
		emit(string.format("N WR t=%.6f F=%d off=%08X reg=%d data=%08X mask=%08X pc=%08X",
		                   now(), frame, off, (off >> 4) & 0xf, data, mask, pc()))
	end)
	taps[#taps+1] = space:install_read_tap(0xf10000, 0xf11fff, "ncrr", function(off, data, mask)
		local reg = (off >> 4) & 0xf
		ncr_rd[reg] = (ncr_rd[reg] or 0) + 1
	end)

	f:flush()
end

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then installed = true; setup() end

	-- low-mem remaps (overlay clear / RAM config) happen early; reinstall
	-- aggressively until the boot settles, then on a slow heartbeat
	if frame < 700 or frame % 60 == 0 then reinstall_lowmem() end

	local rd = nil
	for reg, n in pairs(ncr_rd) do
		rd = (rd or "") .. string.format(" r%d=%d", reg, n)
	end
	if rd then emit(string.format("NR F=%d%s", frame, rd)); ncr_rd = {} end

	if frame % 60 == 0 then
		local vbr = -1
		pcall(function() vbr = cpu.state["VBR"].value end)
		emit(string.format("B F=%d t=%.6f bytes=%d accs=%d irqvec=%d vbr=%X",
		                   frame, now(), dack_bytes, dack_accs, irqvec_reads, vbr))
	end
	if SNAP_EVERY ~= 0 and frame % SNAP_EVERY == 0 then
		manager.machine.video:snapshot()
		emit(string.format("SNAP F=%d", frame))
	end

	if #buf > 0 then f:write(table.concat(buf, "\n")); f:write("\n"); buf = {}; f:flush() end

	local idle = IDLE_EXIT ~= 0 and frame > 2000 and last_dack_frame > 0
	             and (frame - last_dack_frame) > IDLE_EXIT
	if frame >= MAX_FRAME or idle then
		manager.machine.video:snapshot()
		f:write(string.format("# END F=%d t=%.6f bytes=%d accs=%d irqvec=%d idle=%s\n",
		                      frame, now(), dack_bytes, dack_accs, irqvec_reads, tostring(idle)))
		f:flush(); f:close()
		manager.machine:exit()
	end
end)
