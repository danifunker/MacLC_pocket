# TODO — deferred work

Things known to be missing or imperfect that are **not** being worked on right
now, with the reasoning for the deferral. `docs/RESUME.md` carries live state;
this file is the parking lot.

## Deferred by decision

### OSD unload announcement
Unassigning a disk in the Pocket's menu tells the guest nothing — the Mac goes
on believing the medium is present. Insertion has the same gap: there is no
"medium arrived" announcement either, so the core synthesises one internally
from the download stream (`insertDisk` / CSTIN, the 2026-08-06 media-change
work).

Scope is narrower than it first looks: it applies only to the floppy and the
CD-ROM, since SCSI hard disks are never unmounted mid-session in normal use.

Deferred because the practical flow already works — eject from inside the Mac
(or let the installer eject), then mount the next image. Swapping under a live
volume is hostile on real hardware too; MAME bombs the same way.

Worth doing alongside the GCR floppy work, since both live in the same media
path.

### PRAM persistence
The plumbing exists — the `apf_blockdev` PRAM FSM, `pram_save_req`, and a
documented save flow. It needs data slot 220 declared, a 256-byte PRAM file in
`dist`, and a bench for the save path.

**Deferred as low value.** What PRAM would preserve is largely covered already:
system volume has the Pocket's own controls, colour depth comes from the
factory PRAM seed at every boot, and the clock is set from the Pocket at launch.
That leaves control-panel preferences, which reset harmlessly.

Documented in the readme as a known limitation. Likely to stay unfixed.

### Special → Restart (in-core restart)
Restart from the Apple menu does not bring the machine back; power-cycle
instead. Never worked on the Pocket.

**Deferred until it works on MiSTer** — the warm-boot path is shared upstream
RTL, so fixing it here first would mean debugging a problem the parent project
also has, without its instrumentation.

### Stuck mouse button on Dock unplug
Pulling a USB mouse while its button is held leaves the Mac holding the button
down: HID has no release event, so the release can only be synthesised, and the
device is gone before that can happen. One click after reconnecting clears it.

**Not worth fixing.** Noted in the readme as a one-line limitation. Any fix
means touching the button path, which cost four hardware builds in one session.

## Still cut by resource budget

Second floppy drive · 16bpp video · 640×480 · BlueSCSI Toolbox · CD changer ·
CD audio · floppy writes.

These need the arithmetic in `docs/PORT_STATUS.md` redone before anyone
reconsiders them — the Pocket's Cyclone V has 18,480 ALMs and 308 M10K against
the DE10-Nano's 41,910 and 553, and the current build already sits at ~75% ALM
and ~83% M10K.

★ **Floppy writes are load-bearing as a cut**, not merely absent: `rtl/floppy.v`
has no write datapath and the drive reports write-protected, so the OS never
tries. The ROM's write primitive polls a handshake bit in an UNBOUNDED loop, so
an attempted write would hang the machine rather than fail cleanly.
