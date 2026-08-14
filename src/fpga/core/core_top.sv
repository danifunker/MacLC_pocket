//
// Macintosh LC for the Analogue Pocket — APF top level
//
// Instantiated by the real top-level: apf_top
//
// ============================================================================
// WHAT THIS FILE IS
//
// core_top is the CHASSIS, not the machine. It owns everything Analogue-
// specific — the bridge, data slots, video/audio contracts, gamepad, the
// physical SDRAM pins — and hands the Macintosh LC itself (mac_lc_pocket) the
// same shaped edges the MiSTer top used to hand it:
//
//     MiSTer (sys/sys_top.v + MacLC.sv)      Pocket (this file)
//     ------------------------------------   ---------------------------------
//     hps_io CONF_STR / status[31:0]         interact.json -> bridge writes
//     hps_io dio_download/index/addr/data    apf_bridge_loader
//     hps_io sd_lba/sd_rd/sd_wr/sd_buff_*    apf_blockdev  (NOT YET WRITTEN)
//     hps_io ps2_key / ps2_mouse             pocket_input (gamepad synthesis)
//     framework scaler -> HDMI/VGA           video_rgb/de/hs/vs to the scaler
//     framework I2S (audio_out.sv)           audgen_* I2S generator below
//     SDRAM module on the DE10 daughterboard  dram_* pins + pocket_sdram
//
// The Mac RTL under rtl/ is untouched by any of this.
//
// STATUS: the APF side of this file is complete. mac_lc_pocket is NOT — see
// docs/PORT_STATUS.md. This project does not compile yet.
// ============================================================================

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable,

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,

///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,

output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
//
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig

);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness. 0 = big-endian, which is what apf_bridge_loader assumes
// when it splits each 32-bit bridge write into two 16-bit Mac words.
// The 68020 is big-endian too, so this keeps ROM and disk images in file
// order all the way into SDRAM.
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// ---------------------------------------------------------------------------
// Unused memories.
//
// The two cellular PSRAMs are deliberately idle. They are, however, the escape
// hatch if the M10K budget gets tight: the framebuffer is 192 of the device's
// 308 M10K blocks, and a dedicated cram would give video a private port with
// no CPU contention -- which is the exact condition that forced the framebuffer
// into BRAM in the first place (see rtl/vram_bram.sv). That would also allow
// 16bpp back. It is a real project, not a switch.
// ---------------------------------------------------------------------------
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


// ---------------------------------------------------------------------------
// Bridge read mux
// ---------------------------------------------------------------------------
// Writes are broadcast to every device; reads have to be muxed. The core
// claims three windows:
//   0x10000000  ROM data slot        (write-only, loader)
//   0x20000000  Floppy data slot     (write-only, loader)
//   0xF0000000  interact.json options
//   0xF8000000  APF host/target command handler
    wire [31:0] bd_bridge_rd_data;   // declared early: `default_nettype none`
    wire  [2:0] bd_dbg_stage;

always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    // apf_blockdev's 512-byte sector buffer. Outside apf_bridge_loader's
    // window (which masks to bridge_addr[31:30] == 2'b00) on purpose.
    32'h40xxxxxx: bridge_rd_data <= bd_bridge_rd_data;
    // Each variable must read back its OWN value: the Pocket reads a persisted
    // variable to populate the menu, and returning opt_mem_size for every
    // address in the window (as this did) gives the wrong value for all but one.
    32'hF0000000: bridge_rd_data <= {31'd0, opt_mem_size};
    32'hF0000010: bridge_rd_data <= {29'd0, opt_test_pattern};
    // Bring-up readout: how far the block device has ever got. Read off the
    // Core Settings menu -- see apf_blockdev.v dbg_stage.
    32'hF0000014: bridge_rd_data <= {29'd0, bd_dbg_stage};
    32'hF0xxxxxx: bridge_rd_data <= 32'd0;   // actions read back as 0
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    endcase
end

// ---------------------------------------------------------------------------
// interact.json option registers (clk_74a domain)
// ---------------------------------------------------------------------------
// These replace the MiSTer OSD's status[] word. Addresses must match
// interact.json.
//
// The two "apply at reset" semantics are inherited deliberately from the
// MiSTer core: memory size and monitor mode are sampled while the machine is
// held in reset, because a real LC only reads them at boot and the OS lays
// out QuickDraw for the boot geometry. Changing them live is guest-hostile.
// ★ Default 10 MB (2026-08-14). The OS writes this register only at core
// launch or when the menu VALUE CHANGES — a JTAG fabric push resets it and
// the OS never rewrites, so with a 2 MB default every pushed-fabric round
// silently ran 2 MB while the menu claimed 10 MB (the 08-12/08-13 memory
// deception, RESUME §0). Defaulting to the machine's intended config makes
// pushed fabrics honest; card launches are unaffected (the OS writes the
// persisted choice at launch either way). Keep interact.json defaultval in
// sync with this.
reg         opt_mem_size    = 1'b1;   // 0 = 2 MB, 1 = 10 MB
reg         opt_reset_apply = 1'b0;   // action pulses (clk_74a)
reg         opt_reset_pram  = 1'b0;
reg         opt_nmi         = 1'b0;
// Bring-up witness: [2] = show the video engine's built-in synthetic pattern
// instead of VRAM, [1:0] = which pattern. Visible whether or not the Mac runs,
// so it distinguishes "interact writes never arrive" from "they arrive but the
// machine is stalled and every action looks identical".
reg  [2:0]  opt_test_pattern = 3'd0;

always @(posedge clk_74a) begin
    // Actions are one-shot: they self-clear once the core side has seen them.
    opt_reset_apply <= 1'b0;
    opt_reset_pram  <= 1'b0;
    opt_nmi         <= 1'b0;

    if (bridge_wr) begin
        casex (bridge_addr)
        32'hF0000000: opt_mem_size    <= bridge_wr_data[0];
        32'hF0000004: opt_reset_apply <= bridge_wr_data[0];
        32'hF0000008: opt_reset_pram  <= bridge_wr_data[0];
        32'hF000000C: opt_nmi         <= bridge_wr_data[0];
        32'hF0000010: opt_test_pattern <= bridge_wr_data[2:0];
        default: ;
        endcase
    end
