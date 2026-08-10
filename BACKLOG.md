# MacLC MiSTer Backlog

## Priority 2: Audio

### ASC FIFO Mode
The Apple Sound Chip (ASC) supports FIFO playback mode where the CPU streams audio
samples into a 1KB FIFO buffer. Currently our ASC implementation only supports
wavetable synthesis mode.

**Approach:** Add a 1KB FIFO buffer to `rtl/asc.v`. Track read/write pointers and
generate half-empty/full interrupts. In FIFO mode, the DAC reads from the FIFO at the
configured sample rate instead of the wavetable oscillators.

### ASC Full Implementation
Beyond FIFO, the real ASC supports multiple operating modes, volume control, and
stereo panning. Our current implementation covers the basics needed for boot but
not full audio fidelity.

**Approach:** Reference MAME's `asc.cpp` for the complete register set. Implement
volume registers, stereo channel mixing, and all mode transitions.

## Priority 3: Storage & I/O

### SCSI DRQ Gating
The NCR 5380 SCSI controller asserts DRQ (data request) to signal the CPU that data
is ready. Currently DRQ timing may not be properly gated relative to bus phases,
which could cause data corruption on writes.

**Approach:** Review `rtl/ncr5380.sv` DRQ assertion logic. Ensure DRQ is only asserted
during the correct bus phase (DATA IN/DATA OUT) and is properly deasserted on ACK.
Compare with MAME's NCR 5380 implementation for phase-gating behavior.

### SWIM Floppy Controller
The Mac LC uses SWIM (Sanders-Wozniak Integrated Machine) rather than IWM for floppy
control. SWIM supports both GCR (800K) and MFM (1.44MB) formats. Our current
implementation is IWM-based and only handles GCR.

**Approach:** SWIM is a superset of IWM with additional MFM support registers. Add
MFM encoding/decoding alongside existing GCR logic in `rtl/iwm.v`. The SWIM mode
register at $DFE1FF selects between IWM-compat and SWIM native modes.
