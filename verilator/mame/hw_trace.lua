-- hw_trace.lua — one-pass MAME ground-truth capture of the LC's non-SCSI
-- hardware traffic during early boot (companion to scsi_trace.lua; same
-- buffering/install gotchas honored — see docs/mame_compare.md).
--
-- Captures, on maincpu program space (addresses from maclc.cpp / v8.cpp):
--   * VIA1   $F00000-$F01FFF : every WRITE logged (reg decode (a>>9)&0xF,
--     byte extracted via mask, PC, frame, emu time). READS counted
--     per-register per-frame (IFR-poll storms summarized, not logged) —
--     EXCEPT reg $A (the shift register, $F01400 = the Egret transport):
--     SR reads AND writes are logged in full (the complete Egret byte
--     exchange: command bytes, responses, autopoll traffic).
--   * pseudovia (VIA2) $F26000-$F27FFF : every WRITE logged with reg name
--     (offset&0x13: 00=PB 01=CONFIG/ram_config 02=IFR2 03=IFR-ack
--     10=VIDEO/depth 12=SIER 13=IER — pseudovia.cpp); reads counted
--     per-reg per-frame. Reg 01 and 10 writes ARE the V8 memory-mapping /
--     video-depth config stream (v8.cpp via2_config_w / via2_video_config_w).
--   * Ariel RAMDAC $F24000-$F25FFF : every write (CLUT/depth), reads counted.
--   * SCC $F04000-$F05FFF : every WRITE logged with a WR0-pointer-tracking
--     register decode per channel (ctlB=+0 ctlA=+2 dataB=+4 dataA=+6,
--     z80scc dc_ab; byte is in D15-D8). NB the decode is a heuristic: the
--     pointer is consumed by control READS too, which we track but only
--     count; raw bytes are always logged so the decode can be re-derived.
--   * autovector fetches $64-$7F : counted per vector per frame (interrupt
--     level/source rates; vector = addr>>2, 25=L1..31=L7/NMI). Low-memory
--     taps get killed by v8.cpp install_ram/rom remaps (overlay / RAM
--     config) — reinstalled every frame until F700 then every 60 frames,
--     exactly like scsi_trace.lua.
--
-- Env: TR_OUT (default /tmp/hw_trace.txt), MAX_FRAME (default 1560).
--
-- Run: verilator/mame/run_mame.sh -hard disk.hd \
--        -autoboot_script verilator/mame/hw_trace.lua

local function envnum(n, d) local v=os.getenv(n); return v and (tonumber(v) or d) or d end
local TR_OUT    = os.getenv("TR_OUT") or "/tmp/hw_trace.txt"
local MAX_FRAME = envnum("MAX_FRAME", 1560)

local f = io.open(TR_OUT, "w")
local frame, installed = 0, false
local cpu, space, taps = nil, nil, {}
local lowtaps = {}
local buf = {}
local timefn = nil

local via1_rd, pv_rd, ariel_rd, scc_rd = {}, {}, {}, {}
local av_rd = {}

local VIA1_REG = { [0]="ORB","ORA","DDRB","DDRA","T1CL","T1CH","T1LL","T1LH",
                   "T2CL","T2CH","SR","ACR","PCR","IFR","IER","ORA*" }
local PV_REG   = { [0x00]="PB", [0x01]="CONFIG", [0x02]="IFR2", [0x03]="IFRACK",
                   [0x10]="VIDEO", [0x12]="SIER", [0x13]="IER" }
local SCC_PORT = { [0]="ctlB", [2]="ctlA", [4]="dataB", [6]="dataA" }

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

-- extract the byte from the highest active lane of a 32-bit-bus access
local function topbyte(data, mask)
	for i = 3, 0, -1 do
		if (mask >> (i*8)) & 0xff ~= 0 then return (data >> (i*8)) & 0xff end
	end
	return data & 0xff
end

-- SCC WR0 pointer tracking (per channel). A control write with ptr==0 is
-- WR0 itself: low 3 bits set the pointer, "point high" cmd (bits5-3=001)
-- adds 8. Any following control access (read OR write) hits reg ptr then
-- resets to 0.
local scc_ptr = { A = 0, B = 0 }

local function scc_ctl_write(ch, byte)
	local p = scc_ptr[ch]
	if p == 0 then
		local nptr = byte & 7
		if (byte & 0x38) == 0x08 then nptr = nptr + 8 end
		scc_ptr[ch] = nptr
		return string.format("WR0 cmd=%X ptr->%d", (byte >> 3) & 7, nptr)
	else
		scc_ptr[ch] = 0
		return string.format("WR%d", p)
	end
end

local function reinstall_lowmem()
	for _, t in ipairs(lowtaps) do pcall(function() t:remove() end) end
	lowtaps = {}
	-- autovector fetch counts ($64=L1 .. $7C=L7); $60 kept as canary
	lowtaps[#lowtaps+1] = space:install_read_tap(0x60, 0x7f, "avr", function(off, data, mask)
		local v = off >> 2
		av_rd[v] = (av_rd[v] or 0) + 1
	end)
