-- wedge_trace.lua — MAME ground truth for the 7.x "Welcome to Macintosh"
-- async-driver wedge (docs/handoff_welcome_wedge_2026-06-12.md, Q1-Q5).
--
-- The FPGA core wedges in System code spinning on a RAM flag:
--     $8AA38: 4A2A 060A  tst.b $060A(A2)
--     $8AA3C: 66FA       bne.s $8AA38
-- This script finds that code in a HEALTHY MAME boot and decodes the wake
-- mechanism:
--   * Q1: scan RAM each SCAN_EVERY frames for byte pattern 4A 2A 06 0A 66 FA
--     (not in ROM/disk verbatim — decompressed System resource). Install a
--     fetch tap on each match; on execution (pc==match) read A2 and derive
--     the flag byte at A2+$60A.  New A2 values are logged as SPIN lines.
--   * Q2: write tap on each flag byte — every write logged with value, PC,
--     SR (interrupt context) and a 6-longword stack peek (call chain).
--   * Q3: read tap on each flag byte — exact spin iteration counts per frame
--     (FR lines; works even with the 020 icache hiding refetches).
--   * Q4: NCR5380 ($F10000) read-TRANSITION log (logs only when a reg's read
--     value changes — suppresses phase-poll spam) + ALL register writes,
--     each with PC and the running DACK byte counter.
--   * Q5: DACK window ($F06000) cumulative byte counter, stamped on every
--     event line and on B heartbeat lines every 60 frames.
--
-- Env: TR_OUT (default /tmp/wedge_trace.txt), MAX_FRAME (9000),
--      SNAP_EVERY (300), RAM_TOP (0xA00000 = 10MB), SCAN_START (300),
--      SCAN_EVERY (60 until first match, then 600).
--      VIC_LO/VIC_HI (default 0, disabled): pre-armed EXECUTION tap over a
--      vicinity known from a prior run (run 1: pattern at $8B6E0, fires=0).
--      Catches the ENCLOSING routine running even when the spin itself is
--      skipped, doubles as positive control for pc-filtered fetch taps, and
--      closes run 1's scan-install window. Logs each distinct pc once (EX
--      lines, with A0-A3/D0-D1), then per-frame hit deltas (EXF lines).
--      On first pattern match the surrounding code (match-0x2E0..match+0x41F)
--      is hexdumped to the log as MEM lines (disassemble with unidasm).
--
-- Run (mirrors docs/mame_trace_71boot_results.md):
--   MAME=~/repos/mame/maclc ROMPATH=~/repos/mame/roms RAMSIZE=10M \
--   TR_OUT=/tmp/wedge_71.txt \
--   verilator/mame/run_mame.sh -hard /tmp/MacLC_7-1.hd \
--     -autoboot_script verilator/mame/wedge_trace.lua \
--     -snapshot_directory /tmp/wedge_snap_71
--
-- Gotchas honored (docs/mame_compare.md): install taps on first
-- register_frame_done; keep tap refs in tables; RAM taps reinstalled
-- periodically (v8.cpp install_ram/rom remaps silently kill them); buffered
-- writes flushed per frame.

local function envnum(n, d) local v=os.getenv(n); return v and (tonumber(v) or d) or d end
local TR_OUT     = os.getenv("TR_OUT") or "/tmp/wedge_trace.txt"
local MAX_FRAME  = envnum("MAX_FRAME", 9000)
local SNAP_EVERY = envnum("SNAP_EVERY", 300)
local RAM_TOP    = envnum("RAM_TOP", 0xa00000)
local SCAN_START = envnum("SCAN_START", 300)
local VIC_LO     = envnum("VIC_LO", 0)
local VIC_HI     = envnum("VIC_HI", 0)
local WILD       = envnum("WILD", 0)       -- 1: match tst.b d16(An)/bne.s -6 for ANY An
local SCCTAP     = envnum("SCCTAP", 0)     -- 1: log SCC ($F04000) register traffic
local RET_AT     = envnum("RET_AT", 0)     -- frame to press Return (dirty-volume dialog)
local PATTERN    = "\x4A\x2A\x06\x0A\x66\xFA"
local WPATTERN   = "\x4A[\x28-\x2F]..\x66\xFA"

local f = io.open(TR_OUT, "w")
local frame, installed = 0, false
local cpu, space = nil, nil
local buf = {}

