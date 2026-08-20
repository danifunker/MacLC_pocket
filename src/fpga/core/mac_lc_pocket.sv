// ============================================================================
// mac_lc_pocket.sv — the Macintosh LC itself, for the Analogue Pocket.
//
// PROVENANCE: derived from verilator/sim.v (module emu) at commit a5568a4,
// NOT from the MiSTer MacLC.sv. sim.v was the better base by a wide margin:
// half the size, the MiSTer framework glue (hps_io, CONF_STR/status[],
// video_freak, pll_video/pll_cfg, dbg_probes, HDMI) already absent, clk_sys
// already an input rather than an internal PLL, and its memory model already
// instantiated behind the SAME .din/.addr/.ds/.we/.oe/.dout interface that
// pocket_sdram exposes. docs/verilator_differences.md audits its CPU bus glue
// (cpu_berr, _cpuVPA, _cpuDTACK, dtack_en, fc7_berr, fc7_iack,
// overlay_trigger, memoryOverlayOn) as byte-identical to MacLC.sv, so the
// hardest part of the machine top arrived already correct — and already
// validated: the three Pocket cuts pass the boot oracle in this exact body
// (see docs/PORT_STATUS.md).
//
// WHY THE PORT LIST IS STILL sim.v's (VGA_*, ioctl_*, debug_*, cfg_memSize,
// 3-slot sd_*): deliberately. Renaming them would mean ~1000 lines of edits to
// a body that currently boots, for zero functional gain, and core_top adapts
// the handful of names it cares about in one place instead. Keeping them
// identical is also the precondition for the real prize — letting
// the sim.v top INSTANTIATE this module rather than duplicating the machine,
// which retires the two-tops divergence class that has repeatedly cost this
// project real bugs (sim.v once hardwired .berr(1'b0), masking the MOVES
// bus-error fix; selectASC was wired in sim but floating on FPGA, so ASC
// registers were dead in hardware).
//
// The debug_* outputs are kept and simply left unconnected by core_top;
// Quartus strips them. Same for serial_txd/rxd.
//
// WHAT WAS ADDED BACK — exactly the "intentional FPGA-only additions" list in
// docs/verilator_differences.md, none of which sim.v needed:
//   * rom_loaded latch — hold reset from FPGA config until the first ROM
//     download begins, so the 68k cannot execute whatever the PREVIOUS core
//     left in SDRAM at the ROM window.
//   * sdram_reinit pulse — edge-triggered, gated on rom_loaded and
//     !dio_download. The reverted MiSTer attempts tied .init to a level that
//     was ALSO held through the download, which swallowed the download writes
//     and broke cold boot.
//   * configRAMSize driven from cfg_memSize (2 MB / 10 MB). sim.v hardwired
//     2 MB and left cfg_memSize dead. NOTE the 10 MB SIMM path has never been
//     exercised in simulation.
//   * pocket_sdram in place of sim_ram.
// ============================================================================