end

local function setup()
	cpu = manager.machine.devices[":maincpu"]
	space = cpu.spaces["program"]

	f:write(string.format("# hw_trace install F=%d t=%.6f max_frame=%d\n",
	                      frame, now(), MAX_FRAME))

	reinstall_lowmem()

	-- VIA1: writes full; SR ($F01400, reg A) reads full; other reads counted
	taps[#taps+1] = space:install_write_tap(0xf00000, 0xf01fff, "v1w", function(off, data, mask)
		local reg = (off >> 9) & 0xf
		emit(string.format("V1W t=%.6f F=%d reg=%X(%s) data=%02X pc=%08X raw=%08X/%08X",
		                   now(), frame, reg, VIA1_REG[reg], topbyte(data, mask), pc(), data, mask))
	end)
	taps[#taps+1] = space:install_read_tap(0xf00000, 0xf01fff, "v1r", function(off, data, mask)
		local reg = (off >> 9) & 0xf
		if reg == 0xa then
			emit(string.format("SRR t=%.6f F=%d data=%02X pc=%08X",
			                   now(), frame, topbyte(data, mask), pc()))
		else
			via1_rd[reg] = (via1_rd[reg] or 0) + 1
		end
	end)

	-- pseudovia (VIA2): writes full, reads counted
	taps[#taps+1] = space:install_write_tap(0xf26000, 0xf27fff, "pvw", function(off, data, mask)
		local reg = off & 0x13
		emit(string.format("PVW t=%.6f F=%d off=%X reg=%02X(%s) data=%02X pc=%08X",
		                   now(), frame, off & 0x1fff, reg, PV_REG[reg] or "?", topbyte(data, mask), pc()))
	end)
	taps[#taps+1] = space:install_read_tap(0xf26000, 0xf27fff, "pvr", function(off, data, mask)
		local reg = off & 0x13
		pv_rd[reg] = (pv_rd[reg] or 0) + 1
	end)

	-- Ariel RAMDAC: writes full (CLUT stream), reads counted
	taps[#taps+1] = space:install_write_tap(0xf24000, 0xf25fff, "arw", function(off, data, mask)
		emit(string.format("ARW t=%.6f F=%d off=%X data=%02X pc=%08X",
		                   now(), frame, off & 0x1fff, topbyte(data, mask), pc()))
	end)
	taps[#taps+1] = space:install_read_tap(0xf24000, 0xf25fff, "arr", function(off, data, mask)
		local r = off & 7
		ariel_rd[r] = (ariel_rd[r] or 0) + 1
	end)

	-- SCC: writes full + WR decode; reads counted per port (reads consume
	-- the WR0 pointer — tracked)
	taps[#taps+1] = space:install_write_tap(0xf04000, 0xf05fff, "sccw", function(off, data, mask)
		local port = off & 6
		local byte = topbyte(data, mask)
		local dec = ""
		if port == 0 then dec = " " .. scc_ctl_write("B", byte)
		elseif port == 2 then dec = " " .. scc_ctl_write("A", byte)
		end
		emit(string.format("SCW t=%.6f F=%d %s data=%02X pc=%08X%s",
		                   now(), frame, SCC_PORT[port] or tostring(port), byte, pc(), dec))
	end)
	taps[#taps+1] = space:install_read_tap(0xf04000, 0xf05fff, "sccr", function(off, data, mask)
		local port = off & 6
		if port == 0 then scc_ptr.B = 0 elseif port == 2 then scc_ptr.A = 0 end
		scc_rd[port] = (scc_rd[port] or 0) + 1
	end)

	f:flush()
end

local function flush_counts(name, t)
	local s = nil
	for reg, n in pairs(t) do
		s = (s or "") .. string.format(" %X=%d", reg, n)
	end
	if s then emit(string.format("%s F=%d%s", name, frame, s)) end
	return {}
end

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then installed = true; setup() end

	if frame < 700 or frame % 60 == 0 then reinstall_lowmem() end

	via1_rd  = flush_counts("V1R", via1_rd)
	pv_rd    = flush_counts("PVR", pv_rd)
	ariel_rd = flush_counts("ARR", ariel_rd)
	scc_rd   = flush_counts("SCR", scc_rd)
	av_rd    = flush_counts("AV",  av_rd)

	if frame % 60 == 0 then
		emit(string.format("B F=%d t=%.6f", frame, now()))
	end

	if #buf > 0 then f:write(table.concat(buf, "\n")); f:write("\n"); buf = {}; f:flush() end

	if frame >= MAX_FRAME then
		f:write(string.format("# END F=%d t=%.6f\n", frame, now()))
		f:flush(); f:close()
		manager.machine:exit()
	end
end)