local scanning   = false   -- our own RAM scan reads must not count as hits
local in_cb      = false   -- reentrancy guard for reads inside tap callbacks
local scan_every = envnum("SCAN_EVERY", 60)
local found_any  = false
local no_range   = false   -- read_range unavailable -> slow u16 fallback

local matches    = {}      -- addr -> {fires=n, last_a2=v}
local match_list = {}
local fetch_taps = {}
local flags      = {}      -- flagaddr -> {reads, writes, emitted, pcs={}}
local flag_list  = {}
local flag_taps  = {}
local dev_taps   = {}

local dack_bytes, dack_accs = 0, 0
local ncr_rd_cnt = {}      -- per-frame read counts by reg
local ncr_last   = {}      -- last read value by reg (transition detect)
local vic_pcs    = {}      -- distinct executed pcs in the vicinity window
local vic_hits, vic_emitted, vic_logged = 0, 0, 0
local dumped     = {}      -- one MEM hexdump per matched region
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

local function reg(n)
	local v = -1
	pcall(function() v = cpu.state[n].value end)
	return v
end

-- ---------- flag byte taps (Q2 writes / Q3 reads) ----------

local function flag_lane(fl, off, mask)
	-- does this 32-bit-bus access cover the flag byte? return its value shift
	local base = off & ~3
	if fl < base or fl > base + 3 then return nil end
	local sh = (3 - (fl & 3)) * 8
	if (mask >> sh) & 0xff == 0 then return nil end
	return sh
end

local function install_flag_taps(fl)
	local base = fl & ~3
	local ok, err = pcall(function()
	flag_taps[#flag_taps+1] = space:install_read_tap(base, base+3, "flr"..string.format("%x", fl),
		function(off, data, mask)
			if scanning or in_cb then return end
			local sh = flag_lane(fl, off, mask)
			if not sh then return end
			local fr = flags[fl]
			fr.reads = fr.reads + 1
			local p = pc()
			fr.pcs[p] = (fr.pcs[p] or 0) + 1
		end)
	flag_taps[#flag_taps+1] = space:install_write_tap(base, base+3, "flw"..string.format("%x", fl),
		function(off, data, mask)
			if scanning or in_cb then return end
			local sh = flag_lane(fl, off, mask)
			if not sh then return end
			local fr = flags[fl]
			fr.writes = fr.writes + 1
			local val = (data >> sh) & 0xff
			local sr, a7 = reg("SR"), reg("A7")
			local stk = ""
			in_cb = true
			for i = 0, 5 do
				local ok, v = pcall(function() return space:read_u32(a7 + i*4) end)
				stk = stk .. string.format(" s%d=%08X", i, (ok and v) and v or 0)
			end
			in_cb = false
			emit(string.format("FW fl=%06X F=%d t=%.6f val=%02X pc=%08X sr=%04X dack=%d%s",
			                   fl, frame, now(), val, pc(), sr, dack_bytes, stk))
		end)
	end)
	if not ok then emit(string.format("TAPERR flag fl=%06X: %s", fl, tostring(err))) end
end

