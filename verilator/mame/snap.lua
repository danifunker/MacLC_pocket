-- snap.lua — headless MAME screenshot helper.
-- Boots maclc and writes a PNG snapshot every SNAP_EVERY frames (and one at
-- SNAP_AT), then exits at MAX_FRAME.  Compare these to the core's
-- screenshot_frame_NNNN.png (./obj_dir/Vemu --screenshot N).
--
-- Env: SNAP_AT (single frame, default 0=off), SNAP_EVERY (default 0=off),
--      MAX_FRAME (default 1100), SNAP_DIR is set via mame's -snapshot_directory.
-- Snapshots land in <snapshot_directory>/maclc/ (default /private/tmp/goodroms/snap).
--
-- Run: run_mame.sh -autoboot_script verilator/mame/snap.lua \
--        -snapname "maclc/f%i" -snapshot_directory /private/tmp/goodroms/snap

local function envnum(n, d) local v=os.getenv(n); return v and (tonumber(v) or d) or d end
local SNAP_AT    = envnum("SNAP_AT", 0)
local SNAP_EVERY = envnum("SNAP_EVERY", 0)
local MAX_FRAME  = envnum("MAX_FRAME", 1100)
local frame = 0

emu.register_frame_done(function()
	frame = frame + 1
	if (SNAP_AT  ~= 0 and frame == SNAP_AT) or
	   (SNAP_EVERY ~= 0 and (frame % SNAP_EVERY) == 0) then
		manager.machine.video:snapshot()
	end
	if frame >= MAX_FRAME then manager.machine:exit() end
end)