end

//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;

// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked_s;
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;

    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported;
    wire    [31:0]  savestate_addr;
    wire    [31:0]  savestate_size;
    wire    [31:0]  savestate_maxloadsize;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;

    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    reg             target_dataslot_read;
    reg             target_dataslot_write;
    reg             target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg             target_dataslot_openfile;   // require additional param/resp structs to be mapped

    wire            target_dataslot_ack;
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    reg     [15:0]  target_dataslot_id;
    reg     [31:0]  target_dataslot_slotoffset;
    reg     [31:0]  target_dataslot_bridgeaddr;
    reg     [31:0]  target_dataslot_length;

    wire    [31:0]  target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire    [31:0]  target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands

// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire            datatable_wren;
    wire    [31:0]  datatable_data;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),

    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),

    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),

    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),

    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),

    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);

// Savestates are not supported: the Mac core has an HC05 microcontroller
// (Egret), an SDRAM full of guest state, and mounted writable disk images.
// Snapshotting that coherently is a project of its own.
assign savestate_supported = 1'b0;
assign savestate_addr = 0;
assign savestate_size = 0;
assign savestate_maxloadsize = 0;
assign savestate_start_ack = 0;
assign savestate_start_busy = 0;
assign savestate_start_ok = 0;
assign savestate_start_err = 0;
assign savestate_load_ack = 0;
assign savestate_load_busy = 0;
assign savestate_load_ok = 0;
assign savestate_load_err = 0;

// target_dataslot_read/_write/_id/_slotoffset/_bridgeaddr/_length are now
// driven by apf_blockdev (instantiated below). Only the file-level commands
// stay idle -- we never open files by name.
always @(posedge clk_74a) begin
    target_dataslot_getfile    <= 1'b0;
    target_dataslot_openfile   <= 1'b0;
end

// ---------------------------------------------------------------------------
// Block device — SCSI disks on APF data slots
// ---------------------------------------------------------------------------
// Slots are declared `deferload` in data.json, following the reference Pocket
// core: nothing is transferred at mount time, dataslot_update is the media
// change event, and 512-byte sectors are fetched on demand. Slot ids 310/311
// map to SCSI IDs 0 and 1.
// ★ DIAGNOSTIC BISECTION (2026-08-11). Set to 1 to hide every SCSI disk from
// the machine: img_mounted is forced low, so the Mac's SCSI targets report no
// media and the boot ROM's bus scan finds an empty bus.
//
// WHY: the cold boot wedges with the CPU repeatedly on the SCSI pseudo-DMA
// windows ($F06000 and $F12000-$F13FFF, addrDecoder.v:161/169) where DTACK is
// ~scsiDREQ and DREQ never arrives. Everything shared with MiSTer has been
// diffed and matches, so the fault must be in Pocket-only glue -- and
// apf_blockdev is the only Pocket-only block on the SCSI path. This splits it
// cleanly: boots => the fault is in apf_blockdev; still hangs => SCSI is
// innocent and the hunt moves elsewhere.
//
// MUST be 0 for any release build.
// ★ MUST BE 0 IN ANY BUILD THE USER RUNS. This was set to 1 for a one-off
// bisection (does hiding all SCSI media change the boot hang? -- it did not)
// and then left on for many build/flash cycles, so the machine ran with NO
// disks at all while we were interpreting its boot behaviour. Do not ship 1.
// ★ 2026-08-12: temporarily 1 again ONLY for the baseline-anchor build (the
// golden build ran with media hidden). Must return to 0 in the first
// forward step after the baseline is re-proven — see docs/boot_problems.md.
// ★ 2026-08-12 buildV: returned to 0 — the download-tear root cause is fixed
// (boot_problems ★★★), cold boot reaches the "?" seek loop, and this is the
// first forward step: media visible again for the first honest SCSI test
// since the golden build.
localparam bit SCSI_DISABLE_DIAG = 1'b0;

localparam [15:0] SLOT_PRAM = 16'd220;   // NVRAM save file (256 bytes)
localparam [15:0] SLOT_HDD0 = 16'd310;
localparam [15:0] SLOT_HDD1 = 16'd311;
localparam [15:0] SLOT_CD   = 16'd320;   // CD-ROM ISO (read-only, ID 3)

    wire [2:0]  bd_sd_ack;
    wire [7:0]  bd_sd_buff_addr;
    wire [15:0] bd_sd_buff_dout;
    wire        bd_sd_buff_wr;
    wire [2:0]  bd_img_mounted;
    wire [31:0] bd_img_size;