local function add_flag(fl)
	fl = fl & 0xffffff           -- 68020 mask is 0x80ffffff; RAM < $A00000
	if flags[fl] then return end
	flags[fl] = {reads = 0, writes = 0, emitted = 0, pcs = {}}
	flag_list[#flag_list+1] = fl
	install_flag_taps(fl)
	emit(string.format("FLAG fl=%06X F=%d t=%.6f", fl, frame, now()))
end

-- ---------- vicinity execution tap (run-2: enclosing-routine probe) ----------

local vic_taps = {}
local function install_vic_tap()
	if VIC_HI <= VIC_LO then return end
	local ok, t = pcall(function()
		return space:install_read_tap(VIC_LO & ~3, VIC_HI | 3, "vic",
		function(off, data, mask)
			if scanning or in_cb then return end
			local p = pc()
			if p < VIC_LO or p > VIC_HI then return end
			vic_hits = vic_hits + 1
			if vic_pcs[p] then
				vic_pcs[p] = vic_pcs[p] + 1
			else
				vic_pcs[p] = 1
				vic_logged = vic_logged + 1
				if vic_logged <= 96 then
					emit(string.format(
						"EX pc=%08X F=%d t=%.6f a0=%08X a1=%08X a2=%08X a3=%08X d0=%08X d1=%08X dack=%d",
						p, frame, now(), reg("A0"), reg("A1"), reg("A2"), reg("A3"),
						reg("D0"), reg("D1"), dack_bytes))
				end
			end
		end)
	end)
	if ok then vic_taps[#vic_taps+1] = t
	else emit(string.format("TAPERR vic: %s", tostring(t))) end
end

-- ---------- code hexdump around a match (disassemble offline w/ unidasm) ----------

local function dump_region(lo, hi, tag)
	scanning = true
	for base = lo & ~15, hi, 16 do
		local bytes = ""
		for i = 0, 15 do
			local ok, v = pcall(function() return space:read_u8(base + i) end)
			bytes = bytes .. string.format("%02X", (ok and v) and v or 0)
		end
		emit(string.format("MEM %s %06X: %s", tag, base, bytes))
	end
	scanning = false
end

-- ---------- spin fetch taps (Q1) ----------

-- NOTE: MAME tap ranges must be bus-width aligned (end address needs its low
-- 2 bits SET on the 32-bit 68020 bus) or install_read_tap THROWS — and an
-- uncaught throw aborts the rest of the frame callback. Align, and pcall all
-- installs with TAPERR logging so failures are visible in the trace file.
local function install_fetch_tap(X)
	local lo, hi = X & ~3, (X + 5) | 3
	local ok, t = pcall(function()
		return space:install_read_tap(lo, hi, "fx"..string.format("%x", X),
		function(off, data, mask)
			if scanning or in_cb then return end
			local p = pc()
			if p ~= X then return end
			local m = matches[X]
			m.fires = m.fires + 1
			local a2 = reg("A" .. m.regn)
			if a2 ~= m.last_a2 then
				m.last_a2 = a2
				local fl = (a2 + m.disp) & 0xffffffff
				emit(string.format("SPIN X=%06X F=%d t=%.6f a%d=%08X disp=%X flag=%08X dack=%d fires=%d",
				                   X, frame, now(), m.regn, a2, m.disp, fl, dack_bytes, m.fires))
				add_flag(fl)
			end
		end)
	end)
	if ok then fetch_taps[#fetch_taps+1] = t
	else emit(string.format("TAPERR fetch X=%06X: %s", X, tostring(t))) end
end

local function add_match(addr, regn, disp)
	if matches[addr] then return end
	matches[addr] = {fires = 0, last_a2 = nil, regn = regn, disp = disp}
	match_list[#match_list+1] = addr
	emit(string.format("MATCH X=%06X F=%d t=%.6f a%d disp=%X odd=%s", addr, frame, now(),
	                   regn, disp, tostring((addr & 1) ~= 0)))
	if (addr & 1) == 0 and #match_list <= 24 then install_fetch_tap(addr) end
	local region = addr & ~0xfff
	if not dumped[region] and #match_list <= 8 then
		dumped[region] = true
		local ok, err = pcall(dump_region, addr - 0x6e0, addr + 0x161f,
		                      string.format("X%06X", addr))
		if not ok then
			scanning = false
			emit(string.format("DUMPERR X=%06X: %s", addr, tostring(err)))
		end
	end
end

-- v8.cpp install_ram/rom remaps silently kill RAM-space taps; reinstall the
-- dynamic ones periodically (counters live in `matches`/`flags`, so safe)
local function reinstall_ram_taps()
	for _, t in ipairs(fetch_taps) do pcall(function() t:remove() end) end
	for _, t in ipairs(flag_taps)  do pcall(function() t:remove() end) end
	for _, t in ipairs(vic_taps)   do pcall(function() t:remove() end) end
	fetch_taps, flag_taps, vic_taps = {}, {}, {}
	for _, a in ipairs(match_list) do
		if (a & 1) == 0 then install_fetch_tap(a) end
	end
	for _, fl in ipairs(flag_list) do install_flag_taps(fl) end
	install_vic_tap()
end

-- ---------- RAM pattern scan (Q1) ----------

local function scan_chunk_string(lo, hi)
	if no_range then return nil end
	local ok, s = pcall(function() return space:read_range(lo, hi, 8) end)
	if not ok or type(s) ~= "string" then
		no_range = true
		emit(string.format("SCANERR read_range unavailable (%s) — u16 fallback", tostring(s)))
		return nil
	end
	return s
end

local function scan_ram()
	scanning = true
	local CHUNK = 0x80000
	local found = {}
	local lo = 0
	while lo < RAM_TOP do
		local hi = math.min(lo + CHUNK + 8, RAM_TOP) - 1
		local s = scan_chunk_string(lo, hi)
		if s then
			local init = 1
			while true do
				local i
				if WILD ~= 0 then i = s:find(WPATTERN, init, false)
				else              i = s:find(PATTERN,  init, true) end
				if not i then break end
				local addr = lo + i - 1
				if not matches[addr] then
					found[#found+1] = {addr = addr, regn = s:byte(i+1) - 0x28,
					                   disp = s:byte(i+2) * 256 + s:byte(i+3)}
				end
				init = i + 1
			end
		else
			-- slow fallback: word-stepped opcode probe (matches are even)
			for a = lo, math.min(lo + CHUNK + 8, RAM_TOP) - 6, 2 do
				local w0 = space:read_u16(a)
				local hit = (WILD ~= 0) and (w0 >= 0x4a28 and w0 <= 0x4a2f)
				                        or  (w0 == 0x4a2a and space:read_u16(a+2) == 0x060a)
				if hit and space:read_u16(a+4) == 0x66fa and not matches[a] then
					found[#found+1] = {addr = a, regn = w0 & 7,
					                   disp = space:read_u16(a+2)}
				end
			end
		end
		lo = lo + CHUNK
	end
	scanning = false
	for _, m in ipairs(found) do add_match(m.addr, m.regn, m.disp) end
	if #found > 0 and not found_any then
		found_any = true
		if WILD == 0 then scan_every = 600 end
	end
end

-- ---------- device-space taps (Q4 NCR choreography, Q5 DACK counter) ----------

local function maskbytes(mask)
	local n = 0
	for i = 0, 3 do
		if (mask >> (i*8)) & 0xff ~= 0 then n = n + 1 end
	end
	return n
end

local function setup()
	cpu = manager.machine.devices[":maincpu"]
	space = cpu.spaces["program"]

	f:write(string.format("# wedge_trace install F=%d t=%.6f max_frame=%d ram_top=%X vic=%X-%X\n",
	                      frame, now(), MAX_FRAME, RAM_TOP, VIC_LO, VIC_HI))

	install_vic_tap()

	-- DACK / pseudo-DMA window: counters only (per-access logging would be GBs)
	dev_taps[#dev_taps+1] = space:install_read_tap(0xf06000, 0xf07fff, "dackr", function(off, data, mask)
		if scanning then return end
		dack_bytes = dack_bytes + maskbytes(mask)
		dack_accs = dack_accs + 1
	end)
	dev_taps[#dev_taps+1] = space:install_write_tap(0xf06000, 0xf07fff, "dackw", function(off, data, mask)
		if scanning then return end
		dack_bytes = dack_bytes + maskbytes(mask)
		dack_accs = dack_accs + 1
	end)

	-- SCC ($F04000): choreography spec for rtl/scc.v. All WRITES logged (the
	-- WR-register programming); reads logged only when the returned value for
	-- that offset CHANGES (poll loops hammer RR0 47k+/frame otherwise).
	if SCCTAP ~= 0 then
		local scc_last = {}
		local scc_rdcnt = 0
		local function val_of(data, mask)
			for i = 3, 0, -1 do
				if (mask >> (i*8)) & 0xff ~= 0 then return (data >> (i*8)) & 0xff end
			end
			return -1
		end
		dev_taps[#dev_taps+1] = space:install_read_tap(0xf04000, 0xf04fff, "sccr",
			function(off, data, mask)
				if scanning then return end
				scc_rdcnt = scc_rdcnt + 1
				local v = val_of(data, mask)
				if scc_last[off] ~= v then
					scc_last[off] = v
					emit(string.format("SCR F=%d t=%.6f off=%06X val=%02X pc=%08X n=%d",
					                   frame, now(), off, v, pc(), scc_rdcnt))
				end
			end)
		dev_taps[#dev_taps+1] = space:install_write_tap(0xf04000, 0xf04fff, "sccw",
			function(off, data, mask)
				if scanning then return end
				emit(string.format("SCW F=%d t=%.6f off=%06X val=%02X pc=%08X",
				                   frame, now(), off, val_of(data, mask), pc()))
			end)
	end

	-- NCR5380 registers: all writes; reads logged only on value transitions
	dev_taps[#dev_taps+1] = space:install_write_tap(0xf10000, 0xf11fff, "ncrw", function(off, data, mask)
		if scanning then return end
		emit(string.format("NW F=%d t=%.6f reg=%d data=%08X mask=%08X pc=%08X dack=%d",
		                   frame, now(), (off >> 4) & 0xf, data, mask, pc(), dack_bytes))
	end)
	dev_taps[#dev_taps+1] = space:install_read_tap(0xf10000, 0xf11fff, "ncrr", function(off, data, mask)
		if scanning then return end
		local r = (off >> 4) & 0xf
		ncr_rd_cnt[r] = (ncr_rd_cnt[r] or 0) + 1
		local val = nil
		for i = 3, 0, -1 do
			if (mask >> (i*8)) & 0xff ~= 0 then val = (data >> (i*8)) & 0xff; break end
		end
		if val ~= nil and ncr_last[r] ~= val then
			ncr_last[r] = val
			emit(string.format("NRT F=%d t=%.6f reg=%d val=%02X pc=%08X dack=%d",
			                   frame, now(), r, val, pc(), dack_bytes))
		end
	end)

	f:flush()
end

-- ---------- frame loop ----------

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then installed = true; setup() end

	if frame >= SCAN_START and frame % scan_every == 0 then scan_ram() end
	if frame % 300 == 0 then reinstall_ram_taps() end

	-- dismiss the "not shut down properly" dialog (7.5.x) so the boot proceeds
	if RET_AT ~= 0 and (frame == RET_AT or frame == RET_AT + 900) then
		local ok, err = pcall(function() manager.machine.natkeyboard:post("\n") end)
		emit(string.format("RETKEY F=%d ok=%s %s", frame, tostring(ok), ok and "" or tostring(err)))
	end

	-- per-frame NCR read counts (poll volume)
	local rd = nil
	for r, n in pairs(ncr_rd_cnt) do
		rd = (rd or "") .. string.format(" r%d=%d", r, n)
	end
	if rd then emit(string.format("NR F=%d%s", frame, rd)); ncr_rd_cnt = {} end

	-- per-frame flag read (spin iteration) deltas with top PCs
	for _, fl in ipairs(flag_list) do
		local fr = flags[fl]
		if fr.reads > fr.emitted then
			local pcs = ""
			for p, n in pairs(fr.pcs) do
				pcs = pcs .. string.format(" %08X:%d", p, n)
			end
			emit(string.format("FR fl=%06X F=%d n=%d tot=%d pcs=%s",
			                   fl, frame, fr.reads - fr.emitted, fr.reads, pcs))
			fr.emitted = fr.reads
			fr.pcs = {}
		end
	end

	if vic_hits > vic_emitted then
		emit(string.format("EXF F=%d n=%d tot=%d", frame, vic_hits - vic_emitted, vic_hits))
		vic_emitted = vic_hits
	end

	if frame % 60 == 0 then
		emit(string.format("B F=%d t=%.6f dack=%d accs=%d matches=%d flags=%d vic=%d",
		                   frame, now(), dack_bytes, dack_accs, #match_list, #flag_list, vic_hits))
	end
	if SNAP_EVERY ~= 0 and frame % SNAP_EVERY == 0 then
		manager.machine.video:snapshot()
		emit(string.format("SNAP F=%d", frame))
	end

	if #buf > 0 then f:write(table.concat(buf, "\n")); f:write("\n"); buf = {}; f:flush() end

	if frame >= MAX_FRAME then
		manager.machine.video:snapshot()
		f:write(string.format("# END F=%d t=%.6f dack=%d accs=%d vic=%d\n",
		                      frame, now(), dack_bytes, dack_accs, vic_hits))
		for _, a in ipairs(match_list) do
			local m = matches[a]
			f:write(string.format("# MATCH %06X fires=%d last_a2=%s\n", a, m.fires,
			                      m.last_a2 and string.format("%08X", m.last_a2) or "-"))
		end
		for _, fl in ipairs(flag_list) do
			local fr = flags[fl]
			f:write(string.format("# FLAG %06X reads=%d writes=%d\n", fl, fr.reads, fr.writes))
		end
		local vp = {}
		for p in pairs(vic_pcs) do vp[#vp+1] = p end
		table.sort(vp)
		for _, p in ipairs(vp) do
			f:write(string.format("# VICPC %08X n=%d\n", p, vic_pcs[p]))
		end
		f:flush(); f:close()
		manager.machine:exit()
	end
end)
