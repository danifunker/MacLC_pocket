// tb_amnt.v — launch-time auto-mount integration bench.
//
// Chain under test (all REAL modules except the OS):
//   tb (plays the Analogue OS on the bridge)
//     -> core_bridge_cmd      real: datatable RAM + 0x008A/0x008F handlers
//     -> amnt_wrap            real: AMNT block extracted verbatim from core_top.sv
//     -> apf_blockdev         real: dsu edge latch -> clk_sys img_mounted/img_size
//
// Scenario (mirrors the documented openFPGA launch sequence):
//   1. OS writes the data slot table: {200,rom} {210,flp} {310,hda} {311,0} {320,iso}
//   2. OS sends 0x008F (Data slot access all complete)   <- while reset held
//      EXPECT: img_mounted[0] pulse w/ size 41992192 (slot 310)
//              img_mounted[2] pulse w/ size 7112704  (slot 320)
//              dio_download rises (slot 210 floppy mount latched, copy gated)
//              img_mounted[1] never (311 size 0); slot 200 ignored (unknown id)
//   3. 0x0080 + 0x008F again (allcomplete re-rises)
//      EXPECT: no new mounts (scanner is one-shot)
//   4. Real OSD pick: 0x008A slot 310, new size
//      EXPECT: img_mounted[0] second pulse w/ the new size (path untouched)
`timescale 1ns/1ps

module tb_amnt;

    reg clk74  = 0;
    reg clksys = 0;
    always #6.7  clk74  = ~clk74;    // ~74.6 MHz
    always #15.4 clksys = ~clksys;   // ~32.5 MHz

    // ---- bridge (the OS side) -------------------------------------------
    reg  [31:0] bridge_addr    = 32'd0;
    reg  [31:0] bridge_wr_data = 32'd0;
    reg         bridge_wr      = 1'b0;

    // ---- core_bridge_cmd ------------------------------------------------
    wire        os_reset_n;
    wire        dataslot_update;
    wire [15:0] dataslot_update_id;
    wire [31:0] dataslot_update_size;
    wire        dataslot_allcomplete;
    wire [9:0]  dt_addr;
    wire        dt_wren;
    wire [31:0] dt_data;
    wire [31:0] dt_q;

    wire        bd_target_read, bd_target_write;
    wire        target_ack, target_done;
    wire [2:0]  target_err;
    wire [15:0] bd_target_id;
    wire [31:0] bd_target_off, bd_target_ba, bd_target_len;

    core_bridge_cmd icb (
        .clk                    ( clk74 ),
        .reset_n                ( os_reset_n ),
        .bridge_endian_little   ( 1'b0 ),
        .bridge_addr            ( bridge_addr ),
        .bridge_rd              ( 1'b0 ),
        .bridge_rd_data         ( ),
        .bridge_wr              ( bridge_wr ),
        .bridge_wr_data         ( bridge_wr_data ),
        .status_boot_done       ( 1'b1 ),
        .status_setup_done      ( 1'b1 ),
        .status_running         ( 1'b0 ),
        .dataslot_requestread_ack  ( 1'b1 ),
        .dataslot_requestread_ok   ( 1'b1 ),
        .dataslot_requestwrite_ack ( 1'b1 ),
        .dataslot_requestwrite_ok  ( 1'b1 ),
        .dataslot_update        ( dataslot_update ),
        .dataslot_update_id     ( dataslot_update_id ),
        .dataslot_update_size   ( dataslot_update_size ),
        .dataslot_allcomplete   ( dataslot_allcomplete ),
        .savestate_supported    ( 1'b0 ),
        .savestate_addr         ( 32'd0 ),
        .savestate_size         ( 32'd0 ),
        .savestate_maxloadsize  ( 32'd0 ),
        .savestate_start_ack    ( 1'b0 ),
        .savestate_start_busy   ( 1'b0 ),
        .savestate_start_ok     ( 1'b0 ),
        .savestate_start_err    ( 1'b0 ),
        .savestate_load_ack     ( 1'b0 ),
        .savestate_load_busy    ( 1'b0 ),
        .savestate_load_ok      ( 1'b0 ),
        .savestate_load_err     ( 1'b0 ),
        .target_dataslot_read     ( bd_target_read ),
        .target_dataslot_write    ( bd_target_write ),
        .target_dataslot_getfile  ( 1'b0 ),
        .target_dataslot_openfile ( 1'b0 ),
        .target_dataslot_ack      ( target_ack ),
        .target_dataslot_done     ( target_done ),
        .target_dataslot_err      ( target_err ),
        .target_dataslot_id         ( bd_target_id ),
        .target_dataslot_slotoffset ( bd_target_off ),
        .target_dataslot_bridgeaddr ( bd_target_ba ),
        .target_dataslot_length     ( bd_target_len ),
        .target_buffer_param_struct ( 32'd0 ),
        .target_buffer_resp_struct  ( 32'd0 ),
        .datatable_addr         ( dt_addr ),
        .datatable_wren         ( dt_wren ),
        .datatable_data         ( dt_data ),
        .datatable_q            ( dt_q )
    );

    // ---- AMNT scanner (verbatim block from core_top.sv) -----------------
    wire        bd_dsu;
    wire [15:0] bd_dsu_id;
    wire [31:0] bd_dsu_size;
    wire [31:0] dbg_amnt;

    amnt_wrap scanner (
        .clk_74a              ( clk74 ),
        .dataslot_update      ( dataslot_update ),
        .dataslot_update_id   ( dataslot_update_id ),
        .dataslot_update_size ( dataslot_update_size ),
        .dataslot_allcomplete ( dataslot_allcomplete ),
        .datatable_addr       ( dt_addr ),
        .datatable_wren       ( dt_wren ),
        .datatable_data       ( dt_data ),
        .datatable_q          ( dt_q ),
        .jmnt_active_ext      ( 1'b0 ),
        .o_bd_dsu             ( bd_dsu ),
        .o_bd_dsu_id          ( bd_dsu_id ),
        .o_bd_dsu_size        ( bd_dsu_size ),
        .o_dbg_amnt           ( dbg_amnt )
    );

    // ---- apf_blockdev ---------------------------------------------------
    reg         bd_reset_n = 1'b0;
    wire [2:0]  img_mounted;
    wire [31:0] img_size;
    wire        dio_download;
    wire [7:0]  dio_index;
    wire [24:0] dio_addr;
    wire [15:0] dio_data;
    wire        dio_wr;
    reg         dio_ack    = 1'b0;
    reg         flp_allow  = 1'b0;
    reg  [1:0]  ackdel     = 2'd0;

    // Emulate the machine's SDRAM retire: ack each held dio_wr after 2 cycles.
    always @(posedge clksys) begin
        dio_ack <= 1'b0;
        if (dio_wr && !dio_ack) begin
            if (ackdel == 2'd2) begin ackdel <= 2'd0; dio_ack <= 1'b1; end
            else ackdel <= ackdel + 2'd1;
        end else ackdel <= 2'd0;
    end

    apf_blockdev #( .BUF_BASE(32'h4000_0000) ) blockdev (
        .clk_74a        ( clk74 ),
        .reset_n        ( bd_reset_n ),
        .bridge_addr    ( bridge_addr ),
        .bridge_wr      ( bridge_wr ),
        .bridge_wr_data ( bridge_wr_data ),
        .bridge_rd_data ( ),
        .dataslot_update      ( bd_dsu ),
        .dataslot_update_id   ( bd_dsu_id ),
        .dataslot_update_size ( bd_dsu_size ),
        .target_dataslot_read       ( bd_target_read ),
        .target_dataslot_write      ( bd_target_write ),
        .target_dataslot_ack        ( target_ack ),
        .target_dataslot_done       ( target_done ),
        .target_dataslot_err        ( target_err ),
        .target_dataslot_id         ( bd_target_id ),
        .target_dataslot_slotoffset ( bd_target_off ),
        .target_dataslot_bridgeaddr ( bd_target_ba ),
        .target_dataslot_length     ( bd_target_len ),
        .slot0_id       ( 16'd310 ),
        .slot1_id       ( 16'd311 ),
        .slot_cd_id     ( 16'd320 ),
        .slot_flp_id    ( 16'd210 ),
        .dio_download   ( dio_download ),
        .dio_index      ( dio_index ),
        .dio_addr       ( dio_addr ),
        .dio_data       ( dio_data ),
        .dio_wr         ( dio_wr ),
        .dio_ack        ( dio_ack ),
        .flp_allow      ( flp_allow ),     // 0 until the copy phase
        .clk_sys        ( clksys ),
        .sd_lba0        ( 32'd0 ),
        .sd_lba1        ( 32'd0 ),
        .sd_lba2        ( 32'd0 ),
        .sd_rd          ( 3'b000 ),
        .sd_wr          ( 3'b000 ),
        .sd_ack         ( ),
        .sd_buff_addr   ( ),
        .sd_buff_dout   ( ),
        .sd_buff_wr     ( ),
        .sd_buff_din0   ( 16'd0 ),
        .sd_buff_din1   ( 16'd0 ),
        .img_mounted    ( img_mounted ),
        .img_size       ( img_size ),
        .slot_pram_id   ( 16'd220 ),
        .pram_save_req  ( 1'b0 ),
        .pram_load_addr ( ),
        .pram_load_data ( ),
        .pram_load_wr   ( ),
        .pram_save_addr ( ),
        .pram_save_data ( 8'd0 ),
        .pram_loaded    ( ),
        .dbg_stage      ( ),
        .dbg_cstate     ( ),
        .dbg_bdst       ( ),
        .dbg_bdw0       ( ),
        .dbg_bdlb       ( ),
        .dbg_bdwr       ( ),
        .dbg_bdww       ( )
    );

    // ---- mount observers (clk_sys, like the machine) --------------------
    integer m0_cnt = 0, m1_cnt = 0, m2_cnt = 0;
    reg [31:0] m0_size = 0, m2_size = 0, m0_size_last = 0;
    always @(posedge clksys) begin
        if (img_mounted[0]) begin
            m0_cnt = m0_cnt + 1;
            if (m0_cnt == 1) m0_size = img_size;
            m0_size_last = img_size;
            $display("[%0t] MOUNT slot0 (310)  img_size=%0d", $time, img_size);
        end
        if (img_mounted[1]) begin
            m1_cnt = m1_cnt + 1;
            $display("[%0t] MOUNT slot1 (311)  img_size=%0d  ** UNEXPECTED", $time, img_size);
        end
        if (img_mounted[2]) begin
            m2_cnt = m2_cnt + 1;
            m2_size = img_size;
            $display("[%0t] MOUNT slot2 (320)  img_size=%0d", $time, img_size);
        end
    end

    // dsu event trace (clk_74a)
    reg dsu_d = 0;
    always @(posedge clk74) begin
        dsu_d <= bd_dsu;
        if (bd_dsu && !dsu_d)
            $display("[%0t] dsu edge: id=%0d size=%0d", $time, bd_dsu_id, bd_dsu_size);
    end

    // ---- floppy copy observers (clk_sys, mirrors the machine's sampler) --
    integer     dio_words = 0;
    integer     dio_content_errs = 0;
    reg  [24:0] dio_first_addr = 25'h1FFFFFF;
    reg  [24:0] dio_end_addr   = 25'h1FFFFFF;
    reg  [15:0] dio_word0      = 16'h0;
    reg  [15:0] dio_expect;
    reg         dl_d = 0;
    always @(posedge clksys) begin
        dl_d <= dio_download;
        if (dio_wr && dio_ack) begin
            if (dio_words == 0) begin dio_first_addr <= dio_addr; dio_word0 <= dio_data; end
            // Full-content check against the server's pattern: byte at
            // in-sector offset o of sector s = (s + o) mod 256. Words are
            // {even byte, odd byte}; dio_addr is the file BYTE address.
            dio_expect[15:8] = dio_addr[24:9] + {1'b0, dio_addr[8:0]};        // sector + even offset
            dio_expect[7:0]  = dio_addr[24:9] + {1'b0, dio_addr[8:0]} + 8'd1; // odd byte
            if (dio_data !== dio_expect) begin
                if (dio_content_errs < 5)
                    $display("[%0t] CONTENT MISMATCH addr=%0d got=%04x want=%04x",
                             $time, dio_addr, dio_data, dio_expect);
                dio_content_errs = dio_content_errs + 1;
            end
            dio_words <= dio_words + 1;
        end
        // The machine samples dio_addr in the cycle it observes the fall --
        // identical convention to mac_lc_pocket's classifier.
        if (dl_d && !dio_download) begin
            dio_end_addr <= dio_addr;
            $display("[%0t] download END: dio_addr=%0d words=%0d", $time, dio_addr, dio_words);
        end
    end

    // ---- "OS" target-read server (floppy copy phase) ---------------------
    // Serves every target_dataslot_read: payload into the sector buffer at
    // BUF_BASE over the bridge, then the 'bu' ack and 'ok' done markers into
    // target_0 -- the real OS protocol against the real core_bridge_cmd.
    reg        serve_en  = 1'b0;
    integer    serve_cnt = 0;
    integer    sw, sb;
    reg [7:0]  pb0, pb1, pb2, pb3;
    initial begin : os_server
        forever begin
            @(posedge clk74);
            if (serve_en && bd_target_read) begin
                repeat (8) @(posedge clk74);   // let icb post the command
                // 512 bytes = 128 bridge words; file byte j of sector s =
                // (s + j) mod 256. Bridge words are big-endian (byte0 high).
                for (sw = 0; sw < 128; sw = sw + 1) begin
                    sb  = serve_cnt + 4*sw;
                    pb0 = sb[7:0]; pb1 = sb[7:0] + 8'd1;
                    pb2 = sb[7:0] + 8'd2; pb3 = sb[7:0] + 8'd3;
                    bwr(32'h40000000 + sw*4, {pb0, pb1, pb2, pb3});
                end
                bwr(32'hF8001000, 32'h62750000);          // 'bu' -> ack
                wait (!bd_target_read);
                bwr(32'hF8001000, 32'h6F6B0000);          // 'ok' -> done, err=0
                serve_cnt = serve_cnt + 1;
            end
        end
    end

    // ---- OS bridge write ------------------------------------------------
    task bwr(input [31:0] a, input [31:0] d);
    begin
        @(posedge clk74); #1;
        bridge_addr    = a;
        bridge_wr_data = d;
        bridge_wr      = 1;
        @(posedge clk74); #1;
        bridge_wr      = 0;
        @(posedge clk74); #1;   // hold addr/data through the registered wren
    end
    endtask

    integer errors = 0;
    // !== so an X never reads as a pass
    task check(input cond, input [8*60:1] msg);
    begin
        if (cond !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: %0s", msg);
        end else
            $display("pass: %0s", msg);
    end
    endtask

    initial begin
        repeat (20) @(posedge clk74);
        bd_reset_n = 1;
        repeat (10) @(posedge clk74);

        // 1. the OS populates the data slot table (data.json order)
        bwr(32'hF8002000, 32'd200);  bwr(32'hF8002004, 32'd524288);
        bwr(32'hF8002008, 32'd210);  bwr(32'hF800200C, 32'd819200);
        bwr(32'hF8002010, 32'd310);  bwr(32'hF8002014, 32'd41992192);
        bwr(32'hF8002018, 32'd311);  bwr(32'hF800201C, 32'd0);
        bwr(32'hF8002020, 32'd320);  bwr(32'hF8002024, 32'd7112704);

        // dio_download has no initializer in apf_blockdev (powers up 0 on the
        // FPGA, X here until the first mntF) -- "not raised" is the honest form
        check(dio_download !== 1'b1, "no floppy download before allcomplete");
        check(m0_cnt == 0,           "no mount before allcomplete");

        // 2. 0x008F Data slot access all complete (reset still held: never
        //    sent 0x0011 -- os_reset_n stays low, matching the real launch)
        bwr(32'hF8000000, 32'h434D008F);

        // settle (1023) + scan + fires; generous margin
        repeat (8000) @(posedge clk74);
        repeat (20)   @(posedge clksys);

        $display("--- after launch scan: dbg_amnt=%08x ---", dbg_amnt);
        check(m0_cnt == 1,               "exactly one slot0 mount from scan");
        check(m0_size == 32'd41992192,   "slot0 mount size = 41992192");
        check(m2_cnt == 1,               "exactly one slot2 (CD) mount from scan");
        check(m2_size == 32'd7112704,    "slot2 mount size = 7112704");
        check(m1_cnt == 0,               "slot1 (311, size 0) never mounted");
        check(dio_download == 1'b1,      "floppy mount latched (download raised)");
        check(dio_index == 8'd1,         "floppy dio_index = 1");
        check(dbg_amnt[27] == 1'b1,      "AMNT armed/ran");
        check(dbg_amnt[26:24] == 3'd7,   "AMNT parked in A_DONE");
        check(dbg_amnt[31:28] == 4'd3,   "AMNT fired 3 events (210,310,320)");

        // 3. allcomplete re-rise must NOT re-run the scan
        bwr(32'hF8000020, 32'd310);
        bwr(32'hF8000000, 32'h434D0080);   // request-read: clears allcomplete
        repeat (50) @(posedge clk74);
        bwr(32'hF8000000, 32'h434D008F);   // second rising edge
        repeat (8000) @(posedge clk74);
        repeat (20)   @(posedge clksys);
        check(m0_cnt == 1, "no duplicate mounts after second allcomplete");
        check(m2_cnt == 1, "no duplicate CD mount after second allcomplete");

        // 4. real OSD pick still swap-mounts: 0x008A slot 310, new size
        bwr(32'hF8000020, 32'd310);
        bwr(32'hF8000024, 32'd786473472);
        bwr(32'hF8000000, 32'h434D008A);
        repeat (200) @(posedge clk74);
        repeat (20)  @(posedge clksys);
        check(m0_cnt == 2,                    "OSD pick mounts slot0 again");
        check(m0_size_last == 32'd786473472,  "OSD mount carries the new size");

        // 5. FLOPPY COPY, end to end (the 2026-08-14 envelope fix).
        //    Re-mount slot 210 with a small 4-sector image so the launch
        //    scan's 819200-byte latch is replaced, then open the gate and
        //    serve the copy. The machine's classifier samples dio_addr at
        //    the download fall against the EXACT file size (MiSTer hps_io
        //    presents one-past on end) -- dio_end_addr must equal 2048.
        bwr(32'hF8000020, 32'd210);
        bwr(32'hF8000024, 32'd2048);
        bwr(32'hF8000000, 32'h434D008A);
        repeat (60) @(posedge clk74);
        serve_en  = 1'b1;
        flp_allow = 1'b1;
        // 4 sectors x (128 bridge words x ~3 clk74 + handshakes + drain)
        begin : wait_copy
            integer wi;
            for (wi = 0; wi < 200000; wi = wi + 1) begin
                @(posedge clksys);
                if (dl_d && !dio_download) disable wait_copy;
            end
        end
        repeat (100) @(posedge clksys);
        check(serve_cnt == 4,                 "OS served exactly 4 floppy sectors");
        check(dio_words == 1024,              "1024 dio words delivered (2048 bytes)");
        check(dio_first_addr == 25'd0,        "first dio_addr = 0");
        check(dio_word0 == 16'h0001,          "first dio word = file bytes 0,1");
        check(dio_end_addr == 25'd2048,       "END dio_addr = file SIZE (one-past; the fix)");
        check(dio_download == 1'b0,           "download envelope closed");
        check(dio_content_errs == 0,          "EVERY copied word content-exact");

        if (errors == 0) $display("=== TB PASS ===");
        else             $display("=== TB FAIL: %0d error(s) ===", errors);
        $finish;
    end

    initial begin
        #4_000_000;   // 4 ms guard
        $display("=== TB TIMEOUT ===");
        $finish;
    end

endmodule
