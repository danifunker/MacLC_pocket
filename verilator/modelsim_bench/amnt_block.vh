    localparam [2:0] A_IDLE = 3'd0,   // await first allcomplete rise
                     A_STLE = 3'd1,   // settle after allcomplete
                     A_RDID = 3'd2,   // read slot-id word (entry*2)
                     A_RDSZ = 3'd3,   // read size word (entry*2+1)
                     A_EVAL = 3'd4,   // known id + nonzero size?
                     A_FIRE = 3'd5,   // drive the synthesized update
                     A_GAP  = 3'd6,   // low gap so the next edge is clean
                     A_DONE = 3'd7;   // parked until reconfiguration

    reg  [2:0]  amnt_state = A_IDLE;
    reg         amnt_acp_d = 1'b0;
    reg         amnt_done  = 1'b0;
    reg  [9:0]  amnt_wait  = 10'd0;
    reg  [4:0]  amnt_entry = 5'd0;
    reg  [1:0]  amnt_lat   = 2'd0;
    reg  [15:0] amnt_id    = 16'd0;
    reg  [31:0] amnt_size  = 32'd0;
    reg  [9:0]  amnt_addr  = 10'd0;
    reg  [4:0]  amnt_hold  = 5'd0;
    reg  [3:0]  amnt_fired = 4'd0;    // AMNT probe: mounts synthesized
    wire [4:0]  amnt_next  = amnt_entry + 5'd1;
    wire        amnt_active = (amnt_hold != 5'd0);

    always @(posedge clk_74a) begin
        amnt_acp_d <= dataslot_allcomplete;
        if (amnt_hold != 5'd0) amnt_hold <= amnt_hold - 5'd1;

        case (amnt_state)
        A_IDLE: if (dataslot_allcomplete && !amnt_acp_d && !amnt_done) begin
            amnt_done  <= 1'b1;
            amnt_wait  <= 10'd1023;          // ~14 us; the table writes all
            amnt_state <= A_STLE;            // precede 0x008F, this is margin
        end
        A_STLE: begin
            amnt_entry <= 5'd0;
            if (amnt_wait != 10'd0) amnt_wait <= amnt_wait - 10'd1;
            else begin
                amnt_addr  <= 10'd0;         // entry 0, id word
                amnt_lat   <= 2'd2;
                amnt_state <= A_RDID;
            end
        end
        A_RDID: begin
            if (amnt_lat != 2'd0) amnt_lat <= amnt_lat - 2'd1;
            else begin
                amnt_id    <= datatable_q[15:0];
                amnt_addr  <= {4'd0, amnt_entry, 1'b1};
                amnt_lat   <= 2'd2;
                amnt_state <= A_RDSZ;
            end
        end
        A_RDSZ: begin
            if (amnt_lat != 2'd0) amnt_lat <= amnt_lat - 2'd1;
            else begin
                amnt_size  <= datatable_q;
                amnt_state <= A_EVAL;
            end
        end
        A_EVAL: begin
            if (amnt_size != 32'd0 &&
                (amnt_id == SLOT_HDD0 || amnt_id == SLOT_HDD1 ||
                 amnt_id == SLOT_CD   || amnt_id == SLOT_FLOPPY)) begin
                amnt_state <= A_FIRE;
            end else if (amnt_entry == 5'd31) begin
                amnt_state <= A_DONE;
            end else begin
                amnt_entry <= amnt_next;
                amnt_addr  <= {4'd0, amnt_next, 1'b0};
                amnt_lat   <= 2'd2;
                amnt_state <= A_RDID;
            end
        end
        A_FIRE: begin
            // Start driving only while the mux is quiet; a real update or a
            // JMNT injection landing mid-pulse would merge with ours (same
            // accepted overlap caveat as JMNT -- cannot happen at launch,
            // and the scanner never runs again after it).
            if (amnt_hold == 5'd0 && !dataslot_update && !jmnt_active) begin
                amnt_hold  <= 5'd15;
                amnt_fired <= amnt_fired + 4'd1;
            end else if (amnt_hold == 5'd1) begin
                amnt_wait  <= 10'd15;
                amnt_state <= A_GAP;
            end
        end
        A_GAP: begin
            if (amnt_wait != 10'd0) amnt_wait <= amnt_wait - 10'd1;
            else if (amnt_entry == 5'd31) amnt_state <= A_DONE;
            else begin
                amnt_entry <= amnt_next;
                amnt_addr  <= {4'd0, amnt_next, 1'b0};
                amnt_lat   <= 2'd2;
                amnt_state <= A_RDID;
            end
        end
        A_DONE: amnt_state <= A_DONE;        // parked until the next config
        default: amnt_state <= A_DONE;
        endcase
    end

    // Port A of the framework's data slot table RAM -- read-only scan use.
    // These three were undriven before; nothing else touches port A.
    assign datatable_addr = amnt_addr;
    assign datatable_wren = 1'b0;
    assign datatable_data = 32'd0;

    // AMNT probe word (decoded by scripts/read_bdst.tcl): quasi-static once
    // the scan parks in A_DONE, so the JTAG read needs no handshake.
    wire [31:0] dbg_amnt = { amnt_fired,        // [31:28] mounts synthesized
                             amnt_done,         // [27]    scan armed/ran
                             amnt_state,        // [26:24] 7 = done
                             3'd0, amnt_entry,  // [23:16] last entry scanned
                             amnt_id };         // [15:0]  last id read

    // Real bridge update > JMNT injection > launch scan.
    wire        bd_dsu       = dataslot_update | jmnt_active | amnt_active;
    wire [15:0] bd_dsu_id    = dataslot_update ? dataslot_update_id
                             : jmnt_active     ? jmnt_src[47:32]
                                               : amnt_id;
    wire [31:0] bd_dsu_size  = dataslot_update ? dataslot_update_size
                             : jmnt_active     ? jmnt_src[31:0]
                                               : amnt_size;
