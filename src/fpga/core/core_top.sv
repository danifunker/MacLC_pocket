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
//   0xF1000000  interact.json options
//   0xF8000000  APF host/target command handler
always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    32'hF1xxxxxx: begin
        bridge_rd_data <= {31'd0, opt_mem_size};
    end
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
reg         opt_mem_size    = 1'b0;   // 0 = 2 MB, 1 = 10 MB
reg         opt_reset_apply = 1'b0;   // action pulses (clk_74a)
reg         opt_reset_pram  = 1'b0;
reg         opt_nmi         = 1'b0;

always @(posedge clk_74a) begin
    // Actions are one-shot: they self-clear once the core side has seen them.
    opt_reset_apply <= 1'b0;
    opt_reset_pram  <= 1'b0;
    opt_nmi         <= 1'b0;

    if (bridge_wr) begin
        casex (bridge_addr)
        32'hF1000000: opt_mem_size    <= bridge_wr_data[0];
        32'hF1000004: opt_reset_apply <= bridge_wr_data[0];
        32'hF1000008: opt_reset_pram  <= bridge_wr_data[0];
        32'hF100000C: opt_nmi         <= bridge_wr_data[0];
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

// Target commands are only needed by the block-device path (apf_blockdev),
// which is not written yet. Held idle so core_bridge_cmd sees a well-defined
// state.
always @(posedge clk_74a) begin
    target_dataslot_read       <= 1'b0;
    target_dataslot_write      <= 1'b0;
    target_dataslot_getfile    <= 1'b0;
    target_dataslot_openfile   <= 1'b0;
    target_dataslot_id         <= 16'd0;
    target_dataslot_slotoffset <= 32'd0;
    target_dataslot_bridgeaddr <= 32'd0;
    target_dataslot_length     <= 32'd0;
end


////////////////////////////////////////////////////////////////////////////////////

// ---------------------------------------------------------------------------
// Data slot write sessions
// ---------------------------------------------------------------------------
// The OS announces a slot write with dataslot_requestwrite, streams the file
// over the bridge, then the session ends. apf_bridge_loader needs to know
// which slot is live so it can set dio_index; latch it here.
//
// Slot ids must match data.json:  0 = ROM, 1 = Floppy, 2/3 = SCSI, 4 = PRAM.
// Only 0 and 1 stream into SDRAM; the SCSI slots are block devices served on
// demand and are NOT handled by the loader.
reg  [15:0] loader_slot_id;
reg         loader_active;
always @(posedge clk_74a) begin
    if (dataslot_requestwrite) begin
        loader_slot_id <= dataslot_requestwrite_id;
        loader_active  <= (dataslot_requestwrite_id == 16'd0) ||
                          (dataslot_requestwrite_id == 16'd1);
    end else if (dataslot_allcomplete) begin
        loader_active <= 1'b0;
    end
end

    wire        dio_download;
    wire [7:0]  dio_index;
    wire [24:0] dio_addr;
    wire [15:0] dio_data;
    wire        dio_wr;
    wire        dio_ack;
    wire        loader_busy;

apf_bridge_loader #(
    .ADDR_BASE ( 32'h1000_0000 ),
    .ADDR_MASK ( 32'hE000_0000 )   // covers 0x10000000 (ROM) and 0x20000000 (floppy)
) loader (
    .clk_74a        ( clk_74a ),
    .bridge_addr    ( bridge_addr ),
    .bridge_wr      ( bridge_wr ),
    .bridge_wr_data ( bridge_wr_data ),

    .slot_id        ( loader_slot_id ),
    .slot_active    ( loader_active ),

    .clk_sys        ( clk_sys ),
    .reset          ( ~pll_core_locked_sys ),

    .dio_download   ( dio_download ),
    .dio_index      ( dio_index ),
    .dio_addr       ( dio_addr ),
    .dio_data       ( dio_data ),
    .dio_wr         ( dio_wr ),
    .dio_ack        ( dio_ack ),

    .busy           ( loader_busy )
);


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

assign audio_mclk = audgen_mclk;
assign audio_dac  = audgen_dac;
assign audio_lrck = audgen_lrck;

    wire signed [15:0] mac_audio;

// generate MCLK = 12.288mhz with fractional accumulator
    reg         [21:0]  audgen_accum;
    reg                 audgen_mclk;
    parameter   [20:0]  CYCLE_48KHZ = 21'd122880 * 2;
always @(posedge clk_74a) begin
    audgen_accum <= audgen_accum + CYCLE_48KHZ;
    if(audgen_accum >= 21'd742500) begin
        audgen_mclk <= ~audgen_mclk;
        audgen_accum <= audgen_accum - 21'd742500 + CYCLE_48KHZ;
    end
end

// generate SCLK = 3.072mhz by dividing MCLK by 4
    reg [1:0]   aud_mclk_divider;
    wire        audgen_sclk = aud_mclk_divider[1] /* synthesis keep*/;
always @(posedge audgen_mclk) begin
    aud_mclk_divider <= aud_mclk_divider + 1'b1;
end

// Shift out audio as I2S: 32 bit-slots per channel, 16 active bits MSB-first
// at the start of each slot then 16 dummy bits.
//
// The sample is latched at the START of each channel slot so the whole word
// shifts out coherently -- latching per bit would tear across an ASC update.
    reg     [4:0]   audgen_lrck_cnt;
    reg             audgen_lrck;
    reg             audgen_dac;
    reg     [15:0]  audgen_shift;
always @(negedge audgen_sclk) begin
    audgen_dac <= 1'b0;

    if (audgen_lrck_cnt < 5'd16)
        audgen_dac <= audgen_shift[15];

    audgen_shift <= (audgen_lrck_cnt == 5'd31) ? mac_audio
                                               : {audgen_shift[14:0], 1'b0};

    // 48khz * 64
    audgen_lrck_cnt <= audgen_lrck_cnt + 1'b1;
    if(audgen_lrck_cnt == 31) begin
        // switch channels
        audgen_lrck <= ~audgen_lrck;
    end
end


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
    wire opt_reset_apply_sys = rst_s [2] ^ rst_s [1];
    wire opt_reset_pram_sys  = pram_s[2] ^ pram_s[1];
    wire opt_nmi_sys         = nmi_s [2] ^ nmi_s [1];

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
    .reset          ( ~pll_core_locked_sys | opt_reset_apply_sys | opt_reset_pram_sys ),

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

    // Block devices: apf_blockdev is NOT WRITTEN YET, so these are held
    // inactive. The machine sees no mounted SCSI disks and boots from floppy.
    .sd_lba         ( sd_lba_u ),
    .sd_rd          ( sd_rd_u ),
    .sd_wr          ( sd_wr_u ),
    .sd_ack         ( 3'b000 ),
    .sd_buff_addr   ( 8'd0 ),
    .sd_buff_dout   ( 16'd0 ),
    .sd_buff_din    ( sd_buff_din_u ),
    .sd_buff_wr     ( 1'b0 ),
    .img_mounted    ( 3'b000 ),
    .img_size       ( 64'd0 ),

    // Simulation observability — unconnected; Quartus strips them.
    .debug_pc(), .debug_opcode(), .debug_fetch_valid(), .debug_data_addr(),
    .debug_ram_addr(), .debug_ram_din(), .debug_ram_dout(), .debug_ram_we(),
    .debug_ram_oe(), .debug_ram_ds(), .debug_selectRAM(), .debug_selectROM(),
    .debug_selectVIA(), .debug_selectAriel(), .debug_selectPseudoVIA(),
    .debug_selectSCSI(), .debug_selectSCC(), .debug_selectIWM(),
    .debug_selectASC(), .debug_selectVRAM(), .debug_cpuAddr(),
    .debug_cpuDataIn(), .debug_cpuDataOut(), .debug_cpuRW(),
    .debug_cpuBusControl(), .debug_cpu_as(), .debug_cpu_dtack(),

    // SCC channel A: no serial port is broken out on the Pocket.
    .serial_txd     ( ),
    .serial_rxd     ( 1'b1 ),          // idle mark

    .cfg_cpuType    ( 2'b10 ),         // 68020
    .cfg_memSize    ( opt_mem_size ),  // 0 = 2 MB, 1 = 10 MB
    .nmi_pulse      ( opt_nmi_sys )
);

assign mac_audio = mac_audio_l;        // ASC is mono
assign mac_de    = ~(mac_hb | mac_vb) & mac_ce_pix;

endmodule

`default_nettype wire
