-- diag_tap.lua — discover the exact read/write tap callback signature in this MAME.
local out = io.open(os.getenv("TAP_OUT") or "/tmp/diag_tap.txt", "w")
local frame, installed, n = 0, false, 0
local taps = {}
local cpu, space

local function dump(tag, ...)
	n = n + 1
	local nargs = select('#', ...)
	local parts = {}
	for i = 1, nargs do
		local v = select(i, ...)
		parts[i] = string.format("arg%d(%s)=%s", i, type(v), tostring(v))
	end
	out:write(string.format("%s nargs=%d %s\n", tag, nargs, table.concat(parts, " ")))
	out:flush()
end

emu.register_frame_done(function()
	frame = frame + 1
	if not installed then
		installed = true
		cpu = manager.machine.devices[":maincpu"]
		space = cpu.spaces["program"]
		-- tap the SWIM + VIA windows; dump raw args of the first invocations
		taps[#taps+1] = space:install_read_tap (0xF00000, 0xF17FFF, "rd", function(...) if n < 60 then dump("RD", ...) end end)
		taps[#taps+1] = space:install_write_tap(0xF00000, 0xF17FFF, "wr", function(...) if n < 60 then dump("WR", ...) end end)
		out:write("# installed taps\n"); out:flush()
	end
	if frame >= 600 then out:flush(); manager.machine:exit() end
end)
