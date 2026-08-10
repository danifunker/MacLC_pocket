-- set_montype.lua — force the V8 "Connected monitor" machine-config so we can
-- exercise the 512x384 display (montype 0x02) headlessly, and persist it to
-- cfg/maclc.cfg so an interactive windowed session inherits the same monitor.
--
-- The display SIZE on a real LC is a monitor SENSE value, not an OS setting:
--   0x01 = 15" Portrait (640x870)
--   0x02 = 12" RGB (512x384)   <- needed for the native 16bpp mode
--   0x06 = 13" RGB (640x480)   <- default
-- (from v8.cpp PORT_CONFNAME "Connected monitor"; field tag :v8:MONTYPE.)
--
-- Env: MONTYPE (hex/dec, default 0x02), RUN_FRAMES (default 60).
-- Run:  MONTYPE=0x02 run_mame.sh -hard <hd> -autoboot_script .../set_montype.lua

local function envnum(n, d) local v=os.getenv(n); return v and (tonumber(v) or d) or d end
local MONTYPE    = envnum("MONTYPE", 0x02)
local RUN_FRAMES = envnum("RUN_FRAMES", 60)

local frame = 0
local done  = false

local function find_montype_field()
	local ioport = manager.machine.ioport
	-- Prefer the exact tag, fall back to scanning for the "Connected monitor" field.
	local p = ioport.ports[":v8:MONTYPE"]
	if p then
		for name, fld in pairs(p.fields) do return fld, name, ":v8:MONTYPE" end
	end
	for tag, port in pairs(ioport.ports) do
		for name, fld in pairs(port.fields) do
			if tostring(name):find("monitor") or tostring(name):find("Monitor") then
				return fld, name, tag
			end
		end
	end
	return nil
end

emu.register_frame_done(function()
	frame = frame + 1
	if not done then
		local fld, name, tag = find_montype_field()
		if fld then
			fld:set_value(MONTYPE)
			print(string.format("set_montype: %s [%s] <- 0x%02X", tag, tostring(name), MONTYPE))
		else
			print("set_montype: MONTYPE field NOT FOUND")
		end
		done = true
	end
	if frame >= RUN_FRAMES then manager.machine:exit() end
end)