// ---- JMNT: JTAG mount lever (2026-08-14) ----------------------------------
// A fabric push wipes the mount latches, and the Analogue OS re-sends
// dataslot_update only on a real OSD action -- so a freshly pushed fabric has
// no disks until someone touches the Pocket (the "you re-mount" step in every
// 08-12/08-13 capture round). This lever replays the host event from the PC:
//   source[48]    = fire (any edge; current value loops back on the probe so
//                   scripts read-then-invert instead of guessing)
//   source[47:32] = slot id (310/311/320/210)
//   source[31:0]  = image size in BYTES (the real file's size -- serving
//                   still comes from the OS via target_dataslot_read, this
//                   only tells the fabric what is mounted and how big)
// The injected level holds 31 clk_74a cycles so apf_blockdev's edge detector
// sees one clean event. A real bridge update wins the mux; overlap cannot
// happen in practice (injection exists for pushed fabrics where the OS is
// silent). Driver: scripts/jmnt.tcl.
    wire [48:0] jmnt_src;
    reg         jmnt_fire_d = 1'b0;
    reg  [4:0]  jmnt_hold   = 5'd0;
    always @(posedge clk_74a) begin
        jmnt_fire_d <= jmnt_src[48];
        if (jmnt_src[48] != jmnt_fire_d) jmnt_hold <= 5'd31;
        else if (jmnt_hold != 5'd0)      jmnt_hold <= jmnt_hold - 5'd1;
    end
    wire        jmnt_active  = (jmnt_hold != 5'd0);
    wire        bd_dsu       = dataslot_update | jmnt_active;
    wire [15:0] bd_dsu_id    = dataslot_update ? dataslot_update_id   : jmnt_src[47:32];
    wire [31:0] bd_dsu_size  = dataslot_update ? dataslot_update_size : jmnt_src[31:0];
    altsource_probe #(
        .instance_id ("JMNT"), .probe_width (1), .source_width (49),
        .sld_auto_instance_index ("YES")
    ) cp_jmnt (.probe(jmnt_src[48]), .source(jmnt_src), .source_clk(clk_74a), .source_ena(1'b1));

// ---- JMEM: JTAG memory-size override (buildAS) ----------------------------
// source[1] = override enable, source[0] = value (0 = 2 MB, 1 = 10 MB).
// Muxed into cfg_memSize below; sampled by the machine at reset, so pair a
// change with jboot. Exists for A/B rounds on pushed fabrics, where the OS
// never rewrites opt_mem_size (the RESUME §0 deception) — the RTL default is
// 10 MB (honest), and this lever is the only way to run a 2 MB control round
// without the user at the menu.
    wire [1:0] jmem_src;
    altsource_probe #(
        .instance_id ("JMEM"), .probe_width (2), .source_width (2),
        .sld_auto_instance_index ("YES")
    ) cp_jmem (.probe(jmem_src), .source(jmem_src), .source_clk(clk_74a), .source_ena(1'b1));

apf_blockdev #(
    .BUF_BASE ( 32'h4000_0000 )
) blockdev (
    .clk_74a        ( clk_74a ),
    .reset_n        ( pll_core_locked_s ),

    .bridge_addr    ( bridge_addr ),
    .bridge_wr      ( bridge_wr ),
    .bridge_wr_data ( bridge_wr_data ),
    .bridge_rd_data ( bd_bridge_rd_data ),

    // Muxed with the JMNT lever above -- injected mounts are indistinguishable
    // from OS-announced ones from here on down.
    .dataslot_update      ( bd_dsu ),
    .dataslot_update_id   ( bd_dsu_id ),
    .dataslot_update_size ( bd_dsu_size ),

    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),
    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .slot0_id       ( SLOT_HDD0 ),
    .slot1_id       ( SLOT_HDD1 ),
    .slot_cd_id     ( SLOT_CD ),
    .slot_flp_id    ( SLOT_FLOPPY ),

    .dio_download   ( bd_dio_download ),
    .dio_index      ( bd_dio_index ),
    .dio_addr       ( bd_dio_addr ),
    .dio_data       ( bd_dio_data ),
    .dio_wr         ( bd_dio_wr ),
    .dio_ack        ( bd_dio_ack ),
    .flp_allow      ( rom_done ),

    .clk_sys        ( clk_sys ),
    .sd_lba0        ( sd_lba_u[0] ),
    .sd_lba1        ( sd_lba_u[1] ),
    .sd_lba2        ( sd_lba_u[2] ),
    .sd_rd          ( sd_rd_u ),
    .sd_wr          ( sd_wr_u ),
    .sd_ack         ( bd_sd_ack ),
    .sd_buff_addr   ( bd_sd_buff_addr ),
    .sd_buff_dout   ( bd_sd_buff_dout ),
    .sd_buff_wr     ( bd_sd_buff_wr ),
    .sd_buff_din0   ( sd_buff_din_u[0] ),
    .sd_buff_din1   ( sd_buff_din_u[1] ),
    .img_mounted    ( bd_img_mounted ),
    .img_size       ( bd_img_size ),

    // ---- PRAM (NVRAM) persistence ----
    .slot_pram_id   ( SLOT_PRAM ),
    .pram_save_req  ( mac_pram_save_req ),
    .pram_load_addr ( bd_pram_load_addr ),
    .pram_load_data ( bd_pram_load_data ),
    .pram_load_wr   ( bd_pram_load_wr ),
    .pram_save_addr ( bd_pram_save_addr ),
    .pram_save_data ( mac_pram_save_data ),
    .pram_loaded    ( bd_pram_loaded ),

    .dbg_stage      ( bd_dbg_stage ),
    .dbg_cstate     ( bd_dbg_cstate ),
    .dbg_bdst       ( bd_dbg_bdst ),
    .dbg_bdw0       ( bd_dbg_bdw0 ),
    .dbg_bdlb       ( bd_dbg_bdlb ),
    .dbg_bdwr       ( bd_dbg_bdwr ),
    .dbg_bdww       ( bd_dbg_bdww )
);
    wire [31:0] bd_dbg_bdst;
    wire [31:0] bd_dbg_bdw0;
    wire [31:0] bd_dbg_bdlb;
    wire [31:0] bd_dbg_bdwr;
    wire [31:0] bd_dbg_bdww;

    // FRZE lever (probe under USE_BOOT_ISSP below; logic unconditional).
    // ★ buildAH: source[10] = TRIGGER-ONLY mode — the delivery-count hit
    // fires mac_trig (for the PCRB post-trigger countdown) WITHOUT holding
    // the machine, so the code that runs AFTER the final delivery — the
    // boot code's check-and-decide path — keeps executing into the ring.
    wire [10:0] frz_src;
`ifndef USE_BOOT_ISSP
    assign frz_src = 11'd0;   // no probe deck -> lever permanently released
`endif
    reg frz_hit = 1'b0;
    always @(posedge clk_sys) begin
        if (!frz_src[8])                              frz_hit <= 1'b0;
        else if (bd_dbg_bdlb[31:24] >= frz_src[7:0])  frz_hit <= 1'b1;
    end
    wire mac_freeze = frz_src[9] | (frz_hit && !frz_src[10]);
    wire mac_trig   = frz_hit && frz_src[10];

// PRAM persistence nets. The load path must complete before the machine's
// pram_ready rises -- see the ordering note in apf_blockdev.v.
    wire [4:0] bd_dbg_cstate;
    wire [7:0] bd_pram_load_addr, bd_pram_load_data, bd_pram_save_addr;
    wire       bd_pram_load_wr, bd_pram_loaded;
    wire [7:0] mac_pram_save_data;
    wire       mac_pram_save_req;


////////////////////////////////////////////////////////////////////////////////////

// ---------------------------------------------------------------------------
// Data slot write sessions
// ---------------------------------------------------------------------------
// The OS announces a slot write with dataslot_requestwrite, streams the file
// over the bridge, then the session ends. apf_bridge_loader needs to know
// which slot is live so it can set dio_index; latch it here.
//
// Slot ids must match data.json. They are 200 (ROM) and 210 (Floppy), NOT 0
// and 1: every data slot in the reference core (Pocket-Amiga) is numbered from
// 200 up, and low ids appear to be reserved — a plausible cause of the
// "Load error in 'core'" seen with ids 0/1.
//
// The Mac side still wants MiSTer's dio_index convention (0 = ROM, 1 = floppy,
// and mac_lc_pocket decodes dio_index[1:0] for the DC42/floppy paths), so the
// APF slot id is translated here rather than propagated inward.
localparam [15:0] SLOT_ROM    = 16'd200;
localparam [15:0] SLOT_FLOPPY = 16'd210;

reg  [15:0] loader_slot_id;
reg         loader_active;
always @(posedge clk_74a) begin
    if (dataslot_requestwrite) begin
        loader_slot_id <= (dataslot_requestwrite_id == SLOT_FLOPPY) ? 16'd1 : 16'd0;
        loader_active  <= (dataslot_requestwrite_id == SLOT_ROM) ||
                          (dataslot_requestwrite_id == SLOT_FLOPPY);
    end else if (dataslot_allcomplete) begin
        loader_active <= 1'b0;
    end
end

// Two producers feed the machine's download port:
//   apf_bridge_loader  the ROM, streamed by the OS into the bridge window
//   apf_blockdev       the floppy, pulled in sector by sector at our own pace
// They cannot overlap in practice (ROM at boot, floppy on mount), so a simple
// priority mux on the loader is enough.
    wire        ldr_dio_download;
    wire [7:0]  ldr_dio_index;
    wire [24:0] ldr_dio_addr;
    wire [15:0] ldr_dio_data;
    wire        ldr_dio_wr;

    wire        bd_dio_download;
    wire [7:0]  bd_dio_index;
    wire [24:0] bd_dio_addr;
    wire [15:0] bd_dio_data;
    wire        bd_dio_wr;

    wire        dio_download = ldr_dio_download | bd_dio_download;
    wire [7:0]  dio_index    = ldr_dio_download ? ldr_dio_index : bd_dio_index;
    wire [24:0] dio_addr     = ldr_dio_download ? ldr_dio_addr  : bd_dio_addr;
    wire [15:0] dio_data     = ldr_dio_download ? ldr_dio_data  : bd_dio_data;
    wire        dio_wr       = ldr_dio_download ? ldr_dio_wr    : bd_dio_wr;
    wire        dio_ack;
    wire        loader_busy;

// dio_ack MUST go to exactly one producer. Both used to receive it, so while
// the ROM streamed, the floppy bulk-loader consumed acks belonging to the
// loader's words (and vice versa) -- each advanced on the other's completions.
// At cold boot the deferload slots raise dataslot_update while the ROM is still
// streaming, so the two ran concurrently and corrupted the ROM load. Symptom:
// cold boot unreliable, "force reload the ROM twice and it comes good".
    wire ldr_dio_ack = dio_ack &  ldr_dio_download;
    wire bd_dio_ack  = dio_ack & ~ldr_dio_download;

// Belt and braces: do not begin a floppy bulk copy until the ROM download has
// finished at least once. Latched on the falling edge of the loader's download.
    reg  rom_done = 1'b0, ldr_dl_d = 1'b0;
always @(posedge clk_sys) begin
    ldr_dl_d <= ldr_dio_download;
    if (ldr_dl_d && !ldr_dio_download) rom_done <= 1'b1;
end

apf_bridge_loader #(
    .ADDR_BASE ( 32'h1000_0000 ),
    // Must cover BOTH 0x10000000 (ROM) and 0x20000000 (floppy). 0xE000_0000
    // does NOT: it compares bits [31:29], and 0x2xxxxxxx differs from the
    // 0x1xxxxxxx base there, so every floppy write was silently dropped.
    // 0xC000_0000 maps both windows to 0x00000000. `accept` is additionally
    // gated on slot_active, so widening the window admits no stray traffic.
    .ADDR_MASK ( 32'hC000_0000 )
) loader (
    .clk_74a        ( clk_74a ),
    .bridge_addr    ( bridge_addr ),
    .bridge_wr      ( bridge_wr ),
    .bridge_wr_data ( bridge_wr_data ),

    .slot_id        ( loader_slot_id ),
    .slot_active    ( loader_active ),

    .clk_sys        ( clk_sys ),
    .reset          ( ~pll_core_locked_sys ),

    .dio_download   ( ldr_dio_download ),
    .dio_index      ( ldr_dio_index ),
    .dio_addr       ( ldr_dio_addr ),
    .dio_data       ( ldr_dio_data ),
    .dio_wr         ( ldr_dio_wr ),
    .dio_ack        ( ldr_dio_ack ),

    .dbg_bridge_words ( ldr_dbg_bridge_words ),
    .dbg_pop_words    ( ldr_dbg_pop_words ),

    .busy           ( loader_busy )
);

// ---------------------------------------------------------------------------
// Cold-boot forensics deck (JTAG In-System probes) — DEBUG BUILDS ONLY
// ---------------------------------------------------------------------------
// Enable with USE_BOOT_ISSP in ap_core.qsf; must be OFF for release fits.
// Read with: bash scripts/read_boot_probes.sh
//
// The question this deck exists to answer: when a cold boot needs the ROM
// re-loaded two or three times, where do the words go? Three counters bracket
// the whole path, and the first one that disagrees localises the loss:
//
//   BRGC  words the Analogue OS handed the loader   (clk_74a, in apf_bridge_loader)
//   POPC  words the loader popped toward the machine (clk_sys, same module)
//   ROMC  words the machine retired into SDRAM       (in mac_lc_pocket)
//
// For a 512 KB boot0.rom all three should read 0x40000 = 262,144 after one
// load. They are free-running and never cleared, so read the DELTA across a
// load rather than the absolute value.
//
// DLST carries the arbitration state that the RESUME's cold-boot race theory
// turns on -- in particular whether bd_dio_download is stuck high (it is
// raised on floppy mount without checking flp_allow, apf_blockdev.v:288) and
// therefore steering dio_index away from the ROM's 8'd0, which is what the
// machine's reset hold at mac_lc_pocket.sv:257 keys off.
    wire [31:0] ldr_dbg_bridge_words;
    wire [31:0] ldr_dbg_pop_words;

    // Full 32-bit CPU address, taken from mac_lc_pocket's long-existing
    // debug_cpuAddr output (core_top had left it unconnected). Only the top
    // byte is probed: CPUA already carries [23:0].
    wire [31:0] dbg_cpu_addr_full;
    wire [7:0]  dbg_cpu_addr_hi = dbg_cpu_addr_full[31:24];

    wire [31:0] dbg_dl_status = {
        // [31:24] cpuAddr[31:24] -- the byte CPUA truncates away. Decides
        // whether the PDS scan we are stuck in is the 24-bit slot form
        // ($00E8xxxx) or a 32-bit one, which slot_space (F1..FE) gates
        // completely differently. Routed out of the machine for the probe.
        dbg_cpu_addr_hi,
        bd_dbg_cstate,     // [23:19] blockdev FSM state
        bd_pram_loaded,    // [18]    PRAM load resolved?
        dataslot_allcomplete,   // [17]
        dataslot_requestwrite,  // [16]
        loader_active,          // [15]
        loader_busy,            // [14]
        rom_done,               // [13] == flp_allow into apf_blockdev
        bd_dio_download,        // [12] stuck high from mount until copy ends?
        ldr_dio_download,       // [11]
        dio_download,           // [10] the OR the machine actually sees
        dio_index,              // [9:2] 0=ROM 1=floppy — the reset-hold key
        reset_n,                // [1] APF host reset
        pll_core_locked_sys     // [0]
    };

`ifdef USE_BOOT_ISSP
    altsource_probe #(
        .instance_id ("BRGC"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_brgc (.probe(ldr_dbg_bridge_words), .source(), .source_clk(clk_sys), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("POPC"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_popc (.probe(ldr_dbg_pop_words),    .source(), .source_clk(clk_sys), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("DLST"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_dlst (.probe(dbg_dl_status),        .source(), .source_clk(clk_sys), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("BDST"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_bdst (.probe(bd_dbg_bdst),          .source(), .source_clk(clk_sys), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("BDW0"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_bdw0 (.probe(bd_dbg_bdw0),          .source(), .source_clk(clk_sys), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("BDLB"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_bdlb (.probe(bd_dbg_bdlb),          .source(), .source_clk(clk_sys), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("BDWR"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_bdwr (.probe(bd_dbg_bdwr),          .source(), .source_clk(clk_sys), .source_ena(1'b1));

    // ★ buildAD FRZE: freeze the machine (hold reset, RAM intact) either
    // manually or automatically when the blockdev's cumulative delivery
    // count reaches a threshold — stop the world at "+58" with the System
    // fully landed, before the death spiral scribbles anything.
    //   source[9]  = manual freeze (level)
    //   source[8]  = arm auto-trigger
    //   source[7:0]= delivery-count threshold (ABSOLUTE — the counter is
    //                cumulative across rounds; read BDLB first, add, arm)
    //   probe[8]   = frozen now   probe[7:0] = live delivery count
    // frz_hit latches on arm+reach and clears only on disarm, so a wrapping
    // counter cannot un-freeze the corpse mid-dump.
    altsource_probe #(
        .instance_id ("FRZE"), .probe_width (9), .source_width (11),
        .sld_auto_instance_index ("YES")
    ) cp_frze (.probe({mac_freeze, bd_dbg_bdlb[31:24]}), .source(frz_src), .source_clk(clk_sys), .source_ena(1'b1));

    altsource_probe #(
        .instance_id ("BDWW"), .probe_width (32), .source_width (1),
        .sld_auto_instance_index ("YES")
    ) cp_bdww (.probe(bd_dbg_bdww),          .source(), .source_clk(clk_sys), .source_ena(1'b1));
`endif


// ---------------------------------------------------------------------------
// Input: gamepad -> ps2_key / ps2_mouse
// ---------------------------------------------------------------------------
    wire [10:0] ps2_key;
    wire [24:0] ps2_mouse;
    wire        ptr_mode;

pocket_input #(
    .CLK_HZ ( 32_500_000 )
) input_bridge (
    .clk        ( clk_sys ),
    .reset      ( ~pll_core_locked_sys ),
    .cont1_key  ( cont1_key[15:0] ),
    .ps2_key    ( ps2_key ),
    .ps2_mouse  ( ps2_mouse ),
    .ptr_mode   ( ptr_mode )
);


// ---------------------------------------------------------------------------
// Video: Mac V8 pixel stream -> Analogue scaler
// ---------------------------------------------------------------------------
// The APF contract is a free-running pixel clock with de/hs/vs strobes; the
// scaler in the second FPGA does the rest. Two things matter:
//
//  1. hs and vs are SINGLE-CYCLE pulses in the BACK PORCH, not level syncs.
//     The Mac core emits level syncs (hsync/vsync), so they are edge-detected
//     here. Getting this wrong gives a rolling or offset image, not a blank
//     one, which makes it easy to misdiagnose.
//  2. video_rgb must be 0 outside active video. The scaler samples the bus
//     continuously and non-black blanking bleeds into the border.
//
// video_skip is for cores that drop frames to hit a rate; the Mac runs at a
// fixed 60.15 Hz so it is always 0.

    wire        mac_hsync, mac_vsync, mac_de;
    wire [7:0]  mac_r, mac_g, mac_b;

    reg         hs_d, vs_d;
    reg [23:0]  vidout_rgb;
    reg         vidout_de, vidout_hs, vidout_vs;

always @(posedge clk_pix) begin
    hs_d <= mac_hsync;
    vs_d <= mac_vsync;

    // Rising edge of each level sync -> one-cycle APF pulse.
    vidout_hs <= (~hs_d & mac_hsync);
    vidout_vs <= (~vs_d & mac_vsync);

    vidout_de  <= mac_de;
    vidout_rgb <= mac_de ? {mac_r, mac_g, mac_b} : 24'h000000;
end

assign video_rgb_clock    = clk_pix;
assign video_rgb_clock_90 = clk_pix_90;
assign video_rgb          = vidout_rgb;
assign video_de           = vidout_de;
assign video_skip         = 1'b0;
assign video_vs           = vidout_vs;
assign video_hs           = vidout_hs;


// ---------------------------------------------------------------------------
// Audio: ASC PCM -> APF I2S
// ---------------------------------------------------------------------------
// The APF audio interface is a plain I2S slave-ish contract: the core supplies
// MCLK (12.288 MHz), LRCK (48 kHz) and serial data. The MiSTer framework did
// this in sys/audio_out.sv; here it is the template's generator with a real
// sample shifted in instead of silence.
//
// The Mac's ASC output is MONO (the LC has one speaker); the same sample goes
// to both channels.

    wire signed [15:0] mac_audio;

// The I2S shifter that used to be inlined here never produced audible output.
// It has been replaced by src/fpga/core/i2s.v, modelled on the reference
// Pocket core's known-good module -- see that file's header for what differs
// (chiefly: the sample is now synchronised into the SCLK domain, which it was
// not before). The ASC is mono, so the same sample feeds both channels.
i2s i2s_out (
    .clk_74a     ( clk_74a ),
    .left_audio  ( mac_audio ),
    .right_audio ( mac_audio ),

    .audio_mclk  ( audio_mclk ),
    .audio_dac   ( audio_dac ),
    .audio_lrck  ( audio_lrck )
);


///////////////////////////////////////////////
// Clocks
///////////////////////////////////////////////

    wire    clk_mem;        // 65.0 MHz  — SDRAM state machine
    wire    clk_mem_90;     // 65.0 MHz, +90deg — driven onto dram_clk
    wire    clk_sys;        // 32.5 MHz  — the whole Mac core
    wire    clk_pix;        // 15.667 MHz — 512x384 dot clock

    wire    pll_core_locked;
    wire    pll_core_locked_s;
synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

    wire    pll_core_locked_sys;
synch_3 s02(pll_core_locked, pll_core_locked_sys, clk_sys);

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( 0 ),

    .outclk_0       ( clk_mem ),
    .outclk_1       ( clk_mem_90 ),
    .outclk_2       ( clk_sys ),
    .outclk_3       ( clk_pix ),
    .outclk_4       (  ),

    .locked         ( pll_core_locked )
);

// The APF video contract wants a 90-degree companion to the pixel clock so the
// scaler can centre its sampling. clk_pix is not phase-related to any other
// PLL output, so it gets its own shifted tap rather than being derived here.
// UNRESOLVED: mf_pllbase currently has no 90-degree pixel output -- outclk_4
// is free and should be configured as clk_pix + 90deg. Until then the scaler
// gets the unshifted clock, which is the common case for slow pixel clocks but
// is not guaranteed. See docs/PORT_STATUS.md.
    wire clk_pix_90 = clk_pix;


///////////////////////////////////////////////
// The machine
///////////////////////////////////////////////

    wire [12:0] sdram_a;
    wire [1:0]  sdram_ba;
    wire [1:0]  sdram_dqm;
    wire        sdram_cke, sdram_ras_n, sdram_cas_n, sdram_we_n;

assign dram_a     = sdram_a;
assign dram_ba    = sdram_ba;
assign dram_dqm   = sdram_dqm;
assign dram_cke   = sdram_cke;
assign dram_ras_n = sdram_ras_n;
assign dram_cas_n = sdram_cas_n;
assign dram_we_n  = sdram_we_n;
assign dram_clk   = clk_mem_90;

// mac_lc_pocket keeps sim.v's port NAMES on purpose (VGA_*, ioctl_*, debug_*,
// cfg_*, 3-slot sd_*) so that verilator/sim.v can eventually instantiate it
// instead of duplicating the machine. core_top is where those names are
// adapted to APF, in one place. See the header of mac_lc_pocket.sv.

    wire [31:0] sd_lba_u [3];
    wire  [2:0] sd_rd_u, sd_wr_u;
    wire [15:0] sd_buff_din_u [3];
    wire        mac_hb, mac_vb, mac_ce_pix;
    wire [15:0] mac_audio_l, mac_audio_r;

// ---------------------------------------------------------------------------
// clk_74a -> clk_sys crossings for the option registers
// ---------------------------------------------------------------------------
// opt_reset_apply / opt_reset_pram / opt_nmi are single-cycle pulses generated
// in the bridge's clk_74a domain (74.25 MHz). clk_sys is 32.5 MHz — LESS than
// half — so a one-cycle pulse there can fall entirely between two clk_sys
// edges and be missed. A plain 2FF synchroniser is therefore not enough: the
// pulse is stretched into a level with a toggle, and the edge is recovered on
// the far side.
    reg  opt_reset_tgl = 1'b0, opt_pram_tgl = 1'b0, opt_nmi_tgl = 1'b0;
always @(posedge clk_74a) begin
    if (opt_reset_apply) opt_reset_tgl <= ~opt_reset_tgl;
    if (opt_reset_pram)  opt_pram_tgl  <= ~opt_pram_tgl;
    if (opt_nmi)         opt_nmi_tgl   <= ~opt_nmi_tgl;
end

    reg [2:0] rst_s, pram_s, nmi_s;
always @(posedge clk_sys) begin
    rst_s  <= {rst_s [1:0], opt_reset_tgl};
    pram_s <= {pram_s[1:0], opt_pram_tgl};
    nmi_s  <= {nmi_s [1:0], opt_nmi_tgl};
end
    wire opt_reset_apply_edge = rst_s [2] ^ rst_s [1];
    wire opt_reset_pram_edge  = pram_s[2] ^ pram_s[1];
    wire opt_nmi_edge         = nmi_s [2] ^ nmi_s [1];

// ---------------------------------------------------------------------------
// Stretch the action edges into levels
// ---------------------------------------------------------------------------
// mac_lc_pocket samples `reset` INSIDE `if (clk8_en_p)` (see its reset block),
// and clk8_en_p is high one clk_sys cycle in four. A single-cycle pulse is
// therefore MISSED 75% OF THE TIME. Observed on hardware as "Reset & Apply
// does nothing" -- and as general flakiness, since it did occasionally land.
//
// 16 clk_sys cycles comfortably covers the 4-cycle enable period with margin.
// Safe for all three consumers: the machine's reset test is level-sensitive,
// nmi_pulse is rising-edge-detected in an ungated block, and the pram_zero FSM
// simply re-arms (addr back to 0) while the level is high and then runs once it
// drops.
    reg [4:0] rst_hold = 5'd0, pram_hold = 5'd0, nmi_hold = 5'd0;
always @(posedge clk_sys) begin
    if (opt_reset_apply_edge) rst_hold  <= 5'd16; else if (rst_hold)  rst_hold  <= rst_hold  - 5'd1;
    if (opt_reset_pram_edge)  pram_hold <= 5'd16; else if (pram_hold) pram_hold <= pram_hold - 5'd1;
    if (opt_nmi_edge)         nmi_hold  <= 5'd16; else if (nmi_hold)  nmi_hold  <= nmi_hold  - 5'd1;
end
    wire opt_reset_apply_sys = |rst_hold;
    wire opt_reset_pram_sys  = |pram_hold;
    wire opt_nmi_sys         = |nmi_hold;

// opt_test_pattern is a level, not a pulse, so a plain 2FF synchroniser is
// right here. A multi-bit crossing can show a transient mixed value for one
// clk_sys cycle while the user changes the setting; for a test pattern that is
// cosmetically irrelevant. v8_video re-syncs both fields into clk_pix itself.
    reg [2:0] tp_s1, tp_s2;
always @(posedge clk_sys) begin
    tp_s1 <= opt_test_pattern;
    tp_s2 <= tp_s1;
end

// ---------------------------------------------------------------------------
// APF host reset
// ---------------------------------------------------------------------------
// reset_n is held LOW by the OS while it loads data slots and writes interact
// defaults / persisted values into the core, then released with the [0011 Reset
// Exit] host command (see the interact.json spec). It was declared at import and
// wired to nothing but status_running, so the machine began running before APF
// had finished setup -- the likely reason a COLD load needed the ROM reselected
// by hand while a second boot worked. core-template uses it as an async core
// reset; here it joins the synchronous reset the machine already takes.
    reg  [1:0] rstn_s;
always @(posedge clk_sys) rstn_s <= {rstn_s[0], reset_n};
    wire reset_n_sys = rstn_s[1];

// ---------------------------------------------------------------------------
// Download handshake
// ---------------------------------------------------------------------------
// The machine exposes MiSTer's ioctl_wait ("core busy, hold off"), which it
// raises on each write and drops once the word has actually reached SDRAM via
// its dioBusControl slot. apf_bridge_loader wants the complementary edge — a
// 1-cycle "you may retire that word". Take the FALLING edge of ioctl_wait.
    wire dio_ack_n;                    // = the machine's ioctl_wait
    reg  dio_wait_d;
always @(posedge clk_sys) dio_wait_d <= dio_ack_n;
assign dio_ack = dio_wait_d & ~dio_ack_n;   // dio_ack declared with the loader

mac_lc_pocket machine (
    // Pocket-specific
    .clk_mem        ( clk_mem ),
    .clk_pix        ( clk_pix ),
    .pll_locked     ( pll_core_locked_sys ),
    .sdram_dq       ( dram_dq ),
    .sdram_a        ( sdram_a ),
    .sdram_dqm      ( sdram_dqm ),
    .sdram_ba       ( sdram_ba ),
    .sdram_cke      ( sdram_cke ),
    .sdram_we_n     ( sdram_we_n ),
    .sdram_ras_n    ( sdram_ras_n ),
    .sdram_cas_n    ( sdram_cas_n ),

    .clk_sys        ( clk_sys ),
    // Reset is a LEVEL that also arms the SDRAM re-init pulse inside the
    // machine, so it must be a clean edge, not a held level during downloads.
    .reset          ( ~pll_core_locked_sys | ~reset_n_sys |
                      opt_reset_apply_sys | opt_reset_pram_sys ),

    .ps2_key        ( ps2_key ),
    .ps2_mouse      ( ps2_mouse ),

    // APF gives epoch seconds; the machine wants sim.v's 33-bit timestamp.
    .timestamp      ( {1'b0, rtc_epoch_seconds} ),

    .VGA_R          ( mac_r ),
    .VGA_G          ( mac_g ),
    .VGA_B          ( mac_b ),
    .VGA_HS         ( mac_hsync ),
    .VGA_VS         ( mac_vsync ),
    .VGA_HB         ( mac_hb ),
    .VGA_VB         ( mac_vb ),
    .CE_PIXEL       ( mac_ce_pix ),

    // ASC is mono; both channels carry the same sample.
    .AUDIO_L        ( mac_audio_l ),
    .AUDIO_R        ( mac_audio_r ),

    // ROM / floppy download. apf_bridge_loader emits a byte address and a
    // 1-cycle write strobe, which is exactly ioctl_addr/ioctl_wr's contract.
    .ioctl_download ( dio_download ),
    .ioctl_wr       ( dio_wr ),
    .ioctl_addr     ( dio_addr ),
    .ioctl_dout     ( dio_data ),
    .ioctl_index    ( dio_index ),
    .ioctl_wait     ( dio_ack_n ),

    // Block devices: slots 0/1 = HDDs, slot 2 = the CD-ROM (ISO, read-only).
    .sd_lba         ( sd_lba_u ),
    .sd_rd          ( sd_rd_u ),
    .sd_wr          ( sd_wr_u ),
    .sd_ack         ( bd_sd_ack ),
    .sd_buff_addr   ( bd_sd_buff_addr ),
    .sd_buff_dout   ( bd_sd_buff_dout ),
    .sd_buff_din    ( sd_buff_din_u ),
    .sd_buff_wr     ( bd_sd_buff_wr ),
    // SCSI_DISABLE_DIAG hides all media from the machine — see the localparam.
    .img_mounted    ( SCSI_DISABLE_DIAG ? 3'b000 : bd_img_mounted ),
    // hps_io semantics: valid on the img_mounted pulse. mac_lc_pocket slices
    // img_size[40:9] to get 512-byte block count.
    .img_size       ( {32'd0, bd_img_size} ),
    .ext_freeze     ( mac_freeze ),
    .ext_trig       ( mac_trig ),

    // Simulation observability — unconnected; Quartus strips them.
    .debug_pc(), .debug_opcode(), .debug_fetch_valid(), .debug_data_addr(),
    .debug_ram_addr(), .debug_ram_din(), .debug_ram_dout(), .debug_ram_we(),
    .debug_ram_oe(), .debug_ram_ds(), .debug_selectRAM(), .debug_selectROM(),
    .debug_selectVIA(), .debug_selectAriel(), .debug_selectPseudoVIA(),
    .debug_selectSCSI(), .debug_selectSCC(), .debug_selectIWM(),
    .debug_selectASC(), .debug_selectVRAM(), .debug_cpuAddr(dbg_cpu_addr_full),

    // ---- PRAM (NVRAM) persistence ----
    .pram_load_addr_i ( bd_pram_load_addr ),
    .pram_load_data_i ( bd_pram_load_data ),
    .pram_load_wr_i   ( bd_pram_load_wr ),
    .pram_loaded_i    ( bd_pram_loaded ),
    .pram_save_addr_i ( bd_pram_save_addr ),
    .pram_save_data_o ( mac_pram_save_data ),
    .pram_save_req_o  ( mac_pram_save_req ),
    .debug_cpuDataIn(), .debug_cpuDataOut(), .debug_cpuRW(),
    .debug_cpuBusControl(), .debug_cpu_as(), .debug_cpu_dtack(),

    // SCC channel A: no serial port is broken out on the Pocket.
    .serial_txd     ( ),
    .serial_rxd     ( 1'b1 ),          // idle mark

    .cfg_cpuType    ( 2'b10 ),         // 68020
    // Memory config: selectable via the interact.json Memory item (register
    // 0xF0000000, opt_mem_size above), 0 = 2 MB (configRAMSize 8'h24),
    // 1 = 10 MB (8'hE4). History below, newest last — the evidence has
    // flipped more than once, so read all of it before trusting any line.
    //
    // Set to 2 MB on 2026-08-10 after the ASC was fixed and the machine began
    // playing the CHIMES OF DEATH -- a 68k POST failure, most commonly the RAM
    // test. 10 MB had been locked in on the belief that only it booted, but the
    // Memory menu item defaulted to 2 MB, so the earlier successful boots to
    // the "?" disk screen were probably 2 MB all along.
    //
    // 2 MB is also the only config with verification behind it: sim.v hardwires
    // 8'h24 and the Verilator boot oracle passes on it, while PORT_STATUS
    // records that the 10 MB SIMM path has NEVER been exercised in simulation.
    //
    // If 2 MB silences the death chimes, the 10 MB path has a real bug -- most
    // likely the V8 bank layout implied by 8'hE4 not matching what pocket_sdram
    // actually provides (a 16 MB subset), so the ROM's RAM test probes memory
    // that aliases or is not there.
    // 0 = 2 MB (configRAMSize 8'h24), 1 = 10 MB (8'hE4). Selectable via the
    // Memory menu item, and `persist` so a 10 MB choice survives a core load.
    //
    // Sampled while the machine is held in reset, so pair any change with
    // Reset & Apply.
    //
    // Evidence so far, for whoever debugs boot next: 2 MB produced a HAPPY
    // CHIME on hardware; 10 MB produced the CHIMES OF DEATH (a 68k POST
    // failure, usually the RAM test). 2 MB is also the only config the
    // Verilator boot oracle validates -- sim.v hardwires 8'h24 -- while
    // PORT_STATUS records the 10 MB SIMM path as never exercised in
    // simulation. If boot goes wrong, try 2 MB before suspecting anything else.
    //
    // 2026-08-13 UPDATE, superseding the death-chime line above: after the
    // write-path and VIA-timer fixes, a user-confirmed TRUE-10 MB round
    // (menu re-select + Reset & Apply, games disk) passed POST, played the
    // chime, and reached "Welcome to Macintosh" -- 10 MB POSTs fine now.
    // The death chimes were measured on the 08-10 netlist and do not carry
    // forward.
    .cfg_memSize    ( jmem_src[1] ? jmem_src[0] : opt_mem_size ),  // JMEM lever wins when enabled
    .nmi_pulse      ( opt_nmi_sys ),
    // Same pulse also stays in .reset above: the zeroing takes ~8 us and the
    // reset stretch is ~2 ms, so the Egret is held off until PRAM is clear.
    .pram_reset     ( opt_reset_pram_sys ),
    .test_pattern   ( tp_s2 )
);

assign mac_audio = mac_audio_l;        // ASC is mono
assign mac_de    = ~(mac_hb | mac_vb) & mac_ce_pix;

endmodule

`default_nettype wire