module mac_lc_pocket
(
	// ---- Pocket additions (everything below this block is sim.v's) --------
	input         clk_mem,      // 65.0 MHz — SDRAM state machine, must be 8x clk_8
	input         clk_pix,      // 15.667 MHz — 512x384 dot clock (APF video_rgb_clock)
	input         pll_locked,   // synchronised into clk_sys by core_top

	// SDRAM pins, driven out through core_top
	inout  [15:0] sdram_dq,
	output [12:0] sdram_a,
	output  [1:0] sdram_dqm,
	output  [1:0] sdram_ba,
	output        sdram_cke,
	output        sdram_we_n,
	output        sdram_ras_n,
	output        sdram_cas_n,

	// ---- sim.v's port list, verbatim -------------------------------------
	input         clk_sys,
	input         reset,

	// ---- Pocket additions -------------------------------------------------
	// Zero the Egret PRAM, then let the machine reboot. See the FSM below.
	input         pram_reset,
	// Built-in video test pattern: [2] = bypass VRAM, [1:0] = pattern select.
	// Bring-up witness — proves the video contract and the interact write path
	// independently of whether the Mac itself is running.
	input  [2:0]  test_pattern,

	// PS2 keyboard/mouse
	input [10:0]  ps2_key,
	input [24:0]  ps2_mouse,

	// RTC timestamp
	input [32:0]  timestamp,

	// VGA output
	output [7:0]  VGA_R,
	output [7:0]  VGA_G,
	output [7:0]  VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_HB,
	output        VGA_VB,
	output        CE_PIXEL,

	// Audio output
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	// ROM/disk loading interface (ioctl)
	input         ioctl_download,
	input         ioctl_wr,
	input [24:0]  ioctl_addr,
	input [15:0]  ioctl_dout,
	input [7:0]   ioctl_index,
	output reg    ioctl_wait = 1'b0,

	// SCSI block device interface. Slots: 0,1 = disks (SCSI 6/5),
	// 2 = CD-ROM (SCSI 3; FPGA top uses hps_io slot 4 for it — the sim
	// block-device model has no PRAM/Toolbox slots so the CD sits at 2).
	output [31:0] sd_lba[3],
	output [2:0]  sd_rd,
	output [2:0]  sd_wr,
	input  [2:0]  sd_ack,
	input  [7:0]  sd_buff_addr,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din[3],
	input         sd_buff_wr,
	input  [2:0]  img_mounted,
	input  [63:0] img_size,

	// ★ buildAD: hold the machine in reset while high (FRZE lever in
	// core_top — manual bit or auto-trigger at a blockdev delivery count).
	// RAM freezes for the ROMV v4 oracle; SDRAM refresh unaffected.
	input         ext_freeze,
	input         vram_force_512k, // V256 lever: restore 512K VRAM SIMM (see addrController_top)
	// ★ buildAH: trigger-only variant — fires at the delivery count WITHOUT
	// holding the machine; starts PCRB's post-trigger countdown so the ring
	// freezes K distinct PCs later, inside the boot code's check-and-decide
	// window after the final sector.
	input         ext_trig,

	// CPU debug outputs
	output [31:0] debug_pc,
	output [15:0] debug_opcode,
	output        debug_fetch_valid,
	output [31:0] debug_data_addr,

	// RAM debug outputs
	output [24:0] debug_ram_addr,
	output [15:0] debug_ram_din,
	output [15:0] debug_ram_dout,
	output        debug_ram_we,
	output        debug_ram_oe,
	output  [1:0] debug_ram_ds,
	output        debug_selectRAM,
	output        debug_selectROM,

	// Peripheral debug outputs
	output        debug_selectVIA,
	output        debug_selectAriel,
	output        debug_selectPseudoVIA,
	output        debug_selectSCSI,
	output        debug_selectSCC,
	output        debug_selectIWM,
	output        debug_selectASC,
	output        debug_selectVRAM,
	output [31:0] debug_cpuAddr,

	// ---- PRAM (NVRAM) persistence, driven by apf_blockdev -----------------
	input  [7:0]  pram_load_addr_i,
	input  [7:0]  pram_load_data_i,
	input         pram_load_wr_i,
	input         pram_loaded_i,      // load resolved (ok or failed) -> may boot
	input  [7:0]  pram_save_addr_i,
	output [7:0]  pram_save_data_o,
	output        pram_save_req_o,
	output [15:0] debug_cpuDataIn,    // Data from CPU to peripherals
	output [15:0] debug_cpuDataOut,   // Data from peripherals to CPU
	output        debug_cpuRW,        // 1=read, 0=write
	output        debug_cpuBusControl,
	output        debug_cpu_as,       // _cpuAS (0 = address strobe asserted)
	output        debug_cpu_dtack,    // _cpuDTACK (0 = acknowledged)

	// Serial port (SCC Channel A)
	output        serial_txd,       // SCC Channel A TX output (for sim-side RX)
	input         serial_rxd,       // SCC Channel A RX input (from sim-side TX)

	// Machine configuration inputs
	input  [1:0]  cfg_cpuType,      // Unused, kept for sim_main.cpp compatibility
	input         cfg_memSize,      // 0 = 2 MB (0x24), 1 = 10 MB (0xE4)
	input         nmi_pulse         // --nmi-at-frame: pulse a Level-7 NMI (MacsBug test)
);

	localparam SCSI_DEVS = 2;

	// Configuration
	// 0 = 2 MB, 1 = 10 MB. The old "0=1MB, 1=4MB" comment here was inherited
	// text and wrong — see configRAMSize below for what is actually driven.
	wire      status_mem = cfg_memSize;
	localparam [1:0] status_cpu = 2'b10;     // 68020
	// Mac LC always runs at C15M (~15.67 MHz) - use 16 MHz clock enables

	////////////////////   CLOCKS   ///////////////////

	// clk_mem and pll_locked are PORTS here (core_top's mf_pllbase owns both).
	// sim.v declared them internally as clk_mem = clk_sys / pll_locked = !reset,
	// which is where the simulator's ideal-memory shortcut showed through: on
	// hardware the SDRAM state machine needs a real 65 MHz, exactly 8x the
	// 8.125 MHz bus clock, or pocket_sdram's per-cycle wrap breaks.

	// Clock enables - generated by addrController_top
	wire clk8_en_p, clk8_en_n;
	// V8 SCSI_PCLK / SCC RTxC source — see rtl/v8_clocks.sv (plan_040526.md Step 5).
	wire scsi_pclk_en;
	v8_clocks v8_clocks_inst (
		.clk_sys     (clk_sys),
		.reset       (~n_reset),
		.scsi_pclk_en(scsi_pclk_en)
	);
	wire clk16_en_p, clk16_en_n;
	wire clk8;

	// Cleared only by reconfig; the ROM stays in SDRAM across warm resets.
	reg rom_loaded = 1'b0;
	// jboot_loaded: the JTAG boot strobe vouches that the ROM is already
	// resident in SDRAM (it survives fabric reconfiguration).
	always @(posedge clk_sys) if ((dio_download && dio_index == 8'd0) || jboot_loaded) rom_loaded <= 1'b1;

	// ---- "Reset PRAM": zero the Egret's pram[] --------------------------------
	// MiSTer's "Reset PRAM & Core" (R6) works by writing zeros through
	// egret_wrapper's pram_load_* port and rebooting. This port was tied off at
	// import (pram_load_wr=0, pram_ready=1), so the menu action did nothing but
	// an ordinary reset.
	//
	// egret_wrapper requires pram_load_wr to fire BEFORE pram_ready rises (see
	// its comment at line ~146 and the gate at ~767), so pram_ready drops for the
	// duration of the zeroing. 256 writes at clk_sys is ~8 us, far inside the
	// ~2 ms n_reset stretch that the same button also triggers, so the Egret is
	// held in reset throughout and re-copies the zeroed PRAM on release.
	wire [7:0] pram_load_addr;
	wire [7:0] pram_load_data;
	wire       pram_load_wr;
	wire [7:0] pram_save_data_w;
	wire       pram_wr_stb_w;
	assign pram_save_data_o = pram_save_data_w;

	reg       pram_zero_busy = 1'b0;
	reg [7:0] pram_zero_addr = 8'd0;
	always @(posedge clk_sys) begin
		if (pram_reset) begin
			pram_zero_busy <= 1'b1;
			pram_zero_addr <= 8'd0;
		end else if (pram_zero_busy) begin
			// pram_load_wr is pram_zero_busy itself, so the byte at
			// pram_zero_addr is written on this very cycle; advance after.
			if (pram_zero_addr == 8'd255) pram_zero_busy <= 1'b0;
			pram_zero_addr <= pram_zero_addr + 8'd1;
		end
	end

	// ---- PRAM (NVRAM) persistence -----------------------------------------
	// Two writers into the Egret's pram[]: the "Reset PRAM" zeroing above, and
	// the save-file restore driven by apf_blockdev. They are mutually exclusive
	// in practice (the restore runs once at power-up, the zeroing only on an
	// explicit menu action, which also resets the machine), so a simple
	// priority mux is enough -- and zeroing wins, because the user asked for it.
	//
	// pram_ready must not rise until whichever writer is active has finished:
	// egret_wrapper copies pram[] into the HC05's working RAM exactly once on
	// that signal and holds the 68020 in reset until the copy completes.
	// pram_loaded comes from apf_blockdev and is raised on load success OR
	// failure, so a missing save file can never wedge the boot.
	assign pram_load_addr = pram_zero_busy ? pram_zero_addr : pram_load_addr_i;
	assign pram_load_data = pram_zero_busy ? 8'h00          : pram_load_data_i;
	assign pram_load_wr   = pram_zero_busy | pram_load_wr_i;
	// ★ READY BACKSTOP — do not remove. 2026-08-11: the first cut of this made
	// pram_ready depend ONLY on pram_loaded_i, and the PRAM load never
	// resolved on hardware, so pram_ready never rose, egret_wrapper never set
	// pram_loaded, reset_680x0 stayed asserted and the 68020 executed exactly
	// ONE bus cycle before sitting in reset for ever. The probe read
	// `_cpuReset=0, cycles=1` -- a completely dead machine, caused by an
	// OPTIONAL save file.
	//
	// MacLC.sv.reference:352 has the same guard for the same reason
	// (`pram_rdy_cnt >= 200_000_000` there). The rule: the boot may WAIT for
	// NVRAM, but must never DEPEND on it. ~1 s at 32.5 MHz is far longer than
	// a 256-byte target_dataslot_read needs, including apf_blockdev's own
	// ~226 ms command timeout and a retry.
	reg [25:0] pram_rdy_cnt = 26'd0;
	reg        pram_rdy_to  = 1'b0;
	always @(posedge clk_sys) begin
		if (pram_loaded_i || pram_rdy_to) pram_rdy_cnt <= 26'd0;
		else if (pram_rdy_cnt == 26'd32_500_000) pram_rdy_to <= 1'b1;
		else pram_rdy_cnt <= pram_rdy_cnt + 26'd1;
	end
	wire   pram_ready_r   = (pram_loaded_i | pram_rdy_to) & ~pram_zero_busy;

	// Dirty tracking: the Egret firmware strobes pram_wr_stb on every PRAM byte
	// it writes. Flush on a quiet period rather than per byte -- the guest
	// rewrites PRAM in bursts, and each save is a whole-file 256-byte round
	// trip through the OS.
	reg [23:0] pram_idle_ctr = 24'd0;
	reg        pram_dirty    = 1'b0;
	reg        pram_save_req_r = 1'b0;
	always @(posedge clk_sys) begin
		pram_save_req_r <= 1'b0;
		if (pram_wr_stb_w) begin
			pram_dirty    <= 1'b1;
			pram_idle_ctr <= 24'd0;               // restart the quiet timer
		end else if (pram_dirty) begin
			// ~0.5 s of no PRAM writes at 32.5 MHz, then flush once.
			if (pram_idle_ctr == 24'd16_250_000) begin
				pram_save_req_r <= 1'b1;
				pram_dirty      <= 1'b0;
				pram_idle_ctr   <= 24'd0;
			end else begin
				pram_idle_ctr <= pram_idle_ctr + 24'd1;
			end
		end
	end
	assign pram_save_req_o = pram_save_req_r;

	reg  iiop_mfreeze = 1'b0;   // buildAV: REGISTERED in the IIOP block (the
	                           // buildAU combinational forward-wire did not
	                           // hold reset on HW despite both inputs = 1;
	                           // a registered signal in one clk_sys block is
	                           // what ext_freeze uses and it works).

	// Reset logic
	// NOTE: Do NOT include _cpuReset_o here! The RESET instruction drives
	// reset_n low to reset peripherals, but should NOT reset the CPU itself.
	// IMPORTANT: In simulation, wait for ROM download to complete before releasing reset
	reg n_reset = 0;
	reg n_reset_prev = 0;
	reg dio_download_prev = 0;
	always @(posedge clk_sys) begin
		reg [15:0] rst_cnt;

		if (clk8_en_p) begin
			n_reset_prev <= n_reset;
			dio_download_prev <= dio_download;

			// Debug: track when download completes
			if (dio_download_prev && !dio_download) begin
				$display("[F%0d] SIM: dio_download went LOW - ROM download complete", sim_frame_count);
			end

			// Gate on the ROM download (index 0) ONLY, not any download.
			// Mounting a floppy must NOT reboot the machine — hot-insert, like
			// real hardware, and the MiSTer media-change logic (CSTIN/DiskChg,
			// see CLAUDE.md) depends on it.
			//
			// A reset-on-any-download workaround for the Pocket floppy hang was
			// tried here and removed: it cost hot-insert. The hang is instead
			// addressed by making the floppy a `deferload` slot that
			// apf_blockdev copies into SDRAM at a pace the CORE sets, so
			// nothing is ever pushed at the bus faster than it can absorb.
			// !rom_loaded extends the hold from FPGA config until that first
			// ROM download begins, closing the window in which the 68k would
			// otherwise execute whatever the PREVIOUS core left in SDRAM at
			// the ROM window.
			// ★ cold_rst REMOVED from this term 2026-08-11. The automatic
			// post-download re-reset was added to imitate the user's manual
			// "reload the ROM two or three times" workaround. It DID change
			// behaviour (the overlay started clearing) but it was in flight
			// when that workaround stopped working, so it is backed out until
			// the regression is bisected. The generator above is left in place
			// and simply drives nothing; re-add `cold_rst ||` here to retry.
			// ★ buildAD: ext_freeze holds the machine in reset INDEFINITELY
			// (manual bit or the FRZE auto-trigger at a delivery count —
			// core_top). SDRAM keeps refreshing, so RAM is a frozen corpse
			// the ROMV v4 oracle can dump at leisure; without this, every
			// scan's reset release let the machine reboot and march its RAM
			// test straight through the evidence (seen live 2026-08-13:
			// low RAM full of the DB6D:B6DB march pattern mid-dump).
			// ★ buildAU: iiop_mfreeze = freeze the machine AT the vector-4
			// dispatch (opt-in via IIOP source[1]) — the fault-time RAM and
			// stack are frozen before SysError's dialog redraw can scribble
			// them. Same reset-hold as ext_freeze; release via IIOP rearm.
			if(~pll_locked || !rom_loaded || reset || jboot_rst ||
			   ext_freeze || iiop_mfreeze || (dio_download && dio_index == 8'd0)) begin
				rst_cnt <= '1;
				n_reset <= 0;
			end
			else if(rst_cnt) begin
				rst_cnt <= rst_cnt - 1'd1;
				// Debug: show countdown at key points only
				if (rst_cnt == 16'h0001) begin
					$display("[F%0d] SIM: rst_cnt about to expire, n_reset will go high", sim_frame_count);
				end
			end
			else begin
				n_reset <= 1;
			end

			// Debug: track when n_reset changes
			if (n_reset != n_reset_prev) begin
				$display("[F%0d] SIM: *** n_reset changed to %b *** (rst_cnt=%04x)", sim_frame_count, n_reset, rst_cnt);
			end
		end
	end

	///////////////////////////////////////////////////

	wire v8_ce_pix;
	assign CE_PIXEL  = v8_ce_pix;  // real pixel-clock enable (was hardwired 1 -> doubled every pixel)

	// Video Output - Mac LC V8 video system
	assign VGA_R  = v8_vga_r;
	assign VGA_G  = v8_vga_g;
	assign VGA_B  = v8_vga_b;
	wire VGA_DE = v8_de;
	assign VGA_VS = v8_vsync;
	assign VGA_HS = v8_hsync;
	assign VGA_HB = v8_hblank;
	assign VGA_VB = v8_vblank;

	// Frame counter for debug logging
	reg [31:0] sim_frame_count = 0;
	reg vs_prev = 0;
	always @(posedge clk_sys) begin
		vs_prev <= VGA_VS;
		if (VGA_VS && !vs_prev)  // Rising edge of vsync = new frame
			sim_frame_count <= sim_frame_count + 1;
	end

	// ASC samples drive AUDIO_L/R directly (Commit C). Legacy DMA gone.
	assign AUDIO_L = asc_sample_l;
	assign AUDIO_R = asc_sample_r;

	// Mac LC memory configuration
	// POCKET: 2 MB board only, or 2 MB board + 4 MB + 4 MB SIMM = 10 MB.
	// sim.v hardwired 8'h24 and left cfg_memSize a dead wire; the 10 MB SIMM
	// path has never been exercised in simulation, only on MiSTer hardware.
	wire [7:0] configRAMSize = cfg_memSize ? 8'hE4 : 8'h24;
	wire [7:0] pvia_ram_config_out;   // Active RAM config from pseudovia
	wire       pvia_ram_configured;   // ROM has programmed V8 config ($0 mirror enable)

	// Serial Ports - connect SCC Channel A to sim via serial_txd/serial_rxd ports
	wire serialOut;              // SCC Channel A TX (driven by SCC)

	// ---- STM console (2026-08-12): JTAG -> 9600-baud serial into SCC ch A --
	// The ROM's STM diagnostic monitor listens on the modem port (9600 8N2)
	// and can run its own critical tests on demand (*T: Size Memory, Data Bus,
	// Mod3 RAM, Address Line...; *R returns the status/error code). The Pocket
	// has no serial pin, so synthesize the RX line from an ISSP source:
	// toggling source[8] transmits source[7:0] once. Idle high. Drive with
	// scripts/stm_send.tcl.
	wire [8:0]  stm_src;
	reg  [7:0]  stm_sent_cnt = 8'd0;
	reg         stm_go_d     = 1'b0;
	reg  [11:0] stm_baud     = 12'd0;
	reg  [3:0]  stm_bitn     = 4'd0;
	reg  [10:0] stm_shift    = 11'h7FF;
	reg         stm_line     = 1'b1;
	// ★ must match scc.v's console-speed shim (baud_divid=100 for the STM's
	// WR12=0A config) — both ends of this internal line run at ~325 kbaud.
	// Before the shim this was 3385 (true 9600).
	localparam [11:0] STM_BAUD_DIV = 12'd100;
	always @(posedge clk_sys) begin
		stm_go_d <= stm_src[8];
		if (stm_bitn == 4'd0) begin
			stm_line <= 1'b1;
			// ★ RISING edge only. ISSP sources reset to 0 at every JTAG session
			// boundary; with any-toggle triggering, each session close whose
			// last state was 1 fired a spurious 0x00 character — which queued
			// ahead of real commands and fed the monitor null bytes (captured:
			// R-dtA-00 + error-reset). Rising-edge-only makes session resets
			// silent. Protocol: write {1,byte} to send, {0,x} to re-arm.
			if (!stm_go_d && stm_src[8]) begin
				// {stop, stop, data[7:0], start} — shifted out LSB first
				stm_shift    <= {2'b11, stm_src[7:0], 1'b0};
				stm_bitn     <= 4'd11;
				stm_baud     <= STM_BAUD_DIV;
				stm_sent_cnt <= stm_sent_cnt + 8'd1;
			end
		end else begin
			stm_line <= stm_shift[0];
			if (stm_baud == 12'd0) begin
				stm_shift <= {1'b1, stm_shift[10:1]};
				stm_bitn  <= stm_bitn - 4'd1;
				stm_baud  <= STM_BAUD_DIV;
			end else begin
				stm_baud <= stm_baud - 12'd1;
			end
		end
	end
	wire serialIn = serial_rxd & stm_line;  // SCC Channel A RX (external idle-1 AND injector)
	// MiSTer: `wire serialCTS = 1'b1; // Idle/deasserted when no serial device
	// connected` (MacLC.sv.reference:681). This was 1'b0 here, i.e. the SCC was
	// told a modem was asserting CTS on a port with nothing plugged into it.
	// Restored to parity 2026-08-11.
	// ★ 2026-08-12 baseline-anchor build: back to 0 (the golden build's value)
	// as part of reproducing the exact last-known-working configuration. The
	// wiring into scc.cts is verified identical to MiSTer's, so 1'b1 SHOULD be
	// right — restore it as its own single-variable step once the golden
	// baseline is re-proven on hardware.
	wire serialCTS = 1'b0;
	wire serialRTS;
	assign serial_txd = serialOut;

	// V8 Video system wires
	wire v8_hsync, v8_vsync, v8_hblank, v8_vblank, v8_de;

	// ---- clk_pix -> clk_sys: 2FF sync for the guest-facing blanking levels --
	// ★ PORTED FROM MacLC.sv.reference:632-639 on 2026-08-11. Upstream syncs
	// these and consumes ONLY the _s versions (its line 1181 comment reads
	// "2FF-synced from the clk_vid scanout domain"). This fork wired the RAW
	// signals straight across, so v8_vblank -- which is generated in the
	// clk_pix domain (15.667 MHz) -- drove pseudovia's VBlank INTERRUPT and the
	// VIA blanking inputs, both clocked at clk_sys (32.5 MHz), with no
	// synchronizer at all. An unsynchronised level feeding an interrupt is a
	// metastability hazard whose outcome varies per power-up, and the Mac's
	// early boot is paced by the VBlank tick.
	//
	// The Pocket makes this WORSE than MiSTer, not better: the clk_pix/clk_sys
	// ratio here (15.667 / 32.5) differs from MiSTer's clk_vid/clk_sys, so the
	// sampling relationship this fork runs was never the one upstream tested.
	reg vbl_meta = 1'b0, v8_vblank_s = 1'b0;
	reg hbl_meta = 1'b0, v8_hblank_s = 1'b0;
	always @(posedge clk_sys) begin
		vbl_meta    <= v8_vblank;
		v8_vblank_s <= vbl_meta;
		hbl_meta    <= v8_hblank;
		v8_hblank_s <= hbl_meta;
	end

	// ---- clk_sys -> clk_pix: video-domain reset ----------------------------
	// ★ Also from MacLC.sv.reference:623-629, where the video module is reset
	// by vidrst_s, a 2FF sync IN THE VIDEO DOMAIN. We passed raw ~n_reset (a
	// clk_sys signal) directly into a clk_pix module. Upstream additionally
	// folds in ~pll_video_locked and pix_quiet; neither exists on the Pocket
	// (one PLL, no runtime retarget), so the reset term alone is synced here.
	reg vidrst_meta = 1'b1, vidrst_s = 1'b1;
	always @(posedge clk_pix) begin
		vidrst_meta <= ~n_reset;
		vidrst_s    <= vidrst_meta;
	end
	wire [7:0] v8_vga_r, v8_vga_g, v8_vga_b;
	wire [7:0] ariel_pixel_addr;
	wire [23:0] ariel_palette_data;
	wire [7:0] ariel_reg_dout;
	wire selectAriel;      // From address decoder
	wire selectPseudoVIA;  // From address decoder
	wire selectVRAM;       // From address decoder
	wire [7:0] pseudovia_dout;
	wire pseudovia_irq;
	wire capslock;

	// interconnects
	// CPU
	wire _cpuReset, _cpuReset_o, _cpuUDS, _cpuLDS, _cpuRW, _cpuAS;
	wire _cpuVMA, _cpuVPA, _cpuDTACK;
	wire E_rising, E_falling;
	wire [2:0] _cpuIPL;       // final IPL to CPU (Level-7 NMI applied below)
	wire [2:0] _cpuIPL_dc;    // raw IPL from dataController (VIA1 / PseudoVIA / SCC)
	wire [2:0] cpuFC;
	wire [7:0] cpuAddrHi;
	wire [31:0] cpuAddr;
	assign cpuAddr[0] = 1'b0;
	wire [7:0]  cpuAddrFullHi = cpuAddr[31:24];
	wire [15:0] cpuDataOut;

	// RAM/ROM
	wire _romOE;
	wire _ramOE, _ramWE;
	wire _memoryUDS, _memoryLDS;
	wire dioBusControl;
	wire cpuBusControl;
	wire flp_guard;
	wire [22:0] memoryAddr;  // 23-bit SDRAM word address from address controller
	wire [15:0] memoryDataOut;
	wire memoryLatch;
	// peripherals
	wire pds_slot_irq = 1'b0;  // PDS slot interrupt — single point for future PDS work
	wire vid_alt;
	wire memoryOverlayOn, selectSCSI, selectSCC, selectIWM, selectVIA, selectRAM, selectROM, selectUnmapped;
	wire selectSCSIDMA;   // SCSI pseudo-DMA window (DACK) from address decoder
	wire scsiDREQ;        // SCSI pseudo-DMA request → gates CPU DTACK on DMA cycles
	wire scsiIRQ;         // NCR5380 latched IRQ (level) → pseudo-VIA IFR bit 3
	wire [15:0] dataControllerDataOut;

	// floppy disk image interface
	wire dskReadAckInt;
	wire [21:0] dskReadAddrInt;
	// POCKET CUT: the external drive's fetch channel is gone (one drive).

	// dtack generation for 16 MHz mode
	// Phase C (ported from MiSTer cpu-icache): RAM/ROM/VRAM DTACK comes
	// straight from the SDRAM controller's demand handshake (sdram_cpu_done)
	// — the old slot-aligned grant (cpuBusControl & mem_latch_d strobe at
	// each cpu-slot start) is gone, and with it the mod-4 quantization that
	// pinned every memory access to >=8 clk_sys. dtack_en now serves ONLY
	// the immediate paths the demand engine never serves:
	//   - peripheral/unmapped space (as before), and
	//   - ROM-region WRITES (ack-and-discard, 68000/V8 style). A ROM write
	//     asserts neither oe nor we, so the engine never answers it — but
	//     the boot ROM's device-probe code WRITES into ROM space behind a
	//     temporary vector-$8 handler and requires the cycle to complete
	//     (ack or bus-error; the old slot glue acked every mem-region
	//     access regardless of oe/we). Without this the diskless ?-icon
	//     phase deadlocks at a byte write to $A6C3xx — the MiSTer
	//     2026-08-17 magenta-screen boot stall. (MAME confirms hardware
	//     discards ROM writes silently: v8.cpp maps $000000-$0FFFFF
	//     read-only with no bus error.)
	reg  dtack_en;
	always @(posedge clk_sys) begin
		if (!_cpuReset) begin
			dtack_en <= 0;
		end
		else begin
			if (_cpuAS) dtack_en <= 0;
			if (!_cpuAS & ( (!selectROM & !selectRAM & !selectVRAM)
			              | (selectROM & !_cpuRW) )) dtack_en <= 1;
		end
	end

	// VRAM ($F40000-$FBFFFF, cpuAddr[23:21]==111) must use async DTACK like RAM,
	// not the 6800 E-clock VPA peripheral path — the VPA path samples on a fixed
	// E-phase that misses the SDRAM cpu-slot and returns stale data, mis-sizing
	// the video bank and leaving the screen black.
	// FC=7 is the 68k CPU space. cpuAddr[19:16] is the CPU-space cycle-type field:
	//   $F = interrupt acknowledge  -> autovector via VPA (Mac autovectored IRQs)
	//   else ($0 breakpoint, $2 coprocessor, ...) = no responder -> bus error.
	// The boot ROM probes for hardware with `moves.w $22000,D1` (SFC=7), an access
	// that MUST bus-error; asserting VPA there wrongly completes the probe and
	// corrupts the machine-config word, routing boot into the STM serial
	// diagnostic instead of the desktop. See memory: stm-root-cause-moves-berr.
	wire        fc7_iack = (cpuFC == 3'b111) && (cpuAddr[19:16] == 4'hF);
	// FC=7 non-IACK = CPU space with no responder (breakpoint/coprocessor/probe).
	// It MUST bus-error: suppress BOTH VPA and DTACK so no responder completes the
	// cycle, regardless of the (possibly garbage) address the EA computed. The boot
	// ROM's `moves.w $22000,D1` (SFC=7) relies on this fault; if VPA/DTACK answer it
	// the probe completes inline and boot diverts into the STM serial diagnostic.
	wire        fc7_berr = (cpuFC == 3'b111) && !fc7_iack;
	// NuBus/PDS slot space ($F1000000-$FEFFFFFF) must BUS-ERROR on a cardless
	// LC — full rationale in MacLC.sv (phantom PDS card → System 7 boot Sad
	// Macs). Keep both tops identical.
	wire        slot_space = (cpuAddrFullHi >= 8'hF1) && (cpuAddrFullHi <= 8'hFE);
	// SCSI pseudo-DMA ($F06000/$F12000) uses async DTACK gated by the NCR5380 DREQ
	// instead of the 6800-style VPA path the rest of $F0xxxx uses — see MacLC.sv.
	assign      _cpuVPA = fc7_iack ? 1'b0 : ((fc7_berr || slot_space) ? 1'b1 : ~(!_cpuAS && cpuAddr[23:21] == 3'b111 && !selectVRAM && !selectSCSIDMA));
	assign      _cpuDTACK = fc7_berr ? 1'b1 :
	                        icache_hit ? 1'b0 :        // fetch-cache hit answers now
	                        (slot_space && !_cpuAS) ? 1'b0 :
	                        selectSCSIDMA ? ~scsiDREQ :
	                        // Phase C: SDRAM-backed targets ack via the demand
	                        // handshake (early-done: data is in cpu_dout before
	                        // the FSM's exit+2 din_r latch; writes post at ACTIVE).
	                        // ROM WRITES are excluded: the engine never serves
	                        // them (no oe/we) — they ack-and-discard via dtack_en.
	                        (!_cpuAS && (selectRAM || selectVRAM || (selectROM && _cpuRW))) ? ~sdram_cpu_done :
	                        // $Fxxxxx VPA peripherals stay un-acked here (E/VMA
	                        // paced); everything else non-mem = immediate ack
	                        (~(!_cpuAS && cpuAddr[23:21] != 3'b111) | !dtack_en);

	// Programmer's switch / Level-7 NMI — mirror of MacLC.sv (there the trigger is
	// the "R5" OSD button status[5]; in sim it is the nmi_pulse input driven by
	// --nmi-at-frame). Verifies the level-7 autovector path our CPU+glue takes.
	reg        nmi_req   = 1'b0;
	reg        nmi_btn_d = 1'b0;
	reg [15:0] nmi_to    = 16'd0;
	always @(posedge clk_sys) begin
		nmi_btn_d <= nmi_pulse;
		if (nmi_pulse && !nmi_btn_d) begin
			nmi_req <= 1'b1;
			nmi_to  <= 16'hFFFF;
			$display("[F%0d] NMI: asserted (Level-7 requested)", sim_frame_count);
		end else if (nmi_req) begin
			if ((fc7_iack && cpuAddr[3:1] == 3'b111) || nmi_to == 16'd0) begin
				nmi_req <= 1'b0;
				$display("[F%0d] NMI: cleared (%s)", sim_frame_count,
					(fc7_iack && cpuAddr[3:1] == 3'b111) ? "level-7 IACK TAKEN" : "timeout");
			end else
				nmi_to <= nmi_to - 1'b1;
		end
	end
	assign _cpuIPL = nmi_req ? 3'b000 : _cpuIPL_dc;

	wire        cpu_en_p      = clk16_en_p;
	wire        cpu_en_n      = clk16_en_n;
	assign      _cpuReset_o   = tg68_reset_n;
	assign      _cpuRW        = tg68_rw;
	assign      _cpuAS        = tg68_as_n;
	assign      _cpuUDS       = tg68_uds_n;
	assign      _cpuLDS       = tg68_lds_n;
	assign      E_falling     = tg68_E_falling;
	assign      E_rising      = tg68_E_rising;
	assign      _cpuVMA       = tg68_vma_n;
	assign      cpuFC[0]      = tg68_fc0;
	assign      cpuFC[1]      = tg68_fc1;
	assign      cpuFC[2]      = tg68_fc2;
	assign      cpuAddr[31:1] = tg68_a[31:1];
	assign      cpuDataOut    = tg68_dout;

	wire        tg68_rw;
	wire        tg68_as_n;
	wire        tg68_uds_n;
	wire        tg68_lds_n;
	wire        tg68_E_rising;
	wire        tg68_E_falling;
	wire        tg68_vma_n;
	wire        tg68_fc0;
	wire        tg68_fc1;
	wire        tg68_fc2;
	wire [15:0] tg68_dout;
	wire [31:0] tg68_a;
	wire [31:0] tg68_a_early;   // pre-AS address for the fetch cache
	wire        tg68_reset_n;
	wire        tg68_longword;   // 32-bit access flag — drives SCSI pseudo-DMA byte packing
	wire [1:0]  tg68_busstate;

	// BERR: autovector path only for now. Unmapped-BERR disabled — see
	// docs/plan_040526.md: enabling it regresses boot because the CPU
	// emits high-bit addresses ($50xxxxxx etc.) early in ROM execution.
	// Bus-error CPU-space (FC=7) accesses that are NOT interrupt acknowledges:
	// the boot ROM's hardware-presence probes (`moves` to CPU space) which a real
	// 68030 faults because nothing decodes the cycle.
	// Slot-space: ACK with $FFFF (NuBus open-bus, the LBMacTwo
	// empty-slot mechanism) — TG68 berr is not handler-recoverable for
	// normal cycles. Keep both tops identical (MacLC.sv has the rationale).
	// Pseudo-DMA stall timeout → BERR — mirror of MacLC.sv (rationale there).
	// ★ 2026-08-11: was 23'd8125000 (~250 ms), inherited from MacLC.sv. That
	// value is safe upstream because DREQ arrives normally there and the
	// timeout essentially never fires. Here it fires on EVERY pseudo-DMA
	// access, and each one costs a quarter of a second: measured on hardware
	// the CPU advanced ~487 bus cycles per ~1.5 s, roughly 6000x slower than a
	// healthy machine. It was not hung -- it was crawling, which is why video
	// lines crept onto the screen.
	//
	// A real Mac's bus timeout is MICROSECONDS, not milliseconds, so 250 us is
	// the more hardware-faithful number as well as the usable one. It is still
	// ★★ 2026-08-12 (buildZ): BACK TO ~250 ms — the 250 us cut was calibrated
	// against a LIE. Its comment claimed "apf_blockdev fetches the sector
	// BEFORE the data phase begins, so DREQ never waits on the OS" — false
	// for the FIRST byte of every sector: the ROM issues READ(6) and starts
	// its pseudo-DMA access immediately, while the blockdev's OS round-trip
	// (bridge command -> SD card -> buffer, MILLISECONDS) is still in
	// flight. At 250 us the access died via sdma_berr long before data
	// existed; the ROM abandoned the disk, and the sector arrived to an
	// empty room. Captured on hardware (SCS1/SCS2, buildY): target frozen
	// in DATA-IN, BSY held, byte 0 (0x45 'E' of "ER") still offered, last
	// opcode = READ6, zero bytes taken. MiSTer never saw this because HPS
	// served sectors in tens of us.
	// 250 ms only ever costs time when DREQ genuinely never comes (dead
	// target), which selection timeouts already bound at boot scan.
	localparam SDMA_TIMEOUT = 23'd8125000;  // ~250 ms @ 32.5 MHz (MiSTer parity)
	reg [22:0] sdma_stall_ctr = 23'd0;
	reg        sdma_berr      = 1'b0;
	reg [22:0] sdma_stall_max = 23'd0;   // anchor feed (psdt), MiSTer form
	reg [7:0]  sdma_berr_cnt  = 8'd0;    // anchor feed (psdt), MiSTer form
	always @(posedge clk_sys) begin
		if (!_cpuReset) begin
			sdma_stall_ctr <= 0;
			sdma_berr      <= 0;
		end else if (_cpuAS) begin
			sdma_stall_ctr <= 0;
			sdma_berr      <= 0;
		end else if (selectSCSIDMA && !scsiDREQ && !sdma_berr) begin
			sdma_stall_ctr <= sdma_stall_ctr + 23'd1;
			if (sdma_stall_ctr > sdma_stall_max) sdma_stall_max <= sdma_stall_ctr;
			if (sdma_stall_ctr == SDMA_TIMEOUT) begin
				sdma_berr <= 1'b1;   // held until AS deasserts
				if (sdma_berr_cnt != 8'hFF) sdma_berr_cnt <= sdma_berr_cnt + 8'd1;
`ifdef SIMULATION
				$display("SDMA_BERR_TIMEOUT: addr=%h @%0t", cpuAddr, $time);
`endif
			end
		end else if (selectSCSIDMA)
			sdma_stall_ctr <= 0;
	end

	// --- Active pseudo-DMA stall snapshot (ported from MiSTer with the
	// anchor completion, 2026-08-17) — latches the live SCSI engine state
	// the FIRST time a DACK access is DREQ-starved past SDMA_SNAP_THRESH.
	// These registers exist to be ANCHORED (psds/psd2/psd3): they load the
	// ncr5380/scsi.v witness cones so the pseudo-DMA datapath synthesis
	// cannot fold into the marginal forms the anchor law exists to prevent.
	localparam SDMA_SNAP_THRESH = 23'd520000;   // ~16 ms @ 32.5 MHz (tunable)
	reg        sdma_snapped    = 1'b0;
	reg [15:0] sdma_snap_scsi2 = 16'd0;
	reg [31:0] sdma_snap_ncr   = 32'd0;
	reg [31:0] sdma_snap_wr    = 32'd0;
	always @(posedge clk_sys) begin
		if (!_cpuReset)
			sdma_snapped <= 1'b0;
		else if (!sdma_snapped && sdma_stall_ctr == SDMA_SNAP_THRESH) begin
			sdma_snap_scsi2 <= dbg_scsi2_w;   // phase0/1, io_rd, io_wr, io_ack
			sdma_snap_ncr   <= dbg_ncr_w;     // dreq/dma_en/dma_ack/holdoff/mr_dma/pmatch/tcr
			sdma_snap_wr    <= dbg_wr_w;      // data_cnt/phase/io_busy/sd_buff_sel/data_complete
			sdma_snapped    <= 1'b1;
		end
	end

	wire cpu_berr = (fc7_berr && !_cpuAS) || sdma_berr;

	// ── Fetch cache (ported from MiSTer cpu-icache, HW-validated there
	// 2026-08-19) ───────────────────────────────────────────────────────────
	// ★ Fed the EARLY address (tg68_a_early = the kernel's combinational
	// output): the Phase-B FSM registers cpuAddr on the same edge AS falls, so
	// the module's correspondence guard rejects every fetch on the registered
	// address — 100% miss, silently. See rtl/fetch_cache.sv.
	// ★ The MiSTer "cache corrupts / hangs" history is CLOSED — it was TWO
	// independent silicon-only defects, both fixed and both still required:
	//   1. M10K read-during-write (rdw_collide in fetch_cache.sv);
	//   2. abandoned-transaction stale-done in the SDRAM controller (a hit
	//      lets the CPU abandon its demand transaction; the orphan early-done
	//      could falsely complete the NEXT cycle — the done-birth `&& oe`
	//      guard in pocket_sdram.v).
	// Any new agent that can abandon a bus request re-opens class 2.
	// ★ ALWAYS ON (MiSTer user ruling 2026-08-19, after HW validation): no
	// menu toggle — .enable is hardwired.
	wire        icache_hit;
	wire [15:0] icache_data;
	wire        icache_hit_now;   // per-access request-suppression verdict
	fetch_cache #(.LOG2_WORDS(9)) icache (
		.clk        ( clk_sys ),
		.reset      ( ~_cpuReset ),
		.flush_bits ( {memoryOverlayOn, dio_download} ),
		.enable     ( 1'b1 ),
		.cpuAddr    ( tg68_a_early[23:0] ),
		.as_n       ( _cpuAS ),
		.rw         ( _cpuRW ),
		.fc         ( cpuFC ),
		.cacheable  ( selectRAM || selectROM ),
		.snoopable  ( selectRAM ),
		.mem_din    ( dataControllerDataOut ),
		.hit        ( icache_hit ),
		.hit_data   ( icache_data ),
		.hit_now    ( icache_hit_now )
	);

	// ---- VPA peripheral read: register the data one clk_sys stage ----------
	// ★ PORTED FROM MacLC.sv.reference:985-999 on 2026-08-11. This fix existed
	// upstream and mac_lc_pocket dropped it at import -- neither vpa_periph_read
	// nor periph_din_reg existed here at all, and .din was just
	// (slot_space ? 16'hFFFF : dataControllerDataOut).
	//
	// Upstream's rationale, verbatim in spirit: the peripheral read mux is the
	// deepest combinational cone in the design -- scsi.v phase reg -> bsy ->
	// |target_bsy (cross-module) -> wide OR -> CSR (ncr5380.sv) -> long
	// inter-module route -> the 7-way cpuDataOut mux (dataController_top.sv) ->
	// CPU din. SCSI CSR bit6 (scsi_bsy) is the worst path; bit1 (scsi_sel) is a
	// shallow local ICR bit. So the guest read bit1 correctly and bit6
	// incorrectly depending on placement, which upstream named "the dice-roll
	// boot" -- boots that succeed or fail per fit and per power-up.
	//
	// That is precisely the symptom this fork has, and it also explains why the
	// failure looked SCSI-shaped (POST reads the CSR) while surviving a
	// perfectly intact ROM load.
	//
	// The VPA window is >= 5 clk_sys cycles from address/select settle to the
	// data sample, so the extra register stage is absorbed completely: no
	// DTACK/VMA change is needed and the memory (DTACK) read path is untouched.
	// periph_din_reg is CONSUMED only during VPA reads, when the CPU holds its
	// combinational input stable. core_constraints.sdc carries the matching 2x
	// multicycle so STA reports the real E-paced margin instead of
	// over-constraining this to one 30.8 ns period.
	wire vpa_periph_read = !fc7_iack && !fc7_berr && !slot_space && !_cpuAS &&
	                       (cpuAddr[23:21] == 3'b111) && !selectVRAM && !selectSCSIDMA;
	reg [15:0] periph_din_reg;
	always @(posedge clk_sys) periph_din_reg <= dataControllerDataOut;
	wire [15:0] cpu_din_muxed = slot_space      ? 16'hFFFF :
	                            icache_hit      ? icache_data :
	                            vpa_periph_read ? periph_din_reg :
	                                              dataControllerDataOut;
`ifdef SIMULATION
	reg _cpuAS_d;
	always @(posedge clk_sys) _cpuAS_d <= _cpuAS;
	always @(posedge clk_sys) begin
`ifdef VERBOSE_TRACE
		if (_cpuAS_d && !_cpuAS && cpuBusControl && selectUnmapped)
			$display("[F%0d] BERR_UNMAPPED: addr=%h fc=%b rw=%b", sim_frame_count, cpuAddr, cpuFC, _cpuRW);
		if (_cpuAS_d && !_cpuAS && |cpuAddrFullHi)
			$display("[F%0d] HIGH_ADDR: hi=%h addr=%h fc=%b rw=%b", sim_frame_count, cpuAddrFullHi, cpuAddr, cpuFC, _cpuRW);
`endif
	end
`endif

	tg68k tg68k (
		.clk        ( clk_sys      ),
		.reset      ( !_cpuReset ),
		.phi1       ( cpu_en_p  ),
		.phi2       ( cpu_en_n  ),
		.cpu        ( {status_cpu[1], |status_cpu} ),

		.dtack_n    ( _cpuDTACK  ),
		.rw_n       ( tg68_rw    ),
		.as_n       ( tg68_as_n  ),
		.uds_n      ( tg68_uds_n ),
		.lds_n      ( tg68_lds_n ),
		.fc         ( { tg68_fc2, tg68_fc1, tg68_fc0 } ),
		.reset_n    ( tg68_reset_n ),

		.E          (  ),
		.E_div      ( 1'b1 ),
		.E_PosClkEn ( tg68_E_falling ),
		.E_NegClkEn ( tg68_E_rising  ),
		.vma_n      ( tg68_vma_n ),
		.vpa_n      ( _cpuVPA ),

		.br_n       ( 1'b1    ),
		.bg_n       (  ),
		.bgack_n    ( 1'b1 ),

		.ipl        ( _cpuIPL ),
		.berr       ( cpu_berr ),
		.din        ( cpu_din_muxed ),
		.dout       ( tg68_dout ),
		.longword   ( tg68_longword ),
		.addr       ( tg68_a ),
		.addr_early ( tg68_a_early ),
		.busstate   ( tg68_busstate )
	);

	// CPU debug - capture PC and opcode during instruction fetch
	// busstate: 00 = fetch code, 10 = read data, 11 = write data, 01 = idle
	reg [31:0] last_fetch_pc;
	reg [15:0] last_fetch_opcode;
	reg        fetch_valid;
	reg        prev_as_n;
	reg [1:0]  prev_busstate;
	reg        as_falling_seen;
	reg [31:0] fetch_addr_latch;

	always @(posedge clk_sys) begin
		if (!n_reset) begin
			fetch_valid <= 0;
			prev_as_n <= 1;
			prev_busstate <= 2'b01;
			as_falling_seen <= 0;
			last_fetch_pc <= 0;
			last_fetch_opcode <= 0;
			fetch_addr_latch <= 0;
		end else begin
			// Default: clear fetch_valid after one cycle
			fetch_valid <= 0;

			// Track AS edges and busstate
			prev_as_n <= tg68_as_n;
			prev_busstate <= tg68_busstate;

			// Latch address when AS goes low during instruction fetch
			if (prev_as_n && !tg68_as_n && tg68_busstate == 2'b00) begin
				fetch_addr_latch <= tg68_a;
				as_falling_seen <= 1;
			end

			// Capture on AS rising edge (bus cycle complete) if this was a fetch
			if (!prev_as_n && tg68_as_n && as_falling_seen && prev_busstate == 2'b00) begin
				last_fetch_pc <= fetch_addr_latch;
				last_fetch_opcode <= dataControllerDataOut;
				fetch_valid <= 1;
				as_falling_seen <= 0;
			end

			// Clear if busstate changes away from fetch before completion
			if (tg68_busstate != 2'b00 && prev_busstate == 2'b00) begin
				as_falling_seen <= 0;
			end
		end
	end

	// Latch data address during non-fetch bus cycles (data read/write)
	reg [31:0] last_data_addr;
	always @(posedge clk_sys) begin
		if (!n_reset)
			last_data_addr <= 0;
		else if (prev_as_n && !tg68_as_n && tg68_busstate != 2'b00)
			last_data_addr <= tg68_a;
	end

	// ★ buildAS IIOP: the FAULTING FETCH, data included. The games-disk death
	// is an Illegal Instruction whose PCRB trail ends at `jmp (a1)` in the QD
	// blit dispatcher (A2CC32) with no visible fetch at the jump target; the
	// MiSTer-identical kernel executes the same ROM fine, so the question is
	// what the CPU actually FETCHED there. This ring holds the last 4
	// completed FETCH cycles {pc[23:0], data[15:0]} plus the last 2 completed
	// bus cycles of ANY kind {busstate[1:0], addr[23:0], data[15:0]} (in case
	// jump-target fetches carry a different busstate), frozen the moment a
	// DATA READ of $000010 completes = the vector-4 (Illegal Instruction)
	// dispatch read. Nothing else reads $10. Source bit = re-arm toggle.
	// Probe layout (LSB first):
	//   [159:0]   4 x {pc[23:0], data[15:0]} ring; newest slot = wptr-1 mod 4
	//   [243:160] 2 x {busstate[1:0], addr[23:0], data[15:0]}, upper = newer
	//   [245:244] fetch-ring wptr
	//   [247]     frozen
	reg [39:0] iiop_f [0:3];
	reg [41:0] iiop_a [0:1];
	// ★ buildAT side-car: the TOP address byte (tg68_a[31:24]) of each ring
	// slot, exposed via IIO2 — a phantom-card fault jumps/fetches in
	// $FExxxxxx space, whose low 24 bits alias low RAM in the main rings.
	reg  [7:0] iiop_fh [0:3];
	reg  [7:0] iiop_ah [0:1];
	reg  [1:0] iiop_fw = 2'd0;
	reg        iiop_az = 1'b0;
	reg        iiop_frozen = 1'b0;
	// buildAU: source widened to 2 bits — [0] = rearm (any edge), [1] =
	// freeze-the-machine-on-trigger enable (level). With [1] set, the
	// vector-4 dispatch read freezes the MACHINE (reset-hold, RAM intact),
	// not just the capture rings.
	// ---- Instrument switches (buildAZ, 2026-08-14) -------------------------
	// USE_BOOT_ISSP turns on the FULL probe deck (the historical debug fit).
	// IIOP/IIO2, WWSP and WW40 predated per-instrument gating and were
	// unconditional; each now has its own switch so a probe-less build can
	// re-enable ONE instrument with a single qsf line, e.g.
	//     set_global_assignment -name VERILOG_MACRO "USE_ISSP_IIOP=1"
	// while USE_BOOT_ISSP stays off. Lever LOGIC is never guarded — only the
	// altsource_probe instances — so an absent probe's source ties to 0 and
	// the machinery constant-folds away.
`ifdef USE_BOOT_ISSP
 `ifndef USE_ISSP_IIOP
  `define USE_ISSP_IIOP
 `endif
 `ifndef USE_ISSP_WWSP
  `define USE_ISSP_WWSP
 `endif
 `ifndef USE_ISSP_WW40
  `define USE_ISSP_WW40
 `endif
`endif

	wire [1:0] iiop_src;
	wire       iiop_rearm = iiop_src[0];
	reg        iiop_rearm_d = 1'b0;
	// ★ buildAV WW40: last 4 completed WRITES to guest $400E6x, frozen with
	// the capture (iiop_frozen). This is the discriminator: it shows WHO wrote
	// the illegal $400E6C=4C4B and WHAT value — if the segment loader wrote
	// 4C4B, the content is as-authored/relocated (image path); if a different
	// value was written and RAM now holds 4C4B, that is a Pocket write-path
	// corruption. Uses the WORKING capture-freeze, not machine-freeze.
	reg [18:0] ww40 [0:3];   // {addr[3:1], data[15:0]}
	reg  [1:0] ww40_w = 2'd0;
	reg  [7:0] ww40_cnt = 8'd0;
	// ★ buildAX WWSP: last 8 completed WRITES to the two pages the 7.1 fault
	// lives in — $3FF7xx (the live boot-stack band; the Gestalt patch's frame
	// and the return slot the fatal RTS pops) and $400Exx (BootGlobals + the
	// boot-blocks image control lands in). Each slot latches the WRITER's PC
	// (last completed fetch) alongside {page, offset, data} — this is the
	// instrument that NAMES the agent that overwrites the patch's return slot
	// (IIOP caught AAAA -> $3FF76E as the machine's last write before the
	// fatal fetches; MAME 0.264 boots the same image+ROM clean, so the writer
	// is a Pocket-side divergence). 8 slots because the II's own exception-
	// frame pushes land in $3FF7xx between the fatal RTS and the vector-4
	// freeze: they consume 3-4 slots (and pinpoint A7-at-fault); the culprit
	// writes survive in the older slots. Frozen/re-armed with the IIOP deck.
	// Slot = {page(1: 0=$3FF7xx 1=$400Exx), off[7:1](7), data[15:0], wpc[23:0]}
	reg [47:0] wwsp [0:7];
	reg  [2:0] wwsp_w = 3'd0;
	reg  [7:0] wwsp_cnt = 8'd0;
	wire wwsp_hit_stk = (tg68_a[23:8] == 16'h3FF7);
	wire wwsp_hit_bg  = (tg68_a[23:8] == 16'h400E);
	always @(posedge clk_sys) begin
		iiop_rearm_d <= iiop_rearm;
		// registered machine-freeze (buildAV)
		iiop_mfreeze <= iiop_frozen && iiop_src[1];
		if (iiop_rearm != iiop_rearm_d) begin
			iiop_frozen <= 1'b0;
			iiop_fw     <= 2'd0;
			iiop_az     <= 1'b0;
			ww40_w      <= 2'd0;
			ww40_cnt    <= 8'd0;
			wwsp_w      <= 3'd0;
			wwsp_cnt    <= 8'd0;
		end else if (!iiop_frozen) begin
			// WW40: completed WRITE cycle (busstate 11) to $400E6x
			if (!prev_as_n && tg68_as_n && prev_busstate == 2'b11 &&
			    tg68_a[23:4] == 20'h400E6) begin
				ww40[ww40_w] <= {tg68_a[3:1], cpu_din_muxed};
				ww40_w   <= ww40_w + 2'd1;
				ww40_cnt <= ww40_cnt + 8'd1;
			end
			// WWSP: completed WRITE cycle to either hot page, with writer PC
			if (!prev_as_n && tg68_as_n && prev_busstate == 2'b11 &&
			    (wwsp_hit_stk || wwsp_hit_bg)) begin
				wwsp[wwsp_w] <= {wwsp_hit_bg, tg68_a[7:1], cpu_din_muxed,
				                 last_fetch_pc[23:0]};
				wwsp_w   <= wwsp_w + 3'd1;
				wwsp_cnt <= wwsp_cnt + 8'd1;
			end
			// completed FETCH cycle (same qualification as the PCRB tap)
			if (!prev_as_n && tg68_as_n && prev_busstate == 2'b00) begin
				iiop_f[iiop_fw]  <= {fetch_addr_latch[23:0], cpu_din_muxed};
				iiop_fh[iiop_fw] <= fetch_addr_latch[31:24];
				iiop_fw <= iiop_fw + 2'd1;
			end
			// completed cycle of ANY busstate (fetch or data)
			if (!prev_as_n && tg68_as_n) begin
				iiop_a[iiop_az]  <= {prev_busstate, tg68_a[23:0], cpu_din_muxed};
				iiop_ah[iiop_az] <= tg68_a[31:24];
				iiop_az <= ~iiop_az;
				// the vector-4 dispatch: a completing DATA READ at $00000010/$12.
				// ★ buildAT: qualify the FULL 32-bit address — the buildAS
				// [23:2] match also fired on the PDS probe's $FE000010 read
				// (24-bit alias of $10), freezing the capture pre-fault.
				if (prev_busstate == 2'b10 && tg68_a[31:2] == 30'd4)
					iiop_frozen <= 1'b1;
			end
		end
	end
	// NOTE tg68_a during AS-rise still holds the cycle's address; busstate is
	// registered (prev_busstate) to match. cpu_din_muxed is what the KERNEL
	// consumed (slot_space reads = $FFFF, VPA reads = the registered value) —
	// buildAS stored dataControllerDataOut and read the leaked 24-bit-aliased
	// mux value on slot-space cycles instead.

	// ★ buildAT IIO2: PDS-probe witness. Counts completed slot_space cycles
	// and keeps the last two {addr[7:0], kernel data[15:0]} — proves what the
	// ROM's $FE-space card probe ($A4BEB0 family) actually read. Cleared on
	// the same IIOP re-arm edge.
	reg  [7:0] fe_cnt = 8'd0;
	reg [23:0] fe_last = 24'd0, fe_prev = 24'd0;
	always @(posedge clk_sys) begin
		if (iiop_rearm != iiop_rearm_d) begin
			fe_cnt  <= 8'd0;
			fe_last <= 24'd0;
			fe_prev <= 24'd0;
		end else if (!prev_as_n && tg68_as_n && slot_space) begin
			fe_cnt  <= fe_cnt + 8'd1;
			fe_prev <= fe_last;
			fe_last <= {tg68_a[8:1], cpu_din_muxed};
		end
	end
	// Layout (LSB first): fe_last[23:0], fe_prev[23:0], fe_cnt[7:0],
	// ah0, ah1, fh0..fh3 (top address bytes of the IIOP ring slots).
`ifdef USE_ISSP_IIOP
	altsource_probe #(
		.instance_id ("IIO2"), .probe_width (104), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_iio2 (.probe({iiop_fh[3], iiop_fh[2], iiop_fh[1], iiop_fh[0],
	                   iiop_ah[1], iiop_ah[0],
	                   fe_cnt, fe_prev, fe_last}),
	           .source(), .source_clk(clk_sys), .source_ena(1'b1));
	altsource_probe #(
		.instance_id ("IIOP"), .probe_width (248), .source_width (2),
		.sld_auto_instance_index ("YES")
	) cp_iiop (
		.probe({iiop_frozen, 1'b0, iiop_fw,
		        iiop_a[~iiop_az], iiop_a[iiop_az],
		        iiop_f[3], iiop_f[2], iiop_f[1], iiop_f[0]}),
		.source(iiop_src), .source_clk(clk_sys), .source_ena(1'b1));
`else
	assign iiop_src = 2'd0;   // probe absent: rearm/mfreeze levers released
`endif
	// ★ buildAX WWSP probe: {wwsp_w[2:0], wwsp_cnt[7:0], wwsp[7]..wwsp[0]}.
	// Slot = {page(1), off[7:1](7), data[15:0], wpc[23:0]}; page 0 = $3FF7xx,
	// page 1 = $400Exx. Newest = slot (wwsp_w-1) mod 8; wwsp_cnt = total hits
	// this arm (wraps). Decoder: scripts/wwsp.tcl.
`ifdef USE_ISSP_WWSP
	altsource_probe #(
		.instance_id ("WWSP"), .probe_width (395), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_wwsp (.probe({wwsp_w, wwsp_cnt, wwsp[7], wwsp[6], wwsp[5], wwsp[4],
	                   wwsp[3], wwsp[2], wwsp[1], wwsp[0]}),
	           .source(), .source_clk(clk_sys), .source_ena(1'b1));
`endif

	// ★ buildAV WW40 probe: {ww40_w[1:0], ww40_cnt[7:0], ww40[3..0]}.
	// Each ww40 slot = {addr[3:1] (3b), data[15:0]}. Newest write = slot
	// (ww40_w-1) mod 4. ww40_cnt = total $400E6x writes seen this arm.
`ifdef USE_ISSP_WW40
	altsource_probe #(
		.instance_id ("WW40"), .probe_width (86), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_ww40 (.probe({ww40_w, ww40_cnt, ww40[3], ww40[2], ww40[1], ww40[0]}),
	           .source(), .source_clk(clk_sys), .source_ena(1'b1));
`endif


	assign debug_pc = last_fetch_pc;
	assign debug_opcode = last_fetch_opcode;
	assign debug_fetch_valid = fetch_valid;
	assign debug_data_addr = last_data_addr;

	addrController_top ac0
	(
		.clk(clk_sys),
		.clk8(clk8),
		.clk8_en_p(clk8_en_p),
		.clk8_en_n(clk8_en_n),
		.clk16_en_p(clk16_en_p),
		.clk16_en_n(clk16_en_n),
		._cpuReset(_cpuReset),
		.cpuAddr(cpuAddr),
		._cpuUDS(_cpuUDS),
		._cpuLDS(_cpuLDS),
		._cpuRW(_cpuRW),
		._cpuAS(_cpuAS),
		.ram_config(pvia_ram_config_out),
		.ram_config_phys(configRAMSize),
		.ram_configured(pvia_ram_configured),
		.memoryAddr(memoryAddr),
		.memoryLatch(memoryLatch),
		._memoryUDS(_memoryUDS),
		._memoryLDS(_memoryLDS),
		._romOE(_romOE),
		._ramOE(_ramOE),
		._ramWE(_ramWE),
		.dioBusControl(dioBusControl),
		.cpuBusControl(cpuBusControl),
		.flp_guard(flp_guard),
		.cpu_wr_ack(sdram_cpu_done),
		.flp_present(dsk_int_ins),
		.dio_download(dio_download),
		.selectSCSI(selectSCSI),
		.selectSCSIDMA(selectSCSIDMA),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectASC(selectASC),
		.selectVIA(selectVIA),
		.selectRAM(selectRAM),
		.selectROM(selectROM),
		.selectAriel(selectAriel),
		.selectPseudoVIA(selectPseudoVIA),
		.selectVRAM(selectVRAM),
		.selectUnmapped(selectUnmapped),
		.words_per_line(v8_words_per_line),
		.vram_waddr(vram_bram_waddr),
		.vram_we(vram_bram_we),
		.vram_force_512k(vram_force_512k),
		.memoryOverlayOn(memoryOverlayOn),
		.overlay_trigger_addr(),  // debug output, unused in sim


		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt)
	);

	wire diskEject;
	wire diskMotor, diskAct;

	// Video Mode Selection - from PVIA video_config register (bits 2:0 = bpp mode)
	wire [7:0] pvia_video_config;
	wire [7:0] asc_data_out;
	wire asc_irq;

	// Use actual video mode from pseudovia (ROM configures this via register 0x10)
	wire [2:0] v8_video_mode = pvia_video_config[2:0];

	// Monitor ID: 12" RGB, 512x384.
	//
	// POCKET CUT: this MUST be 4'h2 now. maclc_v8_video no longer decodes
	// monitor_id for timing -- the scanout is hardwired to 512x384 -- but
	// monitor_id is still the sense value pseudovia reports to the ROM, and
	// the guest lays out QuickDraw from it. Leaving the inherited 4'h6
	// (640x480 VGA) produced a genuinely mismatched machine: the guest built
	// a 640-wide framebuffer with a 1024-byte stride while the hardware
	// scanned 512 wide, so addrController's packing dropped the right 128
	// columns and the bottom 96 lines of everything the guest drew. It still
	// rendered a plausible-looking desktop, which is exactly what makes this
	// worth a comment -- the failure is a silent crop, not a blank screen.
	wire [3:0] v8_monitor_id = 4'h2;

	ariel_ramdac ariel(
		.clk_sys(clk_sys),
		.clk_pix(clk_pix),   // real pixel clock on FPGA (sim.v used clk_sys)
		.reset(~n_reset),
		.reg_addr(cpuAddr[10:0]),
		.uds_n(_cpuUDS),
		.lds_n(_cpuLDS),
		.data_in(cpuDataOut[7:0]),
		.data_out(ariel_reg_dout),
		.we(selectAriel && !_cpuRW && cpuBusControl),
		.req(selectAriel && cpuBusControl),
		.mem_latch(memoryLatch),
		.cpu_as_n(_cpuAS),

		.pixel_index(ariel_pixel_addr),
		.rgb_out(ariel_palette_data),
		.ariel_written()  // Not used in sim
	);

	// Debug: disabled for now

	// Pseudovia register select is byte-granular and needs A0, which the 16-bit bus
	// drops (cpuAddr[0] is forced 0). Use the real A0 from the CPU (tg68_a[0]) for the
	// register LSB, matching MacLC.sv. Without it, odd registers alias to the even one
	// below — notably the V8 RAM-config reg $01 (which enables the $0 motherboard
	// mirror) aliases to reg $00 (port_b), so ram_configured never sets and the boot's
	// relocation trampoline reads a non-mirrored $0 stack -> garbage. (sim-only bug;
	// MacLC.sv already used tg68_a[0] here.)
	pseudovia pvia(
		.clk_sys(clk_sys),
		.reset(~n_reset),
		.addr({cpuAddr[12:1], tg68_a[0]}),
		.data_in(cpuDataOut[7:0]),
		.data_out(pseudovia_dout),
		.we(selectPseudoVIA && !_cpuRW && cpuBusControl),
		.req(selectPseudoVIA && cpuBusControl),
		.vblank_irq(v8_vblank_s),
		.slot_irq(pds_slot_irq),
		.asc_irq(asc_irq),
		// SCSI flags RE-TIED-OFF (2026-06-12 evening) — matches MacLC.sv
		// (full reversal history there: the dack=14592 post-Happy-Mac
		// crash-restart tracks THIS wiring, not the phantom card; the
		// "driver sleeps without it" rationale was actually the LocalTalk
		// LAP defer, fixed in scc.v).
		.scsi_irq(1'b0),
		.scsi_drq(1'b0),
		.irq_out(pseudovia_irq),
		.ram_config(configRAMSize),
		.monitor_id(v8_monitor_id),
		.video_config(pvia_video_config),
		.ram_config_out(pvia_ram_config_out),
		.ram_configured(pvia_ram_configured)
	);

	// ASC sample outputs (Commit C will route to AUDIO_L/R)
	wire signed [15:0] asc_sample_l;
	wire signed [15:0] asc_sample_r;
	wire               asc_sample_tick;

	asc asc_inst(
		.clk(clk_sys),
		.reset(~n_reset),
		.cs(selectASC),
		// cpuAddr[0] is forced 0; reconstruct the real A0 (tg68_a[0]) so the
		// odd ASC registers (MODE/FIFOMODE/CLOCK) don't alias onto the even reg
		// below them. Same fix as the SWIM/IWM instance above.
		.addr({cpuAddr[11:1], tg68_a[0]}),
		// Full 16-bit write bus: the FIFO must see BOTH byte lanes so MOVE.W/
		// MOVE.L fills land every sample (see the fifo_pend note in rtl/asc.sv).
		.data_in(cpuDataOut),
		.data_out(asc_data_out),
		.we(!_cpuRW && cpuBusControl),
		.cpu_as_n(_cpuAS),
		.uds_n(_cpuUDS),
		.lds_n(_cpuLDS),
		.sample_l(asc_sample_l),
		.sample_r(asc_sample_r),
		.sample_tick(asc_sample_tick),
		.irq(asc_irq),
		.dbg_asc(dbg_asc_w)
	);

	// Historic 16.25 MHz pixel cadence: the sim keeps scanout on clk_sys with a
	// /2 advance enable (the FPGA now runs the module on a real per-monitor
	// pixel clock with pix_ce=1 — see rtl/pll_video.v / MacLC.sv). Keeping the
	// sim on the old grid preserves boot frame counts (screenshot @350 etc).
	// POCKET: the V8 scans out on the REAL dot clock with pix_ce tied high,
	// which is what MacLC.sv does on FPGA. sim.v instead ran the module on
	// clk_sys with a /2 toggle — 32.5/2 = 16.25 MHz, which would give
	// 16.25e6 / (640*407) = 62.4 Hz instead of 60.15 Hz, and would hand the
	// APF scaler a video_rgb_clock that is not the pixel clock.
	maclc_v8_video v8_video(
		.clk_sys(clk_pix),
		.clk8_en_p(clk8_en_p),
		.pix_ce(1'b1),
		// MacLC.sv.reference:1663 uses vidrst_s here, not raw ~n_reset — the
		// module is clocked by clk_pix and n_reset is a clk_sys signal.
		.reset(vidrst_s),

		.video_mode(v8_video_mode),
		.monitor_id(v8_monitor_id),

		// Were left unconnected at import. v8_video 2FF-syncs both internally.
		.test_bypass_vram(test_pattern[2]),
		.test_pattern_sel(test_pattern[1:0]),

		.hsync(v8_hsync),
		.vsync(v8_vsync),
		.hblank(v8_hblank),
		.vblank(v8_vblank),
		.vga_r(v8_vga_r),
		.vga_g(v8_vga_g),
		.vga_b(v8_vga_b),
		.de(v8_de),
		.ce_pix(v8_ce_pix),  // drives CE_PIXEL so the sim samples one pixel per real pixel-clock

		.palette_addr(ariel_pixel_addr),
		.palette_data(ariel_palette_data),

		.words_per_line(v8_words_per_line),
		.vram_raddr(v8_vram_raddr),
		.vram_rdata(v8_vram_rdata)
	);

	// On-chip framebuffer (BRAM). Video reads port B (Phase 2); CPU VRAM writes
	// are mirrored into port A. Single clk_sys domain => coherent. Must match MacLC.sv.
	wire [10:0] v8_words_per_line;
	// 17 bits: addrController_top.vram_waddr and maclc_v8_video.vram_raddr are
	// both [16:0] since the video cut. These were left at [17:0] from the 16bpp
	// build, so the MSB was undriven on one end and truncated on the other.
	wire [16:0] vram_bram_waddr;
	wire        vram_bram_we;
	wire [16:0] v8_vram_raddr;
	wire [15:0] v8_vram_rdata;

	vram_bram vram_fb(
		.a_clk(clk_sys),
		// True dual-port M10K with independent port clocks, so the CPU->video
		// crossing lives INSIDE the RAM primitive — no timed cross-domain
		// paths (see rtl/vram_bram.sv).
		.b_clk(clk_pix),
		.a_addr(vram_bram_waddr),
		.a_din(memoryDataOut),
		.a_be({~_cpuUDS, ~_cpuLDS}),
		.a_we(vram_bram_we),
		.a_dout(),                 // CPU reads still from SDRAM (dropped later)
		.b_addr(v8_vram_raddr),    // video scanline prefetch
		.b_dout(v8_vram_rdata)
	);

`ifdef SIMULATION
	// Phase 1 verification: confirm CPU VRAM writes are landing in the BRAM mirror.
	reg [31:0] vram_wr_count = 0;
	always @(posedge clk_sys) begin
		if (vram_bram_we) begin
			vram_wr_count <= vram_wr_count + 1;
			if (vram_wr_count < 5 || (vram_wr_count % 50000 == 0))
				$display("[F%0d] VRAM->BRAM write #%0d waddr=%05h data=%04h be=%b wpl=%0d",
					sim_frame_count, vram_wr_count, vram_bram_waddr, memoryDataOut,
					{~_cpuUDS,~_cpuLDS}, v8_words_per_line);
		end
	end

	// ---- CPU bus throughput / stall instrumentation (perf H1 measurement) ----
	// Per 60-frame window: how much of the time the CPU has a bus request
	// outstanding (_cpuAS low) but is STILL waiting for DTACK (_cpuDTACK high) =
	// slot-starved stall, vs how many SDRAM cpu transactions actually committed.
	reg [31:0] perf_clk = 0, perf_as = 0, perf_stall = 0, perf_commit = 0;
	reg [31:0] perf_last_frame = 0;
	always @(posedge clk_sys) begin
		perf_clk <= perf_clk + 1;
		if (!_cpuAS)              perf_as     <= perf_as + 1;
		if (!_cpuAS && _cpuDTACK) perf_stall  <= perf_stall + 1;
		if (cpuBusControl && memoryLatch && (selectRAM || selectVRAM || selectROM))
		                          perf_commit <= perf_commit + 1;
		if (sim_frame_count != perf_last_frame && (sim_frame_count % 60 == 0)) begin
			perf_last_frame <= sim_frame_count;
			$display("[F%0d] PERF: clk=%0d as=%0d stall=%0d (%0d%% of as) commits=%0d",
				sim_frame_count, perf_clk, perf_as, perf_stall,
				perf_as ? (perf_stall * 100 / perf_as) : 0, perf_commit);
			perf_clk <= 0; perf_as <= 0; perf_stall <= 0; perf_commit <= 0;
		end
	end
`endif

	// SCSI slot fan-out: disks drive array slots 0,1; the CD-ROM target
	// drives slot 2 (read-only — sd_wr[2] tied off; scsi.v's CDROM mode
	// rejects WRITE commands so cd_wr_w can never fire anyway). Mirrors the
	// MacLC.sv stitching so the shared dataController sees identical shapes.
	wire [31:0] scsi_lba[2];
	wire [1:0]  scsi_rd, scsi_wr;
	wire [15:0] scsi_buff_din[2];
	wire [31:0] cd_lba_w;
	wire        cd_rd_w, cd_wr_w;
	wire [15:0] cd_buff_din_w;
	wire [31:0] dbg_cd_w;
	wire [15:0] dbg_cd_state_w;
	assign sd_lba[0] = scsi_lba[0];
	assign sd_lba[1] = scsi_lba[1];
	assign sd_lba[2] = cd_lba_w;
	assign sd_rd[1:0] = scsi_rd;
	assign sd_rd[2]   = cd_rd_w;
	assign sd_wr[1:0] = scsi_wr;
	assign sd_wr[2]   = 1'b0;
	assign sd_buff_din[0] = scsi_buff_din[0];
	assign sd_buff_din[1] = scsi_buff_din[1];
	assign sd_buff_din[2] = cd_buff_din_w;

	// SCSI debug buses (wired to the SCS1/SCS2 probes; see the ISSP deck)
	wire [15:0] dbg_scsi_w, dbg_scsi2_w, dbg_scsi4_w, dbg_scsi5_w;
	// ── Always-on marginality anchor (ported from MiSTer 2026-08-16) ────────
	// MiSTer learned this the hard way (MacLC.sv.reference:1238-1296, dates
	// 2026-07-29/08-03/08-04): probes-OFF fits of this shared RTL
	// deterministically corrupt the SCSI read path on hardware — the exact
	// signature is FINDER COLOUR-ICON GARBAGE escalating to error-11/F-Line
	// bombs — while fits whose probe fanout loads these same cones pass. STA
	// is met either way and does not predict it. The recurring fingerprint is
	// RING-STALE serving (a ring slot served at/past the rd_hps_blk fill
	// boundary); the pinned nets are the stall comparators, fill counter and
	// look-ahead adder of each disk target (scsi.v dbg_ring — comparator nets
	// shared with io_busy by construction), the write-path first-beat word,
	// and the floppy fetch cone (SDRAM slot -> dskReadDataLatch -> encoder),
	// which failed the same way on MiSTer with the SCSI anchor alone present.
	//
	// THE POCKET PORT NEVER CARRIED THIS ANCHOR (severed at import with the
	// probe decks it fed). 2026-08-16 evidence it is needed here too: the
	// rung-3 ladder netlists (buildBQ seed 2, buildBR seed 4 — two different
	// placements) both garble Finder colour icons IDENTICALLY on a
	// SHA-verified pristine disk from the first desktop draw, while the
	// rung-2 netlist (buildBP) is clean on the same disk in the same session
	// — netlist-alignment-dependent, placement-independent, exactly the
	// MiSTer-documented class. The historic Pocket fit-family behaviour
	// (hang-family vs deterministic-F-line-family fits, BM/BN era) fits the
	// same mechanism: mis-read icon data is drawn, mis-read code F-lines.
	//
	// Adaptations from the reference block, each deliberate:
	// - anchor_cda0-4/cdur: NOT ported — cd_audio.sv is cut from this fork;
	//   those cones do not exist.
	// - anchor_psdt/psds/psd2/psd3: COMPLETED 2026-08-17 (v1.0.0 field
	//   report: F-line rate returned with the trio absent — a partial
	//   anchor half-works, exactly as MiSTer's 08-03 note warns). The SDMA
	//   snapshot deck is now ported (watchdog stall_max/berr_cnt + the
	//   threshold snapshot above cpu_berr), psdt carries the reference's
	//   exact word form, and psds/psd2/psd3 pin the ncr5380/scsi.v
	//   pseudo-DMA witness cones (dbg_ncr/dbg_wr — ports existed unwired).
	// - anchor_ring0/1, anchor_wrfb, anchor_flp0/1/2: ported as-is (the
	//   witness outputs survived in shared RTL, marked "anchor feed").
	// Same law as upstream: never remove, `ifdef, or XOR-fold these
	// registers — a reduction lets synthesis restructure the pinned cones.
	// ~352 FFs is the entire cost.
	// - anchor_asc0: Pocket-only extension (2026-08-17, v1.0.0 field report:
	//   alert sound starts and never stops, machine otherwise fine, MiSTer
	//   clean on byte-identical asc.sv). Pins the ASC FIFO-A status cone
	//   (count/pointer comparators, FIFOSTAT flags, irq) — the same
	//   unpinned-comparator class as the SCSI cones, one subsystem over.
	wire [31:0] dbg_wrfb_w, dbg_ring0_w, dbg_ring1_w;
	wire [31:0] dbg_ncr_w, dbg_wr_w, dbg_asc_w;
	wire [15:0] dbg_flp_byte_cnt_w, dbg_flp_miss_cnt_w, dbg_flp_step_cnt_w;
	wire [6:0]  dbg_flp_track_w;
	wire        dbg_flp_side_w, dbg_flp_byte_stb_w;
	wire [7:0]  dbg_iwm_latch_w, dbg_flp_raw_w;
	(* preserve, noprune *) reg [31:0] anchor_psdt, anchor_psds, anchor_psd2,
	                                   anchor_psd3, anchor_wrfb,
	                                   anchor_ring0, anchor_ring1,
	                                   anchor_flp0, anchor_flp1, anchor_flp2,
	                                   anchor_asc0;
	always @(posedge clk_sys) begin
		anchor_psdt  <= {sdma_berr_cnt, 1'b0, sdma_stall_max};
		anchor_psds  <= {15'd0, sdma_snapped, sdma_snap_scsi2};
		anchor_psd2  <= sdma_snap_ncr;
		anchor_psd3  <= sdma_snap_wr;
		anchor_asc0  <= dbg_asc_w;
		anchor_wrfb  <= dbg_wrfb_w;
		anchor_ring0 <= dbg_ring0_w;
		anchor_ring1 <= dbg_ring1_w;
		anchor_flp0  <= {dbg_flp_byte_cnt_w, dbg_flp_miss_cnt_w};
		anchor_flp1  <= {dbg_flp_step_cnt_w, dbg_iwm_latch_w, dbg_flp_raw_w};
		anchor_flp2  <= {dbg_flp_byte_stb_w, dbg_flp_side_w, dbg_flp_track_w,
		                 1'b0, dskReadAddrInt};
	end

	dataController_top #(SCSI_DEVS) dc0
	(
		.clk32(clk_sys),
		.clk8_en_p(clk8_en_p),
		.clk8_en_n(clk8_en_n),
		.scsi_pclk_en(scsi_pclk_en),
		.E_rising(E_rising),
		.E_falling(E_falling),
		._systemReset(n_reset),
		._cpuReset(_cpuReset),
		._cpuIPL(_cpuIPL_dc),
		.pseudovia_irq(pseudovia_irq),
		._cpuUDS(_cpuUDS),
		._cpuLDS(_cpuLDS),
		._cpuRW(_cpuRW),
		._cpuVMA(_cpuVMA),
		.cpuDataIn(cpuDataOut),
		.cpuDataOut(dataControllerDataOut),
		.cpuAddrRegHi(cpuAddr[12:9]),
		.cpuAddrRegMid(cpuAddr[6:4]),
		.cpuAddrRegLo(cpuAddr[2:1]),
		.cpuLongword(tg68_longword),
		.selectSCSI(selectSCSI),
		.selectSCSIDMA(selectSCSIDMA),
		.scsiDREQ(scsiDREQ),
		.scsiIRQ(scsiIRQ),
		// JTAG probe feeds — FPGA-only (dbg_probes.sv lives in MacLC.sv;
		// altsource_probe is an Altera primitive, never bring it into sim)
		.dbg_scsi(dbg_scsi_w),
		.dbg_scsi2(dbg_scsi2_w),
		.dbg_scsi4(dbg_scsi4_w),
		.dbg_scsi5(dbg_scsi5_w),
		.dbg_ncr(dbg_ncr_w),
		.dbg_ncr2(),
		.dbg_wr(dbg_wr_w),
		// Marginality-anchor feeds (2026-08-16) — NOT probes; see the
		// always-on anchor block above this instantiation.
		.dbg_wrfb(dbg_wrfb_w),
		.dbg_ring0(dbg_ring0_w),
		.dbg_ring1(dbg_ring1_w),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.selectASC(selectASC),
		.asc_data_in(asc_data_out),
		.cpuBusControl(cpuBusControl),
		.memoryDataOut(memoryDataOut),
		.memoryDataIn(ram_do),
		// Floppy fetch byte on its own wire (Phase C — see the port note in
		// dataController_top.sv; ram_do is the CPU's private read data now).
		.dskReadDataIn(extra_rom_data_demux[7:0]),
		.memoryLatch(memoryLatch),
		.selectAriel(selectAriel),
		.ariel_data_in(ariel_reg_dout),
		.selectPseudoVIA(selectPseudoVIA),
		.pseudovia_data_in(pseudovia_dout),
		// ★ DROPPED AT IMPORT, restored 2026-08-11. MacLC.sv.reference:1885
		// connects this; mac_lc_pocket did not, so inside dataController_top
		// the port defaulted to constant 0 and the open-bus case at
		// dataController_top.sv:330 (`selectUnmapped ? 16'hFFFF :`) could
		// never fire. Unmapped reads therefore fell through to stale
		// memoryDataIn/cpu_data instead of 0xFFFF.
		//
		// That is precisely the regression the comment at
		// dataController_top.sv:320-329 was written to fix: the boot ROM's
		// RAM-probe XOR-pattern test cascades a value through unmapped SIMM
		// addresses, the unmapped WRITE is silently dropped (_ramWE not
		// asserted), and if the following READ returns the same value the
		// probe concludes "RAM here" instead of "no RAM here" -- a wrong
		// memory map, and a POST that dies. Because the fall-through value is
		// whatever was last on the bus, it varies per power-up, which is why
		// the failure was intermittent and looked like a timing fault.
		// The wire itself was already driven (addrController_top, line ~665);
		// only this connection was missing.
		.selectUnmapped(selectUnmapped),

		.ps2_key(ps2_key),
		.capslock(capslock),
		.ps2_mouse(ps2_mouse),
		.serialIn(serialIn),
		.serialOut(serialOut),
		.serialCTS(serialCTS),
		.dbg_scc_state(dbg_scc_state),
		.dbg_force_diag(diag_src),
		.serialRTS(serialRTS),

		.timestamp(timestamp),

		._hblank(~v8_hblank_s),
		._vblank(~v8_vblank_s),
		.vid_alt(vid_alt),


		.insertDisk(dsk_int_ins),
		.diskSides(dsk_int_ds),
		.diskMFM(dsk_int_mfm),
		.diskHD(dsk_int_hd),
		.diskEject(diskEject),
		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt),
		.diskMotor(diskMotor),
		.diskAct(diskAct),

		.img_mounted(img_mounted[1:0]),
		.img_size(img_size[40:9]),
		.io_lba(scsi_lba),
		.io_rd(scsi_rd),
		.io_wr(scsi_wr),
		.io_ack(sd_ack[1:0]),

		.sd_buff_addr(sd_buff_addr),
		.sd_buff_addr_hi(5'd0),   // sim HPS model serves 512-byte blocks only
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(scsi_buff_din),
		.sd_buff_wr(sd_buff_wr),

		// ★ 2026-08-13: the CD-ROM target (SCSI ID 3) is BACK, ISO-only, on
		// blockdev slot 2. cd_enable is hardwired: the drive is always on
		// the bus, like a real LC with a CD-ROM attached — disc-less
		// selection answers the AppleCD no-disc sense, which is how the
		// driver's insertion poll works. The A/B lever if ID-3 presence
		// ever destabilizes the bus: rebuild with 1'b0 (one variable).
		.cd_enable(1'b1),
		.cd_img_mounted(img_mounted[2]),
		.cd_io_lba(cd_lba_w),
		.cd_io_rd(cd_rd_w),
		.cd_io_wr(cd_wr_w),
		.cd_io_ack(sd_ack[2]),
		.cd_sd_buff_din(cd_buff_din_w),
		.dbg_cd(dbg_cd_w),
		.dbg_cd_state(dbg_cd_state_w),

		// PRAM: save-back still needs apf_blockdev, but the LOAD side is now
		// driven by the pram_zero FSM below so "Reset PRAM" is real.
		.pram_load_wr(pram_load_wr),
		.pram_load_addr(pram_load_addr),
		.pram_load_data(pram_load_data),
		.pram_save_addr(pram_save_addr_i),
		.pram_save_data(pram_save_data_w),
		.pram_wr_stb(pram_wr_stb_w),
		.pram_ready(pram_ready_r),

		// PFLP floppy diagnostics — on MiSTer these fed ISSP probes; here
		// they feed the always-on marginality anchor (2026-08-16). Only
		// dbg_flp_disk_data stays unconnected (not an anchor input).
		.dbg_flp_byte_cnt(dbg_flp_byte_cnt_w),
		.dbg_flp_miss_cnt(dbg_flp_miss_cnt_w),
		.dbg_flp_disk_data(),
		.dbg_flp_track(dbg_flp_track_w),
		.dbg_flp_side(dbg_flp_side_w),
		.dbg_flp_step_cnt(dbg_flp_step_cnt_w),
		.dbg_iwm_latch(dbg_iwm_latch_w),
		.dbg_flp_byte_stb(dbg_flp_byte_stb_w),
		.dbg_flp_raw(dbg_flp_raw_w),

		// ---- Egret / VIA shift-register taps, for SignalTap --------------
		// These were left unconnected at import.
		//
		// ★ 2026-08-10: the CB1-coalescing theory these were wired up for is
		// REFUTED — do not spend a capture confirming it. CLAUDE.md and the
		// old comment here blamed ext_fall_edge_pending (a single-bit latch
		// consuming at most one CB1 edge per VIA E period) for corrupting the
		// Egret SR handshake. In this via6522.sv that register has NO
		// functional fanout at all: grep the repo and its only reader is the
		// sr_dbg_fall_pending debug port (via6522.sv:976). Upstream already
		// fixed the bug. In ext_clock_mode (ACR shift modes 3 and 7, which is
		// what the Egret uses) BOTH the data path (via6522.sv:865-879) and the
		// bit counter (via6522.sv:941-953) advance on the per-clk edge pulses
		// shift_tick_r / shift_tick_f, decoupled from E — see the comments
		// there, which name this exact failure mode as the thing they fix.
		// ext_edge_pending survives only via shift_pulse, and shift_pulse is
		// read solely inside !ext_clock_mode branches (lines 806, 927).
		//
		// So dbg_sr_fall_pending WILL show edges coalescing on hardware and it
		// means nothing — the flag is dead. Kept as taps because the rest of
		// the bundle (handshake_done, memoryOverlayOn, bit_cnt, shift_reg) is
		// still the right instrument for an Egret handshake question; only the
		// pending-flag interpretation was wrong.
		//
		// Note also that simulation cannot reproduce hardware startup timing:
		// dataController_top.sv:197/209 uses resetDelay 0x0200 under
		// SIMULATION vs 0xFFFFF (129 ms) on FPGA, and egret_wrapper.sv:232
		// uses ONESEC_PERIOD 8192 (~2 ms) vs 4000000 (~1 s). That, not "the
		// behavioural Egret drives CB1 slowly", is why boot-timing faults are
		// FPGA-only — the behavioural Egret is not even compiled in any more.
		.via_sr_dbg_bit_cnt(dbg_sr_bit_cnt),
		.via_sr_dbg_edge_pending(dbg_sr_edge_pending),
		.via_sr_dbg_fall_pending(dbg_sr_fall_pending),
		.via_sr_dbg_shift_reg(dbg_sr_shift_reg),
		.via_sr_dbg_active(dbg_sr_active),
		.via_sr_dbg_dir(dbg_sr_dir),
		.via_sr_dbg_cb1(dbg_sr_cb1),
		.via_sr_dbg_cb2(dbg_sr_cb2),
		.egret_dbg_running(dbg_eg_running),
		.egret_dbg_port_test_done(dbg_eg_port_test_done),
		.egret_dbg_handshake_done(dbg_eg_handshake_done),
		.egret_dbg_treq(dbg_eg_treq),
		.egret_dbg_tip(dbg_eg_tip),
		.egret_dbg_byteack(dbg_eg_byteack),
		.egret_dbg_reset_680x0(dbg_eg_reset_680x0),
		.egret_dbg_cpu_reset_out(dbg_eg_cpu_reset_out),
		.egret_dbg_hc05_pc(dbg_hc05_pc_w)
	);

	// ---- SignalTap capture bundle -----------------------------------------
	// A `preserve`d register so the Fitter cannot optimise these nodes away;
	// SignalTap taps dbg_boot_bus inside this instance.
	//
	// SAMPLING NOTE: clk_sys is 32.5 MHz, so a 1024-deep capture spans only
	// ~31 us — far shorter than the Egret handshake, which runs for
	// milliseconds. Capture with a STORAGE QUALIFIER (store only when
	// dbg_sr_active or on a change of dbg_sr_cb1) or the window will close
	// long before anything interesting happens.
	wire [2:0] dbg_sr_bit_cnt;
	wire       dbg_sr_edge_pending, dbg_sr_fall_pending;
	wire [7:0] dbg_sr_shift_reg;
	wire       dbg_sr_active, dbg_sr_dir, dbg_sr_cb1, dbg_sr_cb2;
	wire       dbg_eg_running, dbg_eg_port_test_done, dbg_eg_handshake_done;
	wire       dbg_eg_treq, dbg_eg_tip, dbg_eg_byteack;
	wire [15:0] dbg_hc05_pc_w;   // ★ buildAN: HC05 live PC
	wire       dbg_eg_reset_680x0, dbg_eg_cpu_reset_out;

	(* preserve *) reg [31:0] dbg_boot_bus;
	always @(posedge clk_sys) dbg_boot_bus <= {
		4'd0,
		memoryOverlayOn,          // [27] the documented failure: never clears
		n_reset,                  // [26]
		rom_loaded,               // [25]
		dbg_eg_cpu_reset_out,     // [24]
		dbg_eg_reset_680x0,       // [23]
		dbg_eg_byteack,           // [22]
		dbg_eg_tip,               // [21]
		dbg_eg_treq,              // [20]
		dbg_eg_handshake_done,    // [19] boot handshake completed?
		dbg_eg_port_test_done,    // [18]
		dbg_eg_running,           // [17]
		dbg_sr_cb2,               // [16]
		dbg_sr_cb1,               // [15] the edge that coalesces
		dbg_sr_dir,               // [14]
		dbg_sr_active,            // [13]
		dbg_sr_fall_pending,      // [12] the suspect latch
		dbg_sr_edge_pending,      // [11]
		dbg_sr_shift_reg,         // [10:3]
		dbg_sr_bit_cnt            // [2:0]
	};

	//////////////////////// DOWNLOADING ///////////////////////////

	wire dio_download = ioctl_download;
	wire [23:0] dio_addr = ioctl_addr[24:1];
	wire [7:0] dio_index = ioctl_index;
	// mirror of MacLC.sv: Main packs the matched extension into the upper
	// ioctl_index bits — compare only the MENU index (see MacLC.sv rationale)
	wire [5:0] dio_menu = dio_index[5:0];

	// Floppy disk image tracking
	// POCKET CUT: single drive -- the dsk_ext_* twins are gone.
	reg dsk_int_ds;
	reg dsk_int_ss;
	reg dsk_int_mfm;  // MFM-format image (ISM path): 720K or 1.44MB
	reg dsk_int_hd;   // 1.44MB HD (vs 720K DD)
	// DiskCopy 4.2 header skip — mirror of MacLC.sv (rationale there).
	reg dc42_name_ok;
	reg dc42_skip;
	reg [7:0] dc42_disk_format;    // DC42 byte 0x50: 0/1/2/3 = 400G/800G/720M/1440M
	// Disk-change presentation — mirror of MacLC.sv (full rationale there): a
	// swap must reach the guest as eject THEN insert, because it only learns
	// about media by polling CSTIN. The sim mounts one image and never swaps,
	// so this only delays that mount; it is here to keep the two tops from
	// diverging (docs/verilator_differences.md).
	localparam [25:0] DSK_EMPTY_CY = 26'h3FFFFFF;
	reg [25:0] dsk_int_empty_cy;
	wire dsk_int_empty = (dsk_int_empty_cy != DSK_EMPTY_CY);
	wire dsk_int_ins = !dsk_int_empty && (dsk_int_ds || dsk_int_ss || dsk_int_mfm);

	always @(posedge clk_sys) begin
		reg old_down;
		old_down <= dio_download;
		if(~old_down && dio_download && dio_menu == 6'd1) begin
			dsk_int_ds  <= 0;
			dsk_int_ss  <= 0;
			dsk_int_mfm <= 0;
			dsk_int_hd  <= 0;
			dsk_int_empty_cy <= 26'd0;
		end
		else if(dio_download && dio_menu == 6'd1)
			dsk_int_empty_cy <= 26'd0;
		else if(dsk_int_empty_cy != DSK_EMPTY_CY)
			dsk_int_empty_cy <= dsk_int_empty_cy + 26'd1;

		if(old_down && ~dio_download && dio_menu == 6'd1) begin
			dsk_int_ds <= (dio_addr == 409600) ||
			              (dc42_skip && (dio_addr == 409642 || dio_addr == 419242));
			dsk_int_ss <= (dio_addr == 204800) ||
			              (dc42_skip && (dio_addr == 204842 || dio_addr == 209642));
			dsk_int_mfm <= (dio_addr == 368640) || (dio_addr == 737280) ||
			               (dc42_skip && (dc42_disk_format == 8'd2 || dc42_disk_format == 8'd3));
			dsk_int_hd  <= (dio_addr == 737280) ||
			               (dc42_skip && dc42_disk_format == 8'd3);
			$display("SIM: floppy0 download end dio_addr(words)=%0d dc42=%b fmt=%02x -> ds=%b ss=%b mfm=%b hd=%b",
			         dio_addr, dc42_skip, dc42_disk_format,
			         (dio_addr == 409600) || (dc42_skip && (dio_addr == 409642 || dio_addr == 419242)),
			         (dio_addr == 204800) || (dc42_skip && (dio_addr == 204842 || dio_addr == 209642)),
			         (dio_addr == 368640) || (dio_addr == 737280) || (dc42_skip && (dc42_disk_format == 8'd2 || dc42_disk_format == 8'd3)),
			         (dio_addr == 737280) || (dc42_skip && dc42_disk_format == 8'd3));
		end
		if(diskEject) begin
			dsk_int_ds <= 0;
			dsk_int_ss <= 0;
			dsk_int_mfm <= 0;
			dsk_int_hd <= 0;
		end
	end

	// POCKET CUT: the external drive's media-state block (download-size
	// sniffing for 400K/800K/720K/1.44M, the DC42 header cases and the
	// empty-hold timer) is deleted with the drive itself.

	// Download addresses (SDRAM word addresses):
	//   ROM:      $500000 + offset
	//   Floppy:   $600000 + offset
	// POCKET CUT: the $700000 second-floppy region is unused now.
	reg [22:0] dio_a;
	reg [15:0] dio_data;
	reg        dio_just_retired = 1'b0;

	// Download request into the SDRAM controller's dedicated port (Phase C —
	// see the root-cause note on the dl_* port in pocket_sdram.v). One word
	// per dioBusControl slot (the pre-Phase-C rate); dl_ack, not the slot
	// edge, releases the loader. Declared here because the handshake below
	// consumes sdram_dl_ack.
	wire       sdram_dl_ack;

	// DC42 write offset: active from the word after the magic (word 41)
	wire [19:0] dio_flp_a = dc42_skip ? (dio_addr[19:0] - 20'd42) : dio_addr[19:0];

	always @(posedge clk_sys) begin
		// ★★ ONE-SHOT ACCEPT (buildT, 2026-08-12) — the second half of the
		// row-crossing-tear fix. ioctl_wr is a LEVEL the loader holds until
		// core_top's ack (an EDGE detect on ioctl_wait's fall). Accepting on
		// the raw level re-asserted ioctl_wait in the one cycle between the
		// retire and the loader dropping ioctl_wr — leaving ioctl_wait STUCK
		// HIGH with no word pending. That fed dio_write ghost slots (writes
		// belonging to no word), and when the next word arrived MID-ghost-slot
		// dio_a re-latched mid-access: the residual 5.4% row-boundary tear
		// buildS measured (55 words, all xx00, all = content(X+0x100)). Ghost
		// slot-ends also pulsed spurious acks that could retire a word
		// UNWRITTEN (masked because every reload rewrites the same file).
		// Accept exactly once per word — only with no word pending and not in
		// the one-cycle post-retire shadow — and ioctl_wait becomes honest:
		// no ghost slots, no spurious acks, and dio_a cannot change while a
		// word is in flight. MiSTer never needed this because HPS ioctl_wr
		// was a one-cycle strobe, not a held level.
		// ★ Phase C re-key (2026-08-19): the retire event is now the SDRAM
		// controller's own dl_ack (see below), so the shadow keys on that;
		// !sdram_dl_ack additionally blocks re-accepting a new word until the
		// previous ack has fully drained (dl_ack is a LEVEL held until the
		// controller samples dl_req low — ~2 clk_sys after the clear; the
		// loader is far slower, so this can never deadlock).
		if(ioctl_wr && !ioctl_wait && !dio_just_retired && !sdram_dl_ack) begin
			if (dio_index[1:0] != 2'b00) begin
				// accept either byte lane order for the sim stream
				if (dio_addr[19:0] == 20'd0) begin
					dc42_skip    <= 1'b0;
					dc42_name_ok <= ((ioctl_dout[7:0]  >= 8'd1) && (ioctl_dout[7:0]  <= 8'd63)) ||
					                ((ioctl_dout[15:8] >= 8'd1) && (ioctl_dout[15:8] <= 8'd63));
				end else if (dio_addr[19:0] == 20'd40)
					dc42_disk_format <= ioctl_dout[7:0];  // byte 0x50 (low byte of word 40)
				else if (dio_addr[19:0] == 20'd41 && dc42_name_ok &&
				             (ioctl_dout == 16'h0001 || ioctl_dout == 16'h0100))
					dc42_skip <= 1'b1;
			end
			// Don't byte-swap for sim_ram (original swaps for SDRAM byte ordering)
			dio_data <= ioctl_dout;
			case (dio_index[1:0])
				2'b01:   dio_a <= 23'h600000 + {3'b0, dio_flp_a};  // Floppy
				default: dio_a <= {5'b10100, dio_addr[17:0]};      // ROM at $500000 (must match addrController rom_sdram_word)
			endcase
			ioctl_wait <= 1;
		end

		// ★ Release the loader on the SDRAM controller's OWN acknowledgement
		// (dl_ack), not on the bus-slot edge. The old edge protocol assumed
		// the write had certainly been issued by the time the slot ended;
		// under demand-start the sequencer can still be busy with a CPU
		// access, and a word that missed its slot would be silently dropped
		// from the image. dl_ack is a level (clk_64 is 2x clk_sys — a
		// one-tick pulse is not sampleable), so this is a clean two-phase
		// handshake: ioctl_wait 0->1 requests, dl_ack 0->1 acknowledges, and
		// the word simply waits for the next window if this one was taken.
		// ★ The hold-during-init property is preserved: while the init ladder
		// runs, pocket_sdram holds dl_ack at 0, so ioctl_wait stays up and
		// the loader's 512-word FIFO absorbs the ~126 us wait — nothing is
		// lost, the words land once memory is live.
		dio_just_retired <= (sdram_dl_ack && ioctl_wait);
		if (sdram_dl_ack) ioctl_wait <= 0;
	end

	// ---- Boot forensics: words actually RETIRED into SDRAM ------------------
	// Counts the FALLING EDGE of ioctl_wr. ioctl_wr is a LEVEL held by the
	// loader until its dio_ack arrives, so its fall is exactly one event per
	// word retired.
	//
	// ★ The first version of this counter tested the ioctl_wait clear term
	//   (dio_old_cyc & ~dioBusControl & dio_write & ioctl_wait) instead, and
	//   over-counted: because ioctl_wr is a level, the `if(ioctl_wr)` block
	//   above RE-ASSERTS ioctl_wait every cycle the strobe is held, so a word
	//   whose ack is slow can satisfy the clear term on more than one bus
	//   slot. It read 365,194 for a 262,144-word ROM (1.39x) on the first
	//   hardware capture. Counting an edge of the strobe itself is immune.
	//
	// Split by destination because dio_index[1:0]==01 is the floppy window.
	// A 512 KB ROM = 262,144 words = 0x40000. Free-running, never cleared:
	// read the DELTA across a load. Compare against the loader's
	// dbg_bridge_words / dbg_pop_words to localise where words are lost.
	reg [31:0] dbg_rom_words = 32'd0;
	reg [31:0] dbg_flp_words = 32'd0;
	reg        dbg_iwr_d     = 1'b0;

	// ---- ROM CONTENT verification -----------------------------------------
	// ★ The word COUNTS above prove only that the right NUMBER of words moved.
	// They would look perfect for a ROM that arrived scrambled, duplicated, or
	// written to the wrong addresses. These two accumulators check the content
	// itself, and the host side can compute the same values from boot0.rom:
	//
	//   rom_sum    = sum of every data word            -> expect 0x350F8EEE
	//   rom_axsum  = sum of (word_index ^ data)        -> expect 0xF486F3D8
	//
	// rom_sum alone is order-insensitive, so a permuted ROM would still match.
	// Folding the word INDEX in makes rom_axsum sensitive to which address
	// each word landed at -- that is the check that catches an addressing bug,
	// which is by far the more likely failure for a download path.
	// (The ROM file's own embedded checksum verifies independently:
	//  stored 0x350EACF0 == computed 0x350EACF0, so the source is good.)
	reg [31:0] rom_sum   = 32'd0;
	reg [31:0] rom_axsum = 32'd0;
	wire [31:0] rom_widx = {14'd0, dio_a[17:0]};   // word index within the file
	wire [31:0] rom_dat  = {16'd0, dio_data};

	always @(posedge clk_sys) begin
		dbg_iwr_d <= ioctl_wr;
		if (dbg_iwr_d & ~ioctl_wr) begin
			if (dio_index[1:0] == 2'b01) dbg_flp_words <= dbg_flp_words + 32'd1;
			else begin
				dbg_rom_words <= dbg_rom_words + 32'd1;
				rom_sum       <= rom_sum   + rom_dat;
				rom_axsum     <= rom_axsum + (rom_widx ^ rom_dat);
			end
		end
	end

	////////////////////////// RAM /////////////////////////////////

	// ★★★ 2026-08-19 — the `download_cycle` MUX IS GONE (Phase C port from
	// MiSTer cpu-icache). It used to steal the CPU's addr/din/ds/we/oe nets
	// for the dioBusControl slot; see the long root-cause note on the dl_*
	// port in pocket_sdram.v. Downloads now reach the controller through
	// their own request, so a mount can no longer hijack a CPU access (or
	// its DTACK) mid-flight. The window is still exactly one word per
	// dioBusControl slot, so the download rate and the CPU/download
	// bandwidth split are unchanged.
	//
	// The two hard-won Pocket properties of the OLD path are PRESERVED by
	// construction in the new one (do not weaken either):
	//   * ROW-CROSSING TEAR (buildR/buildS, 2026-08-12): the download
	//     address/data must never change while an SDRAM access is in flight.
	//     The dl_* port uses the LATCHED dio_a/dio_data, and pocket_sdram
	//     additionally freezes them into its own registers at ACTIVE
	//     (din_q/ds_q/col_q) — a delayed access cannot see its inputs move.
	//   * GHOST SLOTS (buildT): the one-shot accept above still admits
	//     exactly one word per ioctl_wait cycle, and the dl_served marker in
	//     pocket_sdram issues at most one write per request level — no
	//     spurious re-writes, no phantom acks. (The full tear/ghost history
	//     is in git at 9a2d50d/f21fd75.)

	// SDRAM word address mapping:
	// memoryAddr[22:0] is already the SDRAM word address from addrController
	// Download path uses the LATCHED dio_a[22:0] (set when ioctl_wr arrived).
	// ---- ROM RETENTION VERIFIER: RETIRED (2026-08-19, Phase C port) -------
	// The ROMV v4 oracle (JTAG-fed SDRAM range scanner, 2026-08-12..13) is
	// deleted with this port: JTAG bring-up is retired, its romv_src lever
	// was permanently tied 0, and its protocol (free-running oe paired with
	// dout_stb completion toggles) is structurally meaningless under the
	// demand engine, where CPU-class reads complete via cpu_done/cpu_dout.
	// It also muxed into the CPU's own request nets — exactly the shared-mux
	// class Phase C exists to eliminate. Recover from git history (buildAC
	// era, scripts/romv*.tcl) if a memory-content oracle is ever needed
	// again; under the demand engine it would need its own request port,
	// like the download's dl_*.

	// The CPU's SDRAM request — a pure LEVEL, held while AS is low (Phase C).
	// No download leg (dl_* port), no romv leg (retired), and oe carries NO
	// floppy term: floppy intent travels ONLY via flp_win. Including
	// dskReadAckInt here (as the slot machine needed) let a pending floppy
	// window bridge the 2-3 tick AS-high gap between CPU cycles, holding oe
	// high so cpu_done never cleared: the next read then instant-acked on
	// the HELD done and latched the PREVIOUS access's cpu_dout without ever
	// touching SDRAM (stale-read class), and writes lost their done-RISE
	// (vram_we strobes silently dropped) — the MiSTer magenta-screen hunt of
	// 2026-08-17.
	// ★ A cache hit never starts an SDRAM transaction (Law 7): the
	// suppression verdict is a per-access snapshot from fetch_cache (same
	// edge the hit registers, held for the access), so ram_oe_q sees a
	// stable gate — never a mid-transaction drop. Without this every hit
	// ABANDONED its demand transaction and the next access stalled behind
	// the phantom: on MiSTer, Speedometer showed the software-FP tests 4-6%
	// BELOW cache-off while tight loops gained — the stall tax.
	// pocket_sdram's done-birth guard (`&& oe`) remains as the safety net.
	wire [24:0] ram_addr = {2'b00, memoryAddr[22:0]};
	wire [15:0] ram_din  = memoryDataOut;
	wire  [1:0] ram_ds   = { !_memoryUDS, !_memoryLDS };
	wire        ram_we   = !_ramWE;
	wire        ram_oe   = (!_ramOE || !_romOE) && !icache_hit_now;
	// Phase C: CPU reads come from the controller's held cpu_dout register
	// (captured once per demand access), not the shared slot-domain dout —
	// floppy windows can no longer clobber CPU read data, and the value
	// stays valid through the CPU FSM's late din_r latch.
	// (The old `download_cycle ? 16'hffff` term is removed with the mux —
	// video no longer reads SDRAM at all (BRAM framebuffer), and forcing
	// $FFFF here corrupted any CPU read sampled inside a download slot.)
	// ★ The floppy leg is GONE from this mux — it now reaches dataController
	// on its own dskReadDataIn wire. This net is the memory leg of
	// cpuDataOut, so swapping it to the floppy byte for the duration of
	// every fetch window would hand the CPU floppy data whenever a window
	// landed inside a (no-longer-slot-aligned) demand access.
	// (FORCED-WARM BOOT patch: retired buildU 2026-08-12 and stays retired —
	// the honest branch runs on clean code; see git history if ever needed.)
	wire [15:0] sdram_cpu_dout;
	wire        sdram_cpu_done;
	wire [15:0] ram_do = sdram_cpu_dout;
	// Disk byte-parity select: must be dskReadAddr[0], NOT memoryAddr[0] (which
	// is dskReadAddr[1] after the >>1 word conversion drops bit 0). See the long
	// note at the matching demux in MacLC.sv — the old bit selected the wrong
	// byte on odd addresses and corrupted every floppy sector.
	// Phase C: select with the parity REGISTERED alongside the request
	// bundle, so it matches the address the access was actually issued with
	// (the live signal is one tick ahead of the registered window now). The
	// demux source is the controller's `dout` — the floppy-window data
	// register, which CPU traffic never touches.
	wire dsk_byte_odd = dskReadAddrInt[0];
	reg  ram_dskodd_q;
	always @(posedge clk_sys) ram_dskodd_q <= dsk_byte_odd;
	wire [15:0] ram_flp_do;
	wire [15:0] extra_rom_data_demux = ram_dskodd_q ?
						   {ram_flp_do[7:0],ram_flp_do[7:0]}:{ram_flp_do[15:8],ram_flp_do[15:8]};

	// ── Phase C fix (ported from MiSTer 2026-08-18): pipeline the SDRAM
	// request in clk_sys ─────────────────────────────────────────────────────
	// STA on the MiSTer post-fit netlist measured the clk_sys->clk_mem
	// request paths at **-6.710 ns** with a 15.381 ns window: the V8
	// address-translation cone (tg68k|addr -> SIMM compare / mirror subtract
	// / mux -> sd_addr) needs ~22 ns, but a clk_64 capture edge gives it only
	// ONE clk_64 period. The demand sequencer was therefore latching a
	// HALF-SETTLED ROW/COLUMN ADDRESS — reads and writes landing at the wrong
	// location (the "System Update" F-line bomb of 2026-08-17). A multicycle
	// "fixed" this on paper by granting 2 destination periods the silicon
	// never had; the fix must be structural. One clk_sys register stage on
	// the whole request bundle:
	//   * the deep translation cone now terminates at a clk_sys flop and gets
	//     a full 30.76 ns period (22 ns needed -> genuine positive slack);
	//   * the sequencer captures from an adjacent register, a short route
	//     that closes inside one clk_64 period with room to spare.
	// Cost is one clk_sys tick of request latency per access.
	// The bundle registers together (including flp_guard) so the floppy
	// window stays coherent with the address it is muxing — floppy.v latches
	// its fetch a full clk8 period later, which absorbs the shift.
	// ★ flp_win and flp_addr are passed LIVE, deliberately — see the flp_addr
	// port note in pocket_sdram.v: the window IS slot-aligned by construction
	// and delaying the floppy address by the pipeline tick delivers the
	// PREVIOUS byte to the encoder.
	// ★ DO NOT add an SDC multicycle to "help" these paths — that is the
	// exact trap the registration replaces (see core_constraints.sdc).
	reg [24:0] ram_addr_q;
	reg [15:0] ram_din_q;
	reg  [1:0] ram_ds_q;
	reg        ram_we_q, ram_oe_q;
	reg        ram_flpguard_q;
	reg        ram_dlreq_q, ram_dlslot_q;
	reg [23:0] ram_dladdr_q;
	reg [15:0] ram_dldin_q;
	always @(posedge clk_sys) begin
		ram_addr_q     <= ram_addr;
		ram_din_q      <= ram_din;
		ram_ds_q       <= ram_ds;
		ram_we_q       <= ram_we;
		ram_oe_q       <= ram_oe;
		ram_flpguard_q <= flp_guard && !dio_download;
		ram_dlreq_q    <= ioctl_wait;
		ram_dlslot_q   <= dioBusControl;
		ram_dladdr_q   <= {1'b0, dio_a[22:0]};
		ram_dldin_q    <= dio_data;
	end

	// ------------------------------------------------------------------
	// SDRAM — the Phase-C demand-start controller (see pocket_sdram.v).
	// ------------------------------------------------------------------
	// The .init policy is load-bearing and was got wrong twice on MiSTer
	// (reverted d88c098 / 50d0c32): anything tied here that is ALSO asserted
	// during the ROM download swallows the download writes and breaks cold
	// boot. Hence exactly two terms — power-on !pll_locked, and the
	// edge-triggered user-reset pulse below, which is explicitly suppressed
	// while dio_download is active.
	pocket_sdram sdram
	(
		.init           ( !pll_locked || sdram_reinit ),
		.clk_64         ( clk_mem     ),
		.clk_8          ( clk8        ),
		.sd_data        ( sdram_dq    ),
		.sd_addr        ( sdram_a     ),
		.sd_dqm         ( sdram_dqm   ),
		.sd_ba          ( sdram_ba    ),
		.sd_cke         ( sdram_cke   ),
		.sd_we          ( sdram_we_n  ),
		.sd_ras         ( sdram_ras_n ),
		.sd_cas         ( sdram_cas_n ),

		// cpu/chipset interface — the clk_sys-REGISTERED request bundle (see
		// the pipeline note above; feeding the combinational nets here is
		// what broke the 2026-08-17 MiSTer build).
		.din            ( ram_din_q   ),
		.addr           ( ram_addr_q[23:0] ),
		.ds             ( ram_ds_q    ),
		.we             ( ram_we_q    ),
		.oe             ( ram_oe_q    ),
		.dout           ( ram_flp_do  ),

		// Phase C demand-start service.
		// !dio_download on the window terms (matching addrController's
		// at-source gate): during a download, dio writes are only PRESENTED
		// during dioBusControl ticks — the very ticks floppy windows claim —
		// and the guard zone covers them, so a pending floppy fetch would
		// deadlock the loader (ioctl_wait never clears). Floppy pending
		// state persists and is served after the download.
		// flp_win/flp_addr LIVE, flp_guard registered — see the pipeline
		// note above.
		.flp_win        ( dskReadAckInt && !dio_download ),
		.flp_addr       ( ram_addr[23:0] ),
		.flp_guard      ( ram_flpguard_q ),

		// download port (see the root-cause note in pocket_sdram.v)
		.dl_req         ( ram_dlreq_q  ),
		.dl_slot        ( ram_dlslot_q ),
		.dl_addr        ( ram_dladdr_q ),
		.dl_din         ( ram_dldin_q  ),
		.dl_ack         ( sdram_dl_ack ),

		.cpu_done       ( sdram_cpu_done ),
		.cpu_dout       ( sdram_cpu_dout )
	);

	// Dedicated SDRAM re-init pulse on explicit user resets only.
	// Structurally different from the reverted attempts above: edge-triggered
	// (never a level held through a download), fires only once the ROM is
	// already in SDRAM, and suppressed while any download is active. The init
	// ladder is content-preserving (NOPs + refreshes + MRS, ~126 us) and
	// n_reset's stretch holds the CPU long past its completion.
	reg  [3:0] sdram_reinit_cnt = 4'd0;
	reg        user_reset_d = 1'b0;
	wire       user_reset_now = reset;   // host-commanded reset (core_top)
	always @(posedge clk_sys) begin
		user_reset_d <= user_reset_now;
		if (user_reset_now && !user_reset_d && rom_loaded && !dio_download)
			sdram_reinit_cnt <= 4'd15;
		else if (sdram_reinit_cnt != 0)
			sdram_reinit_cnt <= sdram_reinit_cnt - 4'd1;
	end
	wire sdram_reinit = (sdram_reinit_cnt != 0);

	// RAM debug outputs
	assign debug_ram_addr = ram_addr;
	assign debug_ram_din = ram_din;
	assign debug_ram_dout = sdram_cpu_dout;
	assign debug_ram_we = ram_we;
	assign debug_ram_oe = ram_oe;
	assign debug_ram_ds = ram_ds;
	assign debug_selectRAM = selectRAM;
	assign debug_selectROM = selectROM;

	// Peripheral debug outputs
	assign debug_selectVIA = selectVIA;
	assign debug_selectAriel = selectAriel;
	assign debug_selectPseudoVIA = selectPseudoVIA;
	assign debug_selectSCSI = selectSCSI;
	assign debug_selectSCC = selectSCC;
	assign debug_selectIWM = selectIWM;
	assign debug_selectASC = selectASC;
	assign debug_selectVRAM = selectVRAM;
`ifdef SIMULATION
	// Track RAM test progress: log CPU data address during RAM writes
	// Samples periodically to avoid flooding output
	integer ram_wr_count = 0;
	reg [23:0] last_ram_wr_addr = 0;
	always @(posedge clk_sys) begin
		if (selectPseudoVIA && selectVRAM)
			$display("[F%0d] BUG: selectPseudoVIA AND selectVRAM both active! addr=%h", sim_frame_count, cpuAddr);
		if (selectPseudoVIA && !_cpuRW && cpuBusControl)
			$display("[F%0d] PVIA ACTIVE WRITE: cpuAddr=%h data=%h", sim_frame_count, cpuAddr, cpuDataOut);

		// Log RAM writes: first 10, then every 100000th
		if (!_ramWE && cpuBusControl) begin
			if (ram_wr_count < 10 || ram_wr_count % 100000 == 0) begin
				$display("[F%0d] RAM_WR[%0d]: cpuAddr=%h sdramAddr=%h data=%h PC=%h",
					sim_frame_count, ram_wr_count, cpuAddr, memoryAddr, cpuDataOut, last_fetch_pc);
			end
			last_ram_wr_addr <= cpuAddr;
			ram_wr_count <= ram_wr_count + 1;
		end

		// Log RAM reads: every 100000th
		if (!_ramOE && cpuBusControl) begin
			if (ram_wr_count > 0 && ram_wr_count % 100000 == 50000) begin
				$display("[F%0d] RAM_RD: cpuAddr=%h sdramAddr=%h PC=%h",
					sim_frame_count, cpuAddr, memoryAddr, last_fetch_pc);
			end
		end
	end
`endif
	assign debug_cpuAddr = cpuAddr;
	assign debug_cpuDataIn = cpuDataOut;  // CPU writes this to peripherals
	assign debug_cpuDataOut = dataControllerDataOut;  // Peripherals send this to CPU
	assign debug_cpuRW = _cpuRW;  // 1=read, 0=write
	assign debug_cpuBusControl = cpuBusControl;
	assign debug_cpu_as = _cpuAS;
	assign debug_cpu_dtack = _cpuDTACK;

	// ========================================================================
	// JTAG In-System probes — the cold-boot forensics deck
	// ========================================================================
	// DEBUG BUILDS ONLY. Enable with USE_BOOT_ISSP in src/fpga/ap_core.qsf;
	// it MUST be off for a release fit (see the USE_DBG_HUD precedent in
	// CLAUDE.md). Read them with: bash scripts/read_boot_probes.sh
	//
	// FPGA-only — altsource_probe is an Altera primitive, so this block must
	// never be compiled into verilator/sim.v.
	//
	// Why ISSP and not SignalTap: the question here is "how far did the boot
	// get", which is a LEVEL question about signals that change a handful of
	// times over ~137 ms. SignalTap's 1024 samples at 32.5 MHz span 31 us and
	// would close long before anything happened. ISSP is read from a Tcl
	// script over seconds, has no depth limit, costs almost nothing, and can
	// be sampled repeatedly while the user power-cycles the machine.
	//
	//   BOOT  dbg_boot_bus — [27] memoryOverlayOn [26] n_reset [25] rom_loaded
	//                        [19] egret handshake_done, [24:17] egret state,
	//                        [16:11] VIA SR pins, [10:3] SR byte, [2:0] bit_cnt
	//   ROMC  words retired into SDRAM at the ROM window (expect 0x40000 for
	//         a 512 KB ROM). THE decisive number for "did the ROM land".
	//   FLPC  words retired into the floppy window.
	// ---- Video liveness ----------------------------------------------------
	// Separates "video is held in reset" from "video is scanning but the guest
	// has not drawn anything yet" -- a black screen looks identical either way
	// from outside, and the vidrst_s change on 2026-08-11 introduced a NEW way
	// to get the first case: vidrst_s is a clk_pix-domain register that powers
	// up ASSERTED, so if clk_pix ever fails to run, video never leaves reset.
	//
	// vid_frames counts vsync rising edges in the clk_pix domain. If it is
	// advancing, the timing generator is alive and clk_pix is running, and a
	// black screen is the guest's fault, not ours. If it is pinned at 0, the
	// video module is dead -- check vidrst_s and clk_pix first.
	reg [27:0] vid_frames = 28'd0;
	reg        vsync_d    = 1'b0;
	always @(posedge clk_pix) begin
		vsync_d <= v8_vsync;
		if (~vsync_d & v8_vsync) vid_frames <= vid_frames + 28'd1;
	end
	wire [31:0] dbg_vid_state = {
		vidrst_s,      // [31] 1 = video module held in reset
		v8_vblank,     // [30] raw, clk_pix domain
		v8_hblank,     // [29]
		v8_de,         // [28] display enable
		vid_frames     // [27:0] vsync count -- MUST be advancing
	};

	// ---- Interrupt-storm forensics ----------------------------------------
	// 2026-08-11: with SDMA_TIMEOUT shortened the machine runs ~3000x faster
	// and leaves the SCSI stall, but 359/400 sampled bus cycles land in the
	// exception vector table at $0000xx with live IACK cycles at $FFxxxx --
	// the CPU takes an interrupt, returns, and takes it again for ever, so
	// POST never advances and the overlay never clears.
	//
	// _cpuIPL_dc names the winner directly (dataController_top.sv:293):
	//   3'b011 = level 4 SCC   3'b101 = level 2 PseudoVIA
	//   3'b110 = level 1 VIA1  3'b111 = none
	// MiSTer's POST notes document this exact class: a continuously asserted
	// level-2 from pseudovia (ASC folded into slot_status) preempting the
	// level-1 the VIA1 timer self-test waits on. iack_cnt gives the storm RATE
	// so a genuine periodic tick is distinguishable from a stuck level.
	reg [23:0] iack_cnt = 24'd0;
	reg        iack_d   = 1'b0;
	always @(posedge clk_sys) begin
		iack_d <= fc7_iack;
		if (fc7_iack && !iack_d) iack_cnt <= iack_cnt + 24'd1;
	end

	// ---- SCC TX capture (2026-08-12) --------------------------------------
	// Latch every CPU write into the SCC window ($F040xx): count + rolling
	// 3-byte window. Pairs with the STM console injector — commands echoed and
	// answered by the monitor land here. See scripts/read_scc.tcl.
	// ★ v2: capture BOTH directions with address tags. Entry format (12 bits):
	//   [11]   1 = CPU read, 0 = CPU write
	//   [10:9] cpuAddr[2:1]: 0=ctl-B 1=ctl-A 2=data-B 3=data-A
	//   [7:0]  the byte (write: CPU data out; read: periph_din_reg upper lane —
	//          SCC sits on the upper byte on the LC)
	reg [7:0]  scc_wr_cnt  = 8'd0;
	reg [23:0] scc_last3   = 24'd0;
	reg        scc_wr_pend = 1'b0;
	reg [11:0] scc_wr_ent  = 12'd0;
	always @(posedge clk_sys) begin
		if (!_cpuAS && (cpuAddr[23:8] == 16'hF040)) begin
			scc_wr_pend <= 1'b1;
			if (_cpuRW)
				scc_wr_ent <= { 1'b1, cpuAddr[2:1], 1'b0, periph_din_reg[15:8] };
			else
				scc_wr_ent <= { 1'b0, cpuAddr[2:1], 1'b0,
				                !_cpuUDS ? cpuDataOut[15:8] : cpuDataOut[7:0] };
		end else if (scc_wr_pend) begin
			scc_wr_pend <= 1'b0;
			// Filter the STM spin's idle poll (read ctl-A returning RR0=0x04,
			// tens of kHz) — it floods the 256-deep ring within a second and
			// erases every interesting event. RR0 reading anything ELSE
			// (e.g. 0x05 = char available) still records.
			if (scc_wr_ent != 12'hA04) begin
				scc_wr_cnt  <= scc_wr_cnt + 8'd1;
				scc_last3   <= { scc_last3[15:0], scc_wr_ent[7:0] };
				scc_ring[scc_wr_cnt] <= scc_wr_ent;
			end
		end
	end
	wire [31:0] dbg_scc_tx = { scc_wr_cnt, scc_last3 };

	// Full-history ring: last 256 SCC writes, read back deterministically over
	// JTAG via a source-selected index (see scripts/stm_console.tcl). This is
	// what makes the STM console conversational — complete responses, not a
	// 3-byte tail.
	reg [11:0] scc_ring [0:255];
	wire [7:0] scc_rd_idx;
	reg  [11:0] scc_ring_q = 12'd0;
	always @(posedge clk_sys) scc_ring_q <= scc_ring[scc_rd_idx];

	wire [31:0] dbg_irq_state = {
		_cpuIPL_dc,      // [31:29] raw IPL from dataController
		pseudovia_irq,   // [28] level-2 source
		asc_irq,         // [27] ASC (feeds pseudovia IFR bit 4)
		v8_vblank_s,     // [26] synced VBlank (feeds pseudovia vblank_irq)
		fc7_iack,        // [25] in an interrupt-acknowledge cycle right now
		memoryOverlayOn, // [24]
		iack_cnt         // [23:0] interrupts acknowledged — the storm rate
	};

	// ---- Pseudo-DMA stall forensics ---------------------------------------
	// 2026-08-11: the boot wedges with the CPU parked on a pseudo-DMA WRITE
	// (addr $F13EAE, AS asserted, DTACK never answering) and the 250 ms
	// sdma_berr timeout that exists to rescue exactly this NEVER FIRES --
	// even with every SCSI disk hidden from the machine, so it is not a
	// block-device problem.
	//
	// The measured state implies the timeout's own condition is satisfied
	// (selectSCSIDMA=1 from VPA being deasserted, scsiDREQ=0 from DTACK=1,
	// _cpuReset=1, and AS genuinely held low since the bus-cycle counter is
	// frozen). So either one of those inferences is wrong, or the counter is
	// being reset by something. This probe reads the actual terms instead of
	// inferring them.
	wire [31:0] dbg_sdma_state = {
		sdma_berr,        // [31] has the timeout fired?
		scsiDREQ,         // [30] the thing DTACK waits on
		selectSCSIDMA,    // [29] are we even decoding the pseudo-DMA window?
		selectSCSI,       // [28]
		_cpuReset,        // [27] 1 = CPU running
		_cpuAS,           // [26] 0 = asserted
		_cpuRW,           // [25]
		1'b0,             // [24]
		1'b0,             // [23]
		sdma_stall_ctr    // [22:0] MUST be climbing toward 8,125,000
	};

	// ---- CPU liveness ------------------------------------------------------
	// The boot bus carries only Egret/VIA/overlay state, so a frozen reading
	// there cannot distinguish a HALTED 68020 (double bus fault on a corrupt
	// ROM -- note CLAUDE.md: "bus retry via HALT is not implemented") from one
	// spinning in a polling loop that touches none of those signals. The
	// 2026-08-11 capture hit exactly that ambiguity: 40/40 identical samples.
	//
	// CPUC counts bus cycles (falling edge of _cpuAS). Sample it twice:
	//   delta == 0  -> the CPU is genuinely stopped (halted or held in reset)
	//   delta >  0  -> it is executing; CPUA then says WHERE, and a tight
	//                  address range is the poll loop we are deadlocked in.
	reg [31:0] dbg_cpu_cycles = 32'd0;
	reg        dbg_as_d       = 1'b1;
	always @(posedge clk_sys) begin
		dbg_as_d <= _cpuAS;
		if (dbg_as_d & ~_cpuAS) dbg_cpu_cycles <= dbg_cpu_cycles + 32'd1;
	end

	wire [31:0] dbg_cpu_state = {
		memoryOverlayOn,   // [31]
		_cpuRW,            // [30] 1 = read
		_cpuDTACK,         // [29] 0 = asserted
		_cpuAS,            // [28] 0 = asserted
		tg68_reset_n,      // [27] 0 = CPU held in reset
		_cpuReset,         // [26]
		cpu_berr,          // [25] bus error being driven
		_cpuVPA,           // [24]
		cpuAddr[23:0]      // [23:0]
	};

	// ---- JTAG BOOT STROBE (2026-08-12; hoisted out of the deck buildAZ) ----
	// Toggling the JBOOT source arms one full machine reset AND forces the
	// rom_loaded latch — the ROM persists in SDRAM across fabric pushes, so
	// this boots the machine entirely from the PC, no OSD interaction needed.
	// The machinery lives OUTSIDE the deck guard because jboot_rst and
	// jboot_loaded feed the always-on reset/rom_loaded logic (lines ~214/367);
	// keeping the declarations inside made a probe-less fit fail to
	// elaborate — never noticed before buildAZ because no probe-less build
	// had ever been attempted. With the probes absent the sources tie to 0
	// and all of this constant-folds away.
	wire       jboot_src;
	reg        jboot_d      = 1'b0;
	reg        jboot_loaded = 1'b0;   // ORed into the rom_loaded latch above
	reg [4:0]  jboot_hold   = 5'd0;   // ≥16 clk8 ticks: reset block samples clk8_en_p
	wire       jboot_rst    = (jboot_hold != 5'd0);
	always @(posedge clk_sys) begin
		jboot_d <= jboot_src;
		if (jboot_d != jboot_src) begin
			jboot_loaded <= 1'b1;
			jboot_hold   <= 5'd31;
		end else if (clk8_en_p && jboot_hold != 5'd0) begin
			jboot_hold <= jboot_hold - 5'd1;
		end
	end
	// DIAG source: level (not toggle) — 1 grounds VIA1 PA0 so the ROM enters
	// the STM diagnostic monitor at the next boot. Combine with JBOO for
	// STM-on-demand: set DIAG=1, strobe JBOO, converse, set DIAG=0.
	wire diag_src;
`ifndef USE_BOOT_ISSP
	// Probe-less fit: levers permanently released. stm_src is declared at
	// its engine above; without cp_stmc driving it it would float to GND
	// with a warning — tie it explicitly. (romv_src retired 2026-08-19 with
	// the ROMV engine — see the Phase-C note in the RAM section.)
	assign jboot_src = 1'b0;
	assign diag_src  = 1'b0;
	assign stm_src   = 9'd0;
`endif

`ifdef USE_BOOT_ISSP
	altsource_probe #(
		.instance_id ("BOOT"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_boot (.probe(dbg_boot_bus),  .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("CPUC"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_cpuc (.probe(dbg_cpu_cycles), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("CPUA"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_cpua (.probe(dbg_cpu_state),  .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("VIDS"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_vids (.probe(dbg_vid_state),  .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("SDMA"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_sdma (.probe(dbg_sdma_state), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("IRQS"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_irqs (.probe(dbg_irq_state),  .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("RSUM"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_rsum (.probe(rom_sum),        .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("RAXS"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_raxs (.probe(rom_axsum),      .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("SCCT"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_scct (.probe(dbg_scc_tx), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("STMC"), .probe_width (8), .source_width (9),
		.sld_auto_instance_index ("YES")
	) cp_stmc (.probe(stm_sent_cnt), .source(stm_src), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("SCCR"), .probe_width (20), .source_width (8),
		.sld_auto_instance_index ("YES")
	) cp_sccr (.probe({scc_wr_cnt, scc_ring_q}), .source(scc_rd_idx), .source_clk(clk_sys), .source_ena(1'b1));

	// [15:12] rx-delivered count  [11:8] frame-error count  [7:0] engine flags
	wire [15:0] dbg_scc_state;
	altsource_probe #(
		.instance_id ("SCCS"), .probe_width (16), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_sccs (.probe(dbg_scc_state), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("JBOO"), .probe_width (1), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_jboot (.probe(jboot_rst), .source(jboot_src), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("DIAG"), .probe_width (1), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_diag (.probe(diag_src), .source(diag_src), .source_clk(clk_sys), .source_ena(1'b1));

	// (cp_romv / cp_rvsu / cp_rvax removed 2026-08-19 with the ROMV engine.)

	altsource_probe #(
		.instance_id ("ROMC"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_romc (.probe(dbg_rom_words), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("FLPC"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_flpc (.probe(dbg_flp_words), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildZ2: what the CPU actually RECEIVES through the SCSI pseudo-DMA
	// window. The blockdev buffer is byte-perfect and the target serves it;
	// the ROM loads the 32-block driver and rejects it — this captures the
	// received words to split "corrupted on the CPU hop" from "driver fails
	// after clean load". A burst = beats separated by <2 ms (sector gaps are
	// OS-fetch ms-scale, so each sector is its own burst). SDW0 = words 0,1
	// of the LAST burst (a block-0 burst must read 4552 0200). SDCT =
	// {bursts[7:0], prev-burst beats[11:0], current-burst beats[11:0]}.
	reg [15:0] sdw0 = 16'd0, sdw1 = 16'd0;
	reg [11:0] sd_beats = 12'd0, sd_beats_prev = 12'd0;
	reg [7:0]  sd_bursts = 8'd0;
	reg [15:0] sd_idle = 16'hFFFF;
	reg        sd_beat_d = 1'b0;
	wire sd_beat = selectSCSIDMA && !_cpuAS && _cpuRW && !_cpuDTACK;
	always @(posedge clk_sys) begin
		sd_beat_d <= sd_beat;
		if (sd_beat && !sd_beat_d) begin
			if (sd_idle == 16'hFFFF) begin
				sd_beats_prev <= sd_beats;
				sd_beats      <= 12'd1;
				sd_bursts     <= sd_bursts + 8'd1;
				sdw0          <= dataControllerDataOut;
			end else begin
				if (sd_beats == 12'd1) sdw1 <= dataControllerDataOut;
				if (sd_beats != 12'hFFF) sd_beats <= sd_beats + 12'd1;
			end
			sd_idle <= 16'd0;
		end else if (sd_idle != 16'hFFFF) sd_idle <= sd_idle + 16'd1;
	end

	altsource_probe #(
		.instance_id ("SDW0"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_sdw0 (.probe({sdw0, sdw1}), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("SDCT"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_sdct (.probe({sd_bursts, sd_beats_prev, sd_beats}), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildAE SDCP: the ENTIRE last pseudo-DMA burst, beat by beat — the
	// full-sector version of SDW0's two words. 512x16 M10K; each burst
	// restarts the write pointer, so after a FRZE mid-retry-loop freeze the
	// RAM holds every beat of the final burst (byte-mode: beat k = byte k
	// duplicated on both halves; word-mode: beat k = word k). Read back by
	// index: write SDCP source = 0..511, read the 16-bit probe (registered,
	// JTAG pacing dwarfs the settle). Decoder: scripts/sdcp.tcl — dumps the
	// burst and diffs it against a master-image sector offline. Built to
	// catch the LBA-82 retry loop's payload as the CPU received it (served
	// face verified FFFC 4ED0; SDW0 saw 6060 0000 — this shows all 512
	// bytes and therefore the corruption PATTERN, which names the mechanism.
	(* ramstyle = "M10K" *) reg [15:0] sdcap [0:511];
	reg  [9:0] sdcap_w = 10'd0;
	wire [8:0] sdcap_rd_idx;
	reg [15:0] sdcap_q = 16'd0;
	always @(posedge clk_sys) begin
		if (sd_beat && !sd_beat_d) begin
			if (sd_idle == 16'hFFFF) begin
				sdcap[0] <= dataControllerDataOut;
				sdcap_w  <= 10'd1;
			end else if (!sdcap_w[9]) begin
				sdcap[sdcap_w[8:0]] <= dataControllerDataOut;
				sdcap_w <= sdcap_w + 10'd1;
			end
		end
		sdcap_q <= sdcap[sdcap_rd_idx];
	end

	altsource_probe #(
		.instance_id ("SDCP"), .probe_width (16), .source_width (9),
		.sld_auto_instance_index ("YES")
	) cp_sdcp (.probe(sdcap_q), .source(sdcap_rd_idx), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildAF PCRB: the DYING INSTRUCTION STREAM. A 64-deep ring of the
	// last distinct fetch PCs, frozen at the first n_reset FALL after being
	// armed — arm AFTER the boot is underway (jboot also drops n_reset), and
	// the ring freezes exactly at the crash reset holding the 64 PCs that
	// led to death. Every data face is verified byte-perfect (card, blockdev,
	// target, CPU receipt — SDCP 512/512 on the driver re-read) and the last
	// SCSI command completes with GOOD status + correct bytes; the machine
	// dies IN CODE right after. This names the code.
	// PCRB probe = ring[idx] (32-bit). PCRS probe = {frozen, write ptr}.
	// Decoder: scripts/pcrb.tcl; read PCs against docs/MacLC_ROM_disasm.txt
	// (ROM = 00A0xxxx) or RAM addresses (driver/System code).
	(* ramstyle = "M10K" *) reg [31:0] pcrb [0:63];
	reg  [5:0] pcrb_w = 6'd0;
	reg        pcrb_frozen = 1'b0;
	reg [31:0] pcrb_last = 32'hFFFFFFFF;
	reg        pcrb_nrst_d = 1'b1;
	reg        pcrb_arm_d  = 1'b0;
	reg [31:0] pcrb_q;
	// (buildAG's front-stub fetch trigger is gone: the crash restart is
	// `bra BootMe` deep in StartBoot.a — neither a reset nor a front-stub
	// fetch; buildAF/AG both proved it by never freezing.)
	// ★ buildAH: the crash is `bra BootMe` deep in StartBoot.a — no reset,
	// no front-stub fetch (buildAF/AG both missed). New trigger: ext_trig
	// (FRZE trigger-only mode) fires at the ROUND'S FINAL DELIVERY without
	// stopping the machine; the ring then keeps capturing for K more
	// DISTINCT PCs and freezes — landing the 64-entry window K PCs past the
	// final sector, inside the consume→check→decide path. K is a SOURCE
	// field: sweep it over re-arms (no rebuilds) until the dump shows the
	// decision code. K counts ring WRITES (loop iterations re-log PCs), so
	// think "instructions-ish", not unique addresses.
	//   PCRB source (★ buildAO, widened to 48 bits):
	//     [47]    arm (rising edge clears frozen, latches K + match)
	//     [46:38] K (x16 ring-writes of post-trigger countdown)
	//     [37:32] read index
	//     [23:0]  PC-match trigger address (0 = disabled). When set, a fetch
	//             of this PC starts the countdown (OR'd with ext_trig) — used
	//             to freeze at the ioResult-wait EXIT (A14882) or the wander
	//             entry, places the delivery-count trigger cannot reach.
	wire [47:0] pcrb_src;
	reg  [12:0] pcrb_k = 13'd0;      // countdown, in ring writes
	reg  [8:0]  pcrb_klat = 9'd0;    // K latched at arm (polls spray the source)
	reg  [23:0] pcrb_match = 24'd0;  // PC-match trigger, latched at arm
	reg         pcrb_stage2 = 1'b0;  // buildAP: delivery trigger stages the match
	reg         pcrb_trig_d = 1'b0, pcrb_armed_cnt = 1'b0;
	reg  [31:0] pcsn1 = 32'd0, pcsn2 = 32'd0;   // bus snapshot at window freeze
	reg  [31:0] egsn1 = 32'd0;                  // Egret/SR snapshot at freeze
	reg  [15:0] egsn3 = 16'd0;                  // HC05 PC at freeze (buildAN)
	// ★ buildAL live handshake counters (cleared at each PCRB arm): CB1
	// falling edges (the Egret's SR clock — what coalescing loses) vs
	// BYTEACK/TIP toggles (the per-byte protocol strobes). Which counter
	// stops first names the dying side of the stalled Egret transaction.
	reg  [11:0] eg_cb1_cnt = 12'd0;
	reg  [9:0]  eg_ba_cnt  = 10'd0;
	reg  [9:0]  eg_tip_cnt = 10'd0;
	reg         eg_cb1_d = 1'b0, eg_ba_d = 1'b0, eg_tip_d = 1'b0;
	always @(posedge clk_sys) begin
		pcrb_nrst_d <= n_reset;
		pcrb_arm_d  <= pcrb_src[47];
		pcrb_trig_d <= ext_trig;
		// ★ buildAM: WINDOW-SCOPED Egret counters — cleared at the ext_trig
		// edge, frozen with the ring. They measure exactly the death window
		// [trigger .. freeze]: cb1_falls=0 there means the Egret truly sent
		// no shift clocks (HC05/wrapper side); >0 with the SR bit counter
		// still parked means the VIA swallowed them (the documented
		// ext_fall_edge_pending coalescing). The whole-round free-run form
		// saturated into uselessness (4095/1023/1023).
		eg_cb1_d <= dbg_sr_cb1;
		eg_ba_d  <= dbg_eg_byteack;
		eg_tip_d <= dbg_eg_tip;
		if (!pcrb_frozen && pcrb_armed_cnt) begin
			if (eg_cb1_d && !dbg_sr_cb1 && eg_cb1_cnt != 12'hFFF) eg_cb1_cnt <= eg_cb1_cnt + 12'd1;
			if ((eg_ba_d  ^ dbg_eg_byteack) && eg_ba_cnt  != 10'h3FF) eg_ba_cnt  <= eg_ba_cnt  + 10'd1;
			if ((eg_tip_d ^ dbg_eg_tip)     && eg_tip_cnt != 10'h3FF) eg_tip_cnt <= eg_tip_cnt + 10'd1;
		end
		if (pcrb_src[47] && !pcrb_arm_d) begin
			pcrb_frozen    <= 1'b0;                    // re-arm: capture again
			pcrb_armed_cnt <= 1'b0;
			pcrb_klat      <= pcrb_src[46:38];         // K latched AT ARM —
			pcrb_match     <= pcrb_src[23:0];          // polls spray the
			                                           // source afterwards
			eg_cb1_cnt     <= 12'd0;
			eg_ba_cnt      <= 10'd0;
			eg_tip_cnt     <= 10'd0;
		end else if (pcrb_nrst_d && !n_reset)
			pcrb_frozen <= 1'b1;                       // hard reset: hold
		// ★ buildAK: the trigger edge RE-OPENS a frozen ring and starts the
		// countdown — a jboot's n_reset freeze between arm and trigger no
		// longer kills the capture, and the arm/jboot/trigger JTAG ordering
		// races are gone. One capture per arm (armed_cnt gates re-fire).
		// ★ buildAO: OR'd with the PC-match trigger (fetch of pcrb_match).
		// ★ buildAP: TWO-STAGE — when BOTH are armed, the delivery trigger
		// (ext_trig) STAGES the PC-match rather than firing the countdown:
		// the first pcrb_match fetch AFTER the round's final delivery is the
		// PRAM wait's own exit (A14882 is the generic async-I/O wait exit —
		// every disk read exits there too; post-delivery, only the PRAM
		// wait remains). No JTAG timing in the loop.
		if (ext_trig && !pcrb_trig_d && pcrb_match != 24'd0)
			pcrb_stage2 <= 1'b1;
		if (pcrb_src[47] && !pcrb_arm_d)
			pcrb_stage2 <= 1'b0;
		// Rule: match==0 -> delivery trigger fires directly. match!=0 -> the
		// match fires only once STAGED by the delivery trigger (for a
		// standalone PC-match, arm FRZE trig at an already-passed count —
		// it stages immediately).
		if (((ext_trig && !pcrb_trig_d && pcrb_match == 24'd0) ||
		     (pcrb_match != 24'd0 && pcrb_stage2 &&
		      fetch_valid && last_fetch_pc[23:0] == pcrb_match)) && !pcrb_armed_cnt) begin
			pcrb_k         <= {pcrb_klat, 4'd0};      // K x16 writes to go
			pcrb_armed_cnt <= 1'b1;
			pcrb_frozen    <= 1'b0;
			eg_cb1_cnt     <= 12'd0;                  // window-scope: zero at
			eg_ba_cnt      <= 10'd0;                  // the trigger
			eg_tip_cnt     <= 10'd0;
		end
		// ★ buildAQ: SPIN-LOOP FILTER — the wait-for-BSY loop (A07860-7F)
		// and the ioResult wait (A14870-83) flood the 64-deep ring in
		// microseconds; suppressing them makes 64 entries span the whole
		// seconds-wide death corridor as a call TRAIL (callers, error
		// paths, the give-up decision), not a spin close-up.
		// Suppressed windows: [A07840..A0787F] (TimeDBRA delay + wait-for-
		// BSY) via pc[23:6]==18'h281E1; [A14870..A1487F] via pc[23:4]==
		// 20'hA1487; [A14880..A14883] (the exit) via pc[23:2]==22'h285220.
		if (!pcrb_frozen && fetch_valid && last_fetch_pc != pcrb_last &&
		    !(last_fetch_pc[23:6] == 18'h281E1) &&
		    !(last_fetch_pc[23:4] == 20'hA1487) &&
		    !(last_fetch_pc[23:2] == 22'h285220)) begin
			pcrb[pcrb_w] <= last_fetch_pc;
			pcrb_w      <= pcrb_w + 6'd1;
			pcrb_last   <= last_fetch_pc;
			if (pcrb_armed_cnt) begin
				if (pcrb_k == 13'd0) begin
					pcrb_frozen <= 1'b1;
					// ★ buildAI: one-shot SCSI bus snapshot AT the window
					// freeze — the dying selection's live state (busdata =
					// the ID bits on the bus, SEL/BSY/out_en, per-target
					// phase/opcode/completions). A machine reset-hold would
					// wipe these flops; latching perturbs nothing.
					pcsn1 <= {dbg_scsi2_w, dbg_scsi_w};
					pcsn2 <= {dbg_scsi5_w, dbg_scsi4_w};
					// ★ buildAN: where the firmware parked when it stopped
					// clocking (read against egret_rom_disasm.md).
					egsn3 <= dbg_hc05_pc_w;
					// ★ buildAL: Egret/VIA1-SR snapshot at the same instant —
					// the stalled PRAM-write transaction's live handshake.
					egsn1 <= {8'd0,
					          dbg_sr_shift_reg,           // [23:16]
					          1'b0, dbg_sr_bit_cnt,       // [14:12]
					          dbg_sr_edge_pending,        // [11]
					          dbg_sr_fall_pending,        // [10]
					          dbg_sr_active,              // [9]
					          dbg_sr_dir,                 // [8]
					          dbg_sr_cb1,                 // [7]
					          dbg_sr_cb2,                 // [6]
					          dbg_eg_treq,                // [5]
					          dbg_eg_tip,                 // [4]
					          dbg_eg_byteack,             // [3]
					          dbg_eg_running,             // [2]
					          2'b00};
				end
				else pcrb_k <= pcrb_k - 13'd1;
			end
		end
		pcrb_q <= pcrb[pcrb_src[37:32]];
	end

	altsource_probe #(
		.instance_id ("PCRB"), .probe_width (32), .source_width (48),
		.sld_auto_instance_index ("YES")
	) cp_pcrb (.probe(pcrb_q), .source(pcrb_src), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("PCRS"), .probe_width (7), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_pcrs (.probe({pcrb_frozen, pcrb_w}), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildAI: SCSI bus state latched at the PCRB window freeze.
	// PSN1 = {dbg_scsi2 (phases + io handshake), dbg_scsi (out_en/SEL/BSY/
	// tbsy/mounted/busdata)} — busdata carries the ID bits of the selection
	// in flight. PSN2 = {dbg_scsi5 (last opcodes), dbg_scsi4 (rst count +
	// completions)}. Same decode as SCS1/SCS2 in read_bdst.tcl.
	altsource_probe #(
		.instance_id ("PSN1"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_psn1 (.probe(pcsn1), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("PSN2"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_psn2 (.probe(pcsn2), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildAL: the Egret story. EGS1 = SR/handshake snapshot at the window
	// freeze; EGS2 = live handshake counters since the last PCRB arm —
	// {cb1_falls[11:0], byteack_toggles[9:0], tip_toggles[9:0]}.
	altsource_probe #(
		.instance_id ("EGS1"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_egs1 (.probe(egsn1), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("EGS2"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_egs2 (.probe({eg_cb1_cnt, eg_ba_cnt, eg_tip_cnt}), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildAN: the HC05 firmware PC at the window freeze — the exact
	// wait/abort site it parked in (egret_rom_disasm.md is the map).
	altsource_probe #(
		.instance_id ("EGS3"), .probe_width (16), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_egs3 (.probe(egsn3), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildY: the SCSI target's own testimony — why does the ROM read a
	// perfect block 0 and never command the driver read? SCS1 = {dbg_scsi2
	// (target phases + io handshake), dbg_scsi (selection/arbitration)};
	// SCS2 = {dbg_scsi5 (per-target last-opcode bitmap), dbg_scsi4
	// (bus-reset count + per-target completion flags)}.
	altsource_probe #(
		.instance_id ("SCS1"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_scs1 (.probe({dbg_scsi2_w, dbg_scsi_w}), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	altsource_probe #(
		.instance_id ("SCS2"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_scs2 (.probe({dbg_scsi5_w, dbg_scsi4_w}), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ 2026-08-13: the CD target's own testimony (scsi.v dbg_cda1) — did
	// the guest ever talk to ID 3 and what did it last ask?
	// {toc_rdy, no_media, mounted, last_ok, sense_asc, sense_key, cmd_cnt, last_op}
	altsource_probe #(
		.instance_id ("CDA1"), .probe_width (32), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_cda1 (.probe(dbg_cd_w), .source(), .source_clk(clk_sys), .source_ena(1'b1));

	// ★ buildAJ: the CD target's LIVE bus machine — {cd_bsy, phase[2:0],
	// hs[7:0], hs2[3:0]}. cd_bsy stuck high = the disks' bus_busy gate
	// refuses every disk selection while the CD itself still answers.
	altsource_probe #(
		.instance_id ("CDPH"), .probe_width (16), .source_width (1),
		.sld_auto_instance_index ("YES")
	) cp_cdph (.probe(dbg_cd_state_w), .source(), .source_clk(clk_sys), .source_ena(1'b1));
`endif

endmodule
