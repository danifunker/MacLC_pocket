/*
 * Behavioral Egret for Mac LC
 *
 * Replaces the real 68HC05 CPU + Egret firmware with a simple state machine.
 * Handles: 68020 reset release, PRAM, RTC, ADB stubs, pseudo-commands.
 *
 * Protocol: VIA shift register with external clock (CB1 driven by Egret).
 *   Host→Egret: VIA mode 7 (shift out ext clk). VIA rotates SR on CB1 falling.
 *                CB2 = SR[7] always. Egret samples CB2 before each rising edge.
 *   Egret→Host: VIA mode 3 (shift in ext clk). VIA shifts CB2 into SR on CB1 rising.
 *                Egret drives CB2, then provides rising edge.
 *   Both: 8 rising edges per byte. After 8th rising, VIA sets IFR[2].
 *
 * Egret protocol signals (from Apple EgretMgr.a / egretequ.a):
 *   PB3 = xcvrSes (XCVR_SESSION) — Egret's session line
 *         Egret drives LOW (0) to indicate it has data to send
 *         HIGH (1) = idle / end of response
 *   PB4 = viaFull (VIA_FULL) — Host byte acknowledge
 *         Host drives HIGH (1) after reading each byte = "got it"
 *         Host drives LOW (0) when ready for next byte
 *   PB5 = sysSes (SYS_SESSION) — Host's session line
 *         Host drives HIGH (1) = session in progress
 *         Host drives LOW (0) = idle
 *
 * Signal mapping to module ports:
 *   cuda_treq=1 → PB3 pin LOW → xcvrSes asserted (Egret has data)
 *   via_tip (via_tip_latched) = PB5 value = sysSes
 *   via_byteack_in = PB4 value = viaFull
 */

module egret_behavioral (
    input  wire        clk,
    input  wire        clk8_en,
    input  wire        reset,

    // RTC timestamp
    input  wire [32:0] timestamp,

    // VIA Port B
    input  wire        via_tip,           // PB5 = sysSes (1=session active)
    input  wire        via_byteack_in,    // PB4 = viaFull (1=host ack'd byte)
    output wire        cuda_treq,         // PB3 inverted: 1=assert xcvrSes (pin LOW)
    output wire        cuda_byteack,

    // VIA Shift Register (CB1/CB2)
    output reg         cuda_cb1,
    input  wire        via_cb2_in,
    output reg         cuda_cb2,
    output reg         cuda_cb2_oe,

    // VIA SR control
    input  wire        via_sr_read,
    input  wire        via_sr_write,
    input  wire        via_sr_ext_clk,
    input  wire        via_sr_dir,       // 0=in (Egret→Host), 1=out (Host→Egret)
    output reg         cuda_sr_irq,

    // Full Port B (minimal)
    output wire [7:0]  cuda_portb,
    output wire [7:0]  cuda_portb_oe,

    // ADB
    input  wire        adb_data_in,
    output wire        adb_data_out,

    // System control
    output reg         reset_680x0,
    output reg         nmi_680x0,

    // Debug (match egret_wrapper interface)
    output wire        dbg_cen,
    output wire        dbg_port_test_done,
    output wire        dbg_handshake_done,
    output wire        dbg_treq,
    output wire        dbg_tip_in,
    output wire        dbg_byteack_in,
    output wire [7:0]  dbg_pb_out,
    output wire [7:0]  dbg_pc_out,
    output wire        dbg_cpu_running
);

    // =========================================================================
    // Constants
    // =========================================================================

    // Boot delay: ~8192 clk8_en ticks before releasing 68020 reset
    localparam BOOT_DELAY = 16'd8192;

    // CB1 half-period in clk8_en ticks (~4µs per half = ~125 kHz bit clock)
    localparam CB1_HALF_PERIOD = 6'd32;

    // Packet types
    localparam [7:0] PKT_ADB   = 8'h00;
    localparam [7:0] PKT_PSEUDO = 8'h01;
    localparam [7:0] PKT_ERROR = 8'h02;

    // Pseudo-command codes — full table from firmware jump table at $132D
    // 32 entries (0x00-0x1F), indexed by command byte
    localparam [7:0] CMD_WARM_START       = 8'h00;
    localparam [7:0] CMD_AUTOPOLL         = 8'h01;
    localparam [7:0] CMD_GET_6805_ADDR    = 8'h02;
    localparam [7:0] CMD_GET_TIME         = 8'h03;
    localparam [7:0] CMD_GET_PRAM         = 8'h04;  // Legacy PRAM read
    localparam [7:0] CMD_SET_PRAM_LEGACY  = 8'h05;  // Legacy PRAM write
    localparam [7:0] CMD_SET_ONLINE       = 8'h06;
    localparam [7:0] CMD_WR_PRAM          = 8'h07;  // Block PRAM write (was CMD_GET_PRAM)
    localparam [7:0] CMD_WR_XPRAM         = 8'h08;
    localparam [7:0] CMD_SET_TIME         = 8'h09;
    localparam [7:0] CMD_POWER_DOWN       = 8'h0A;
    localparam [7:0] CMD_POWER_CYCLE      = 8'h0B;
    localparam [7:0] CMD_SET_PRAM         = 8'h0C;
    localparam [7:0] CMD_SET_AUTOPOWER    = 8'h0D;
    localparam [7:0] CMD_SEND_DFAC        = 8'h0E;
    localparam [7:0] CMD_READ_DFAC        = 8'h0F;
    localparam [7:0] CMD_POWER_OFF        = 8'h10;
    localparam [7:0] CMD_RESET_SYSTEM     = 8'h11;
    localparam [7:0] CMD_SET_IPL          = 8'h12;
    localparam [7:0] CMD_SET_FILE_SERVER  = 8'h13;
    localparam [7:0] CMD_SET_AUTO_RATE    = 8'h14;
    localparam [7:0] CMD_RD_XPRAM         = 8'h15;  // Read Extended PRAM block
    localparam [7:0] CMD_GET_AUTO_RATE    = 8'h16;
    localparam [7:0] CMD_SET_POLL_RATE    = 8'h17;
    localparam [7:0] CMD_GET_POLL_RATE    = 8'h18;
    localparam [7:0] CMD_SET_DEV_LIST     = 8'h19;
    localparam [7:0] CMD_GET_DEV_LIST     = 8'h1A;
    localparam [7:0] CMD_SET_ONE_SEC      = 8'h1B;
    localparam [7:0] CMD_SET_WAKEUP       = 8'h1C;
    localparam [7:0] CMD_GET_WAKEUP       = 8'h1D;

    // =========================================================================
    // State machine
    // =========================================================================

    // Receive states (host → Egret)
    localparam [3:0] ST_BOOT          = 4'd0;
    localparam [3:0] ST_IDLE          = 4'd1;
    localparam [3:0] ST_RECV_START    = 4'd2;
    localparam [3:0] ST_RECV_CLOCK    = 4'd3;
    localparam [3:0] ST_RECV_DONE     = 4'd4;
    localparam [3:0] ST_PROCESS       = 4'd5;
    // Send states (Egret → host) — Egret protocol with xcvrSes/viaFull/sysSes
    localparam [3:0] ST_SEND_ATTN     = 4'd6;  // Clock attention byte, wait for sysSes
    localparam [3:0] ST_SEND_WAIT_ACK = 4'd7;  // Wait for viaFull ack from host
    localparam [3:0] ST_SEND_CLOCK    = 4'd8;  // Clock 8 bits out via CB1/CB2
    localparam [3:0] ST_SEND_WAIT_VIAFULL = 4'd9;  // Wait for host to set viaFull after byte
    localparam [3:0] ST_FINISH        = 4'd10;

    reg [3:0]  state;

    // =========================================================================
    // Registers
    // =========================================================================

    // Synchronizer for inputs
    reg [2:0] tip_sync;
    wire      tip = tip_sync[2];        // sysSes: 1=session active
    reg       tip_prev;

    reg [2:0] viafull_sync;
    wire      viafull = viafull_sync[2]; // viaFull: 1=host ack'd byte
    reg       viafull_prev;

    // Edge detection
    reg       sr_write_prev;
    reg       sr_read_prev;

    // Boot counter
    reg [15:0] boot_counter;

    // CB1 clock divider
    reg [5:0]  clk_div;

    // Shift state
    reg [7:0]  shift_data;
    reg [3:0]  bit_count;       // 0..8 for clocking, counts rising edges
    reg        sample_phase;    // 0 = drive CB2/sample, 1 = rising edge

    // Buffers
    reg [7:0]  recv_buf [0:23];
    reg [4:0]  recv_count;
    reg [7:0]  send_buf [0:39];
    reg [5:0]  send_count;
    reg [5:0]  send_length;

    // xcvrSes output (active-high = pulling PB3 pin low = "I have data")
    reg        treq_reg;

    // Wait counter for timeouts
    reg [15:0] wait_counter;

    // SR write pending (host wrote SR, needs clocking)
    reg        sr_write_pending;

    // PRAM
    reg [7:0]  pram [0:255];

    // RTC
    localparam [31:0] MAC_UNIX_DELTA = 32'd2082844800;
    reg [31:0] rtc_seconds;
    reg [23:0] rtc_tick;
    reg        rtc_init;

    // Autopoll state
    reg        autopoll_enabled;
    reg [7:0]  auto_rate;       // ADB auto-poll rate (default 0x0B = 11)
    reg [7:0]  poll_rate;       // ADB poll rate

    // ADB device state — keyboard at addr 2, mouse at addr 3
    reg [15:0] adb_reg3 [0:15]; // Register 3 (handler ID) for each ADB address
    reg [15:0] adb_dev_list;    // Device presence bitmap

    // DFAC (sound chip I2C) register storage
    reg [7:0]  dfac_regs [0:7];
    reg [3:0]  dfac_count;      // Number of stored DFAC bytes

    // OneSecond mode
    reg [1:0]  onesec_mode;     // 0=off, 1=time, 2=OK, 3=PRAM tick
    reg [23:0] onesec_counter;
    reg        onesec_pending;  // 1Hz tick has fired, waiting to send

    // Misc state flags
    reg        online_flag;
    reg        file_server_flag;
    reg        wakeup_enabled;
    reg [31:0] autopower_time;  // Wake-up alarm (Mac seconds)

    // Reset pulse state
    reg [15:0] reset_pulse_counter;
    reg        reset_pulsing;

    // =========================================================================
    // Output assignments
    // =========================================================================

    assign cuda_treq     = treq_reg;       // 1 = assert xcvrSes (PB3 pin LOW)
    assign cuda_byteack  = 1'b0;           // Not used for Egret
    assign cuda_portb    = {2'b11, 1'b0, treq_reg, 4'b1111};
    assign cuda_portb_oe = 8'b00001000;    // Only xcvrSes/TREQ is output
    assign adb_data_out  = 1'b1;

    // Debug
    assign dbg_cen             = clk8_en;
    assign dbg_port_test_done  = (state != ST_BOOT);
    assign dbg_handshake_done  = (state != ST_BOOT);
    assign dbg_treq            = treq_reg;
    assign dbg_tip_in          = tip;
    assign dbg_byteack_in      = viafull;
    assign dbg_pb_out          = cuda_portb;
    assign dbg_pc_out          = {4'b0, state};
    assign dbg_cpu_running     = (state != ST_BOOT);

    // =========================================================================
    // PRAM init
    // =========================================================================

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            pram[i] = 8'h00;
        pram[8'h08] = 8'h00;
        pram[8'h09] = 8'h08;
        pram[8'h0C] = 8'h4E;  // Extended PRAM validity 'N'
        pram[8'h0D] = 8'h75;  // Extended PRAM validity 'u'
        pram[8'h0E] = 8'h4D;  // Extended PRAM validity 'M'
        pram[8'h0F] = 8'h63;  // Extended PRAM validity 'c'
        pram[8'h10] = 8'hA8;  // SPValid
        pram[8'h13] = 8'h22;  // SPConfig: both ports useAsync (AppleTalk inactive)
        pram[8'h78] = 8'h07;  // Volume
        pram[8'h7C] = 8'hA8;  // PRAM signature
        pram[8'h7D] = 8'h00;
        pram[8'h7E] = 8'h00;
        pram[8'h7F] = 8'h01;

        // ADB device register 3 defaults: keyboard at 2, mouse at 3
        for (i = 0; i < 16; i = i + 1)
            adb_reg3[i] = 16'h0000;
        adb_reg3[2] = 16'h0201;  // Keyboard: addr 2, handler 1
        adb_reg3[3] = 16'h0301;  // Mouse: addr 3, handler 1

        // DFAC init
        for (i = 0; i < 8; i = i + 1)
            dfac_regs[i] = 8'h00;
        dfac_count = 4'd0;
    end

    // =========================================================================
    // Main state machine
    //
    // Egret protocol (from Apple EgretMgr.a):
    //
    // HOST SEND (command):
    //   1. Host asserts sysSes (PB5=1), sets VIA to shift-out, writes SR, sets viaFull
    //   2. Egret clocks byte via CB1 edges, host waits for IFR[2]
    //   3. Host clears viaFull, delays, writes next byte, sets viaFull
    //   4. After last byte: host clears sysSes + viaFull
    //
    // HOST RECEIVE (response via ShiftRegIRQ):
    //   1. Egret asserts xcvrSes (PB3=0) = "I have data"
    //   2. Egret clocks attention byte via CB1 → VIA SR IRQ fires
    //   3. Host reads vSR (clears IFR[2]), delays 100us (first byte = no viaFull ack)
    //   4. Host asserts sysSes (PB5=1) = "OK, continue sending"
    //   5. Egret clocks next byte → VIA SR IRQ
    //   6. Host reads vSR, sets viaFull (PB4=1) = "got it", delays, clears viaFull
    //   7. Host checks xcvrSes: if PB3=1 (HIGH) → Egret done, go to @done
    //   8. If more bytes: return from ISR, Egret clocks next byte
    //   9. @done: host clears viaFull, clears sysSes, delays
    //
    // HOST RECEIVE (register-based, during boot via SendEgretCmd):
    //   1. Egret clocks attention byte → host polls IFR[2], reads vSR (discard)
    //   2. Host delays, asserts sysSes (PB5=1)
    //   3. Egret clocks data byte → host polls IFR[2]
    //   4. Host sets viaFull (PB4=1), reads vSR, delays, clears viaFull
    //   5. Host checks xcvrSes (PB3) — if HIGH, done
    //   6. Repeat from 3
    //   7. When done: host clears sysSes
    //
    // =========================================================================

    always @(posedge clk) begin
        if (reset) begin
            state          <= ST_BOOT;
            tip_sync       <= 3'b000;
            tip_prev       <= 1'b0;
            viafull_sync   <= 3'b000;
            viafull_prev   <= 1'b0;
            sr_write_prev  <= 1'b0;
            sr_read_prev   <= 1'b0;
            boot_counter   <= 16'd0;
            reset_680x0    <= 1'b1;   // Hold 68020 in reset
            nmi_680x0      <= 1'b0;
            treq_reg       <= 1'b0;
            cuda_cb1       <= 1'b0;
            cuda_cb2       <= 1'b0;
            cuda_cb2_oe    <= 1'b0;
            cuda_sr_irq    <= 1'b0;
            clk_div        <= 6'd0;
            bit_count      <= 4'd0;
            sample_phase   <= 1'b0;
            shift_data     <= 8'd0;
            recv_count     <= 5'd0;
            send_count     <= 6'd0;
            send_length    <= 6'd0;
            wait_counter   <= 16'd0;
            sr_write_pending <= 1'b0;
            rtc_seconds    <= 32'd0;
            rtc_tick       <= 24'd0;
            rtc_init       <= 1'b0;
            autopoll_enabled <= 1'b0;
            auto_rate      <= 8'h0B;
            poll_rate      <= 8'h00;
            adb_dev_list   <= 16'h000C; // Devices at addr 2 (keyboard) and 3 (mouse)
            onesec_mode    <= 2'd0;
            onesec_counter <= 24'd0;
            onesec_pending <= 1'b0;
            online_flag    <= 1'b0;
            file_server_flag <= 1'b0;
            wakeup_enabled <= 1'b0;
            autopower_time <= 32'd0;
            reset_pulse_counter <= 16'd0;
            reset_pulsing  <= 1'b0;

        end else if (clk8_en) begin
            // Synchronize inputs
            tip_sync     <= {tip_sync[1:0], via_tip};
            tip_prev     <= tip;
            viafull_sync <= {viafull_sync[1:0], via_byteack_in};
            viafull_prev <= viafull;
            sr_write_prev <= via_sr_write;
            sr_read_prev  <= via_sr_read;

            // Default: clear one-shot signals
            cuda_sr_irq <= 1'b0;

            // RTC
            if (!rtc_init && timestamp != 0) begin
                rtc_seconds <= timestamp[31:0] + MAC_UNIX_DELTA;
                rtc_init    <= 1'b1;
            end else begin
                if (rtc_tick >= 24'd7_999_999) begin
                    rtc_tick    <= 24'd0;
                    rtc_seconds <= rtc_seconds + 1'd1;
                end else begin
                    rtc_tick <= rtc_tick + 1'd1;
                end
            end

            // Track SR write from host
            if (via_sr_write && !sr_write_prev)
                sr_write_pending <= 1'b1;

            // Reset pulse: assert for ~8192 ticks then deassert and re-release 68020
            if (reset_pulsing) begin
                reset_pulse_counter <= reset_pulse_counter + 1'd1;
                if (reset_pulse_counter >= 16'd8192) begin
                    reset_680x0    <= 1'b0;
                    reset_pulsing  <= 1'b0;
                end
            end

            // 1Hz tick for OneSecondMode async notifications
            if (onesec_mode != 2'd0) begin
                if (onesec_counter >= 24'd7_999_999) begin
                    onesec_counter <= 24'd0;
                    if (state == ST_IDLE && !onesec_pending)
                        onesec_pending <= 1'b1;
                end else begin
                    onesec_counter <= onesec_counter + 1'd1;
                end
            end

            // ---- State machine ----
            case (state)

            // ==== BOOT: hold 68020 in reset, then release ====
            ST_BOOT: begin
                boot_counter <= boot_counter + 1'd1;
                if (boot_counter == BOOT_DELAY) begin
                    reset_680x0 <= 1'b0;  // Release 68020
`ifdef SIMULATION
                    $display("EGRET_BEH: Released 68020 reset at tick %0d", boot_counter);
`endif
                end
                if (boot_counter >= BOOT_DELAY + 16'd100) begin
                    state <= ST_IDLE;
`ifdef SIMULATION
                    $display("EGRET_BEH: Entering IDLE");
`endif
                end
            end

            // ==== IDLE: wait for host to assert sysSes (start transaction) ====
            ST_IDLE: begin
                treq_reg    <= 1'b0;   // xcvrSes deasserted (PB3=1, idle)
                cuda_cb1    <= 1'b0;
                cuda_cb2_oe <= 1'b0;
                recv_count  <= 4'd0;
                send_count  <= 4'd0;

                // Host asserts sysSes (PB5=1) → start receiving command
                if (tip && !tip_prev) begin
                    state        <= ST_RECV_START;
                    wait_counter <= 16'd0;
                    sr_write_pending <= 1'b0;
`ifdef SIMULATION
                    $display("EGRET_BEH: sysSes asserted, entering RECV_START");
`endif
                end
                // 1Hz async notification (OneSecondMode)
                else if (onesec_pending && !tip) begin
                    onesec_pending <= 1'b0;
                    send_count  <= 6'd0;
                    send_buf[0] <= PKT_PSEUDO;
                    send_buf[1] <= 8'h00;
                    send_buf[2] <= CMD_GET_TIME;
                    send_buf[3] <= rtc_seconds[31:24];
                    send_buf[4] <= rtc_seconds[23:16];
                    send_buf[5] <= rtc_seconds[15:8];
                    send_buf[6] <= rtc_seconds[7:0];
                    send_length <= 6'd7;
                    treq_reg      <= 1'b1;
                    state         <= ST_SEND_ATTN;
                    clk_div       <= 6'd0;
                    bit_count     <= 4'd0;
                    sample_phase  <= 1'b0;
                    shift_data    <= 8'h01;
                    cuda_cb2      <= 1'b0;
                    cuda_cb2_oe   <= 1'b1;
                    cuda_cb1      <= 1'b0;
                    wait_counter  <= 16'd0;
`ifdef SIMULATION
                    $display("EGRET_BEH: 1Hz tick, sending async time notification");
`endif
                end
            end

            // ==== RECV_START: wait for host to write SR (viaFull set) ====
            ST_RECV_START: begin
                wait_counter <= wait_counter + 1'd1;

                if (sr_write_pending) begin
                    // Host wrote SR, start clocking
                    sr_write_pending <= 1'b0;
                    state        <= ST_RECV_CLOCK;
                    clk_div      <= 6'd0;
                    bit_count    <= 4'd0;
                    sample_phase <= 1'b0;
                    shift_data   <= 8'd0;
                    cuda_cb1     <= 1'b0;
`ifdef SIMULATION
                    $display("EGRET_BEH: SR written, entering RECV_CLOCK (byte %0d)", recv_count);
`endif
                end else if (!tip) begin
                    // sysSes deasserted — end of command packet
                    if (recv_count > 0) begin
                        state <= ST_PROCESS;
`ifdef SIMULATION
                        $display("EGRET_BEH: sysSes deasserted in RECV_START, processing %0d bytes", recv_count);
`endif
                    end else begin
                        state <= ST_IDLE;
                    end
                end else if (wait_counter >= 16'd50000) begin
                    if (recv_count > 0)
                        state <= ST_PROCESS;
                    else
                        state <= ST_IDLE;
                end
            end

            // ==== RECV_CLOCK: clock 8 bits from VIA SR (mode 7 = shift out ext) ====
            ST_RECV_CLOCK: begin
                clk_div <= clk_div + 1'd1;

                if (clk_div >= CB1_HALF_PERIOD) begin
                    clk_div <= 6'd0;

                    if (!sample_phase) begin
                        // Phase 0: Sample CB2 (data bit), raise CB1
                        shift_data <= {shift_data[6:0], via_cb2_in};
                        sample_phase <= 1'b1;
                        cuda_cb1 <= 1'b1;
                        bit_count <= bit_count + 1'd1;
`ifdef SIMULATION
                        $display("EGRET_BEH: RECV bit[%0d] cb2=%b shift=0x%02x (byte %0d)",
                                 bit_count, via_cb2_in, {shift_data[6:0], via_cb2_in}, recv_count);
`endif
                    end else begin
                        // Phase 1: Lower CB1 (falling edge → VIA rotates SR)
                        cuda_cb1 <= 1'b0;
                        sample_phase <= 1'b0;

                        if (bit_count >= 4'd8) begin
                            recv_buf[recv_count] <= shift_data;
                            recv_count <= recv_count + 1'd1;
                            state <= ST_RECV_DONE;
                            wait_counter <= 16'd0;
`ifdef SIMULATION
                            $display("EGRET_BEH: RECV byte[%0d] = 0x%02x", recv_count, shift_data);
`endif
                        end
                    end
                end
            end

            // ==== RECV_DONE: wait for host to ack (viaFull toggle or SR write) ====
            // In Egret protocol, host does viaFullAck (set PB4) then clears it.
            // Or host writes next byte to SR. Or host deasserts sysSes.
            ST_RECV_DONE: begin
                wait_counter <= wait_counter + 1'd1;

                if (!tip) begin
                    // sysSes deasserted → end of command packet
                    state <= ST_PROCESS;
`ifdef SIMULATION
                    $display("EGRET_BEH: sysSes deasserted after byte %0d, processing", recv_count);
`endif
                end else if (sr_write_pending) begin
                    // Host wrote next byte to SR
                    sr_write_pending <= 1'b0;
                    state        <= ST_RECV_CLOCK;
                    clk_div      <= 6'd0;
                    bit_count    <= 4'd0;
                    sample_phase <= 1'b0;
                    shift_data   <= 8'd0;
                    cuda_cb1     <= 1'b0;
                end else if (wait_counter >= 16'd50000) begin
                    state <= ST_PROCESS;
                end
            end

            // ==== PROCESS: decode command, build response ====
            ST_PROCESS: begin
`ifdef SIMULATION
                $display("EGRET_BEH: PROCESS pkt_type=0x%02x cmd=0x%02x recv_count=%0d",
                         recv_buf[0], recv_buf[1], recv_count);
`endif
                send_count  <= 6'd0;

                case (recv_buf[0])
                PKT_PSEUDO: begin
                    send_buf[0] <= PKT_PSEUDO;
                    send_buf[1] <= 8'h00;        // flags (success)
                    send_buf[2] <= recv_buf[1];  // command echo

                    case (recv_buf[1])
                    CMD_WARM_START: begin
                        // Reset internal state
                        autopoll_enabled <= 1'b0;
                        onesec_mode      <= 2'd0;
                        onesec_pending   <= 1'b0;
                        send_length <= 6'd3;
                    end

                    CMD_AUTOPOLL: begin
                        // recv_buf[2] = 0x00 to disable, non-zero to enable
                        autopoll_enabled <= (recv_buf[2] != 8'h00);
`ifdef SIMULATION
                        $display("EGRET_BEH: AUTOPOLL %s",
                                 recv_buf[2] != 8'h00 ? "ENABLED" : "DISABLED");
`endif
                        send_length <= 6'd3;
                    end

                    CMD_GET_6805_ADDR: begin
                        // Debug command: return 2 zero bytes (no real HC05)
                        send_buf[3] <= 8'h00;
                        send_buf[4] <= 8'h00;
                        send_length <= 6'd5;
                    end

                    CMD_GET_TIME: begin
                        send_buf[3] <= rtc_seconds[31:24];
                        send_buf[4] <= rtc_seconds[23:16];
                        send_buf[5] <= rtc_seconds[15:8];
                        send_buf[6] <= rtc_seconds[7:0];
                        send_length <= 6'd7;
                    end

                    CMD_GET_PRAM: begin
                        // Legacy PRAM read: recv_buf[2]=offset, recv_buf[3]=count
                        // Returns count bytes from PRAM starting at offset
                        begin : get_pram_block
                            integer j;
                            reg [7:0] pram_offset;
                            reg [7:0] pram_count;
                            pram_offset = recv_buf[2];
                            pram_count  = (recv_buf[3] == 8'h00) ? 8'd32 : recv_buf[3];
                            for (j = 0; j < 32; j = j + 1) begin
                                if (j[7:0] < pram_count)
                                    send_buf[3 + j] <= pram[pram_offset + j[7:0]];
                            end
                            send_length <= 6'd3 + {2'd0, pram_count[3:0]};
                        end
`ifdef SIMULATION
                        $display("EGRET_BEH: GET_PRAM offset=0x%02x count=%0d",
                                 recv_buf[2], recv_buf[3]);
`endif
                    end

                    CMD_SET_PRAM_LEGACY: begin
                        // Legacy PRAM write: recv_buf[2]=offset, recv_buf[3]=data
                        pram[recv_buf[2]] <= recv_buf[3];
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: SET_PRAM_LEGACY[0x%02x] = 0x%02x",
                                 recv_buf[2], recv_buf[3]);
`endif
                    end

                    CMD_SET_ONLINE: begin
                        online_flag <= (recv_buf[2] != 8'h00);
                        send_length <= 6'd3;
                    end

                    CMD_WR_PRAM: begin
                        // Block PRAM write: recv_buf[2]=flags, recv_buf[3]=offset, data at [4+]
                        // ROM calls with D1=32, expects 3 header + 32 data = 35 bytes
                        begin : wr_pram_block
                            integer j;
                            for (j = 0; j < 32; j = j + 1)
                                send_buf[3 + j] <= pram[recv_buf[3] + j[7:0]];
                        end
                        send_length <= 6'd35;
`ifdef SIMULATION
                        $display("EGRET_BEH: WR_PRAM (read) offset=0x%02x, sending 32 bytes",
                                 recv_buf[3]);
`endif
                    end

                    CMD_WR_XPRAM: begin
                        begin : wr_xpram_block
                            integer k;
                            for (k = 0; k < 20; k = k + 1) begin
                                if (4 + k < recv_count) begin
                                    if ((recv_buf[3] + k[7:0]) != 8'h13)
                                        pram[recv_buf[3] + k[7:0]] <= recv_buf[4 + k];
`ifdef SIMULATION
                                    else
                                        $display("EGRET_BEH: WR_XPRAM BLOCKED write to 0x13 (SPConfig), ROM wanted 0x%02x, keeping 0x%02x",
                                                 recv_buf[4 + k], pram[8'h13]);
`endif
                                end
                            end
                        end
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: WR_XPRAM offset=0x%02x count=%0d",
                                 recv_buf[3], recv_count - 5'd4);
`endif
                    end

                    CMD_SET_TIME: begin
                        // Packet: [0x01, 0x09, HH, HM, ML, LL]
                        rtc_seconds <= {recv_buf[2], recv_buf[3], recv_buf[4], recv_buf[5]};
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: SET_TIME = 0x%02x%02x%02x%02x",
                                 recv_buf[2], recv_buf[3], recv_buf[4], recv_buf[5]);
`endif
                    end

                    CMD_POWER_DOWN: begin
                        send_length <= 6'd3;
                    end

                    CMD_POWER_CYCLE: begin
                        send_length <= 6'd3;
                    end

                    CMD_SET_PRAM: begin
                        // Single-byte PRAM write: [0x01, 0x0C, offset, data]
                        // Protect SPConfig (0x13)
                        if (recv_buf[2] != 8'h13)
                            pram[recv_buf[2]] <= recv_buf[3];
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: SET_PRAM[0x%02x] = 0x%02x%s",
                                 recv_buf[2], recv_buf[3],
                                 recv_buf[2] == 8'h13 ? " (BLOCKED)" : "");
`endif
                    end

                    CMD_SET_AUTOPOWER: begin
                        // Store 4-byte alarm time
                        autopower_time <= {recv_buf[2], recv_buf[3], recv_buf[4], recv_buf[5]};
                        send_length <= 6'd3;
                    end

                    CMD_SEND_DFAC: begin
                        // Store DFAC data bytes from recv_buf[2..N]
                        begin : send_dfac_block
                            integer d;
                            for (d = 0; d < 8; d = d + 1) begin
                                if (2 + d < recv_count)
                                    dfac_regs[d] <= recv_buf[2 + d];
                            end
                            if (recv_count > 5'd2)
                                dfac_count <= recv_count[3:0] - 4'd2;
                            else
                                dfac_count <= 4'd0;
                        end
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: SEND_DFAC %0d bytes", recv_count - 5'd2);
`endif
                    end

                    CMD_READ_DFAC: begin
                        // Return stored DFAC data
                        begin : read_dfac_block
                            integer d;
                            for (d = 0; d < 8; d = d + 1)
                                send_buf[3 + d] <= dfac_regs[d];
                        end
                        send_length <= 6'd3 + {2'd0, dfac_count};
`ifdef SIMULATION
                        $display("EGRET_BEH: READ_DFAC returning %0d bytes", dfac_count);
`endif
                    end

                    CMD_POWER_OFF: begin
                        send_length <= 6'd3;
                    end

                    CMD_RESET_SYSTEM: begin
                        // Pulse reset: assert, then deassert after delay
                        reset_680x0         <= 1'b1;
                        reset_pulsing       <= 1'b1;
                        reset_pulse_counter <= 16'd0;
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: RESET_SYSTEM — pulsing 68020 reset");
`endif
                    end

                    CMD_SET_IPL: begin
                        // Store IPL level (not wired to pins in behavioral model)
                        send_length <= 6'd3;
                    end

                    CMD_SET_FILE_SERVER: begin
                        file_server_flag <= (recv_buf[2] != 8'h00);
                        send_length <= 6'd3;
                    end

                    CMD_SET_AUTO_RATE: begin
                        auto_rate <= recv_buf[2];
                        send_length <= 6'd3;
                    end

                    CMD_RD_XPRAM: begin
                        // Read Extended PRAM: recv_buf[2]=offset, recv_buf[3]=count
                        // Returns header + count bytes from PRAM
                        begin : rd_xpram_block
                            integer j;
                            reg [7:0] xp_offset;
                            reg [7:0] xp_count;
                            xp_offset = recv_buf[2];
                            xp_count  = recv_buf[3];
                            if (xp_count == 8'h00) xp_count = 8'd1;
                            if (xp_count > 8'd32) xp_count = 8'd32;
                            for (j = 0; j < 32; j = j + 1) begin
                                if (j[7:0] < xp_count)
                                    send_buf[3 + j] <= pram[xp_offset + j[7:0]];
                            end
                            send_length <= 6'd3 + {1'b0, xp_count[4:0]};
                        end
`ifdef SIMULATION
                        $display("EGRET_BEH: RD_XPRAM offset=0x%02x count=%0d",
                                 recv_buf[2], recv_buf[3]);
`endif
                    end

                    CMD_GET_AUTO_RATE: begin
                        send_buf[3] <= auto_rate;
                        send_length <= 6'd4;
                    end

                    CMD_SET_POLL_RATE: begin
                        poll_rate <= recv_buf[2];
                        send_length <= 6'd3;
                    end

                    CMD_GET_POLL_RATE: begin
                        send_buf[3] <= poll_rate;
                        send_length <= 6'd4;
                    end

                    CMD_SET_DEV_LIST: begin
                        adb_dev_list <= {recv_buf[2], recv_buf[3]};
                        send_length <= 6'd3;
                    end

                    CMD_GET_DEV_LIST: begin
                        send_buf[3] <= adb_dev_list[15:8];
                        send_buf[4] <= adb_dev_list[7:0];
                        send_length <= 6'd5;
                    end

                    CMD_SET_ONE_SEC: begin
                        // recv_buf[2]: 0=off, 1=time, 2=OK, 3=PRAM
                        onesec_mode    <= recv_buf[2][1:0];
                        onesec_counter <= 24'd0;
                        onesec_pending <= 1'b0;
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: SET_ONE_SEC mode=%0d", recv_buf[2]);
`endif
                    end

                    CMD_SET_WAKEUP: begin
                        wakeup_enabled <= (recv_buf[2] != 8'h00);
                        send_length <= 6'd3;
                    end

                    CMD_GET_WAKEUP: begin
                        send_buf[3] <= {7'd0, wakeup_enabled};
                        send_length <= 6'd4;
                    end

                    default: begin
                        send_length <= 6'd3;
`ifdef SIMULATION
                        $display("EGRET_BEH: Unknown pseudo-cmd 0x%02x, returning OK", recv_buf[1]);
`endif
                    end
                    endcase
                end

                PKT_ADB: begin
                    // ADB command dispatch
                    // recv_buf[1] = ADB command byte:
                    //   [7:4] = device address, [3:0] = command
                    //   0x0=SendReset, 0x1=Flush, 0x8-0xB=Listen R0-R3, 0xC-0xF=Talk R0-R3
                    begin : adb_dispatch
                        reg [3:0] adb_addr;
                        reg [3:0] adb_cmd;
                        adb_addr = recv_buf[1][7:4];
                        adb_cmd  = recv_buf[1][3:0];

                        send_buf[0] <= PKT_ADB;
                        send_buf[2] <= recv_buf[1];  // cmd echo

                        case (adb_cmd)
                        4'h0: begin
                            // SendReset — reset all ADB device registrations
                            send_buf[1] <= 8'h00;
                            send_length <= 6'd3;
`ifdef SIMULATION
                            $display("EGRET_BEH: ADB SendReset");
`endif
                        end

                        4'h1: begin
                            // Flush — clear pending data for device
                            send_buf[1] <= 8'h00;
                            send_length <= 6'd3;
`ifdef SIMULATION
                            $display("EGRET_BEH: ADB Flush addr=%0d", adb_addr);
`endif
                        end

                        4'hC, 4'hD, 4'hE, 4'hF: begin
                            // Talk R0-R3
                            if (adb_addr == 4'd2 || adb_addr == 4'd3) begin
                                // Device present (keyboard=2, mouse=3)
                                if (adb_cmd == 4'hF) begin
                                    // Talk R3 — return handler ID register
                                    send_buf[1] <= 8'h00;
                                    send_buf[3] <= adb_reg3[adb_addr][15:8];
                                    send_buf[4] <= adb_reg3[adb_addr][7:0];
                                    send_length <= 6'd5;
`ifdef SIMULATION
                                    $display("EGRET_BEH: ADB Talk R3 addr=%0d → 0x%04x",
                                             adb_addr, adb_reg3[adb_addr]);
`endif
                                end else begin
                                    // Talk R0/R1/R2 — no pending data
                                    // Return with SRQ timeout flag (no data available)
                                    send_buf[1] <= 8'h02;  // timeout/no data
                                    send_length <= 6'd3;
`ifdef SIMULATION
                                    $display("EGRET_BEH: ADB Talk R%0d addr=%0d → no data",
                                             adb_cmd - 4'hC, adb_addr);
`endif
                                end
                            end else begin
                                // No device at this address — SRQ timeout
                                send_buf[1] <= 8'h02;
                                send_length <= 6'd3;
`ifdef SIMULATION
                                $display("EGRET_BEH: ADB Talk R%0d addr=%0d → no device",
                                         adb_cmd - 4'hC, adb_addr);
`endif
                            end
                        end

                        4'h8, 4'h9, 4'hA, 4'hB: begin
                            // Listen R0-R3
                            if (adb_cmd == 4'hB && (adb_addr == 4'd2 || adb_addr == 4'd3)) begin
                                // Listen R3 — update handler ID
                                adb_reg3[adb_addr] <= {recv_buf[2], recv_buf[3]};
`ifdef SIMULATION
                                $display("EGRET_BEH: ADB Listen R3 addr=%0d ← 0x%02x%02x",
                                         adb_addr, recv_buf[2], recv_buf[3]);
`endif
                            end
                            send_buf[1] <= 8'h00;
                            send_length <= 6'd3;
                        end

                        default: begin
                            // Unknown/reserved ADB command
                            send_buf[1] <= 8'h02;
                            send_length <= 6'd3;
`ifdef SIMULATION
                            $display("EGRET_BEH: ADB unknown cmd 0x%01x addr=%0d",
                                     adb_cmd, adb_addr);
`endif
                        end
                        endcase
                    end
                end

                default: begin
                    send_buf[0] <= PKT_ERROR;
                    send_buf[1] <= 8'h00;
                    send_buf[2] <= recv_buf[1];
                    send_length <= 6'd3;
                end
                endcase

                // Begin response: assert xcvrSes (PB3 LOW) and clock attention byte
                // The attention byte ($01 for pseudo response) wakes up the host via SR IRQ.
                // In Egret protocol, the first byte clocked IS the notification — no separate
                // "SEND_NOTIFY" needed. The host ISR (or polling loop) picks it up.
                treq_reg      <= 1'b1;  // Assert xcvrSes = "I have data"
                state         <= ST_SEND_ATTN;
                clk_div       <= 6'd0;
                bit_count     <= 4'd0;
                sample_phase  <= 1'b0;
                // Attention byte = $01 (always, for Egret response)
                shift_data    <= 8'h01;
                cuda_cb2      <= 1'b1;  // MSB of $01 = 0... wait, $01 = 00000001, MSB=0
                cuda_cb2_oe   <= 1'b1;
                cuda_cb1      <= 1'b0;
                wait_counter  <= 16'd0;
`ifdef SIMULATION
                $display("EGRET_BEH: Starting response, asserting xcvrSes, clocking attn byte $01");
`endif
            end

            // ==== SEND_ATTN: Clock the attention byte ($01) ====
            // After 8 bits, VIA IFR[2] fires. Host reads SR (gets $01), then:
            //   - ISR path: checks sysSes, delays 100us, asserts sysSes
            //   - Register path: discards byte, delays, asserts sysSes
            // Egret waits for sysSes (PB5=1) before sending data bytes.
            ST_SEND_ATTN: begin
                clk_div <= clk_div + 1'd1;

                if (clk_div >= CB1_HALF_PERIOD) begin
                    clk_div <= 6'd0;

                    if (!sample_phase) begin
                        // Drive CB2 with data bit, raise CB1 (VIA shifts in on rising)
                        cuda_cb2 <= shift_data[7];
                        cuda_cb1  <= 1'b1;
                        bit_count <= bit_count + 1'd1;
                        sample_phase <= 1'b1;
                    end else begin
                        // Lower CB1, shift to next bit
                        cuda_cb1 <= 1'b0;
                        sample_phase <= 1'b0;
                        shift_data <= {shift_data[6:0], 1'b0};

                        if (bit_count >= 4'd8) begin
                            // Attention byte clocked — wait for host sysSes
                            state <= ST_SEND_WAIT_ACK;
                            wait_counter <= 16'd0;
`ifdef SIMULATION
                            $display("EGRET_BEH: Attention byte $01 clocked, waiting for sysSes");
`endif
                        end
                    end
                end
            end

            // ==== SEND_WAIT_ACK: Wait for host to assert sysSes after attention byte ====
            // Host ISR: delay 100us, bset #sysSes,vBufB → PB5=1
            // Register path: delay, bset #sysSes,vBufB → PB5=1
            ST_SEND_WAIT_ACK: begin
                wait_counter <= wait_counter + 1'd1;
                cuda_cb1 <= 1'b0;

                if (tip) begin
                    // Host asserted sysSes — start sending data bytes
                    // Small delay for VIA to settle
                    if (wait_counter >= 16'd20) begin
                        state        <= ST_SEND_CLOCK;
                        clk_div      <= 6'd0;
                        bit_count    <= 4'd0;
                        sample_phase <= 1'b0;
                        shift_data   <= send_buf[0];
                        cuda_cb2     <= send_buf[0][7];
                        cuda_cb2_oe  <= 1'b1;
`ifdef SIMULATION
                        $display("EGRET_BEH: sysSes asserted, sending byte[0] = 0x%02x", send_buf[0]);
`endif
                    end
                end else if (wait_counter >= 16'd100000) begin
                    // Timeout
                    treq_reg <= 1'b0;
                    state    <= ST_IDLE;
`ifdef SIMULATION
                    $display("EGRET_BEH: SEND_WAIT_ACK timeout, returning to IDLE");
`endif
                end
            end

            // ==== SEND_CLOCK: clock 8 bits to VIA SR (mode 3 = shift in ext) ====
            ST_SEND_CLOCK: begin
                clk_div <= clk_div + 1'd1;

                if (clk_div >= CB1_HALF_PERIOD) begin
                    clk_div <= 6'd0;

                    if (!sample_phase) begin
                        // Phase 0: CB2 has data, raise CB1 (VIA shifts in)
                        cuda_cb2  <= shift_data[7];
                        cuda_cb1  <= 1'b1;
                        bit_count <= bit_count + 1'd1;
                        sample_phase <= 1'b1;
                    end else begin
                        // Phase 1: Lower CB1, advance to next bit
                        cuda_cb1 <= 1'b0;
                        sample_phase <= 1'b0;
                        shift_data <= {shift_data[6:0], 1'b0};

                        if (bit_count >= 4'd8) begin
                            // Byte complete — IFR[2] fires in VIA
                            send_count <= send_count + 1'd1;
                            wait_counter <= 16'd0;

                            if (send_count + 1'd1 >= send_length) begin
                                // Last byte sent — deassert xcvrSes BEFORE host checks
                                // Host's last-byte handler (4081540E) does: read SR, set viaFull,
                                // delay, deassert TIP, poll TREQ. We need TREQ deasserted by then.
                                treq_reg <= 1'b0;  // Deassert xcvrSes (PB3=1)
                                state <= ST_SEND_WAIT_VIAFULL;
`ifdef SIMULATION
                                $display("EGRET_BEH: Last byte[%0d] = 0x%02x sent, xcvrSes deasserted",
                                         send_count, send_buf[send_count]);
`endif
                            end else begin
                                // More bytes to send — keep xcvrSes asserted
                                state <= ST_SEND_WAIT_VIAFULL;
`ifdef SIMULATION
                                $display("EGRET_BEH: Byte[%0d] = 0x%02x sent, waiting for viaFull ack",
                                         send_count, send_buf[send_count]);
`endif
                            end
                        end
                    end
                end
            end

            // ==== SEND_WAIT_VIAFULL: Wait for host viaFull (PB4) ack after each byte ====
            // Egret protocol: host sets viaFull (PB4=1), delays 100us, then clears it
            // on ISR exit. We detect the rising edge of viaFull, then wait for it to
            // clear before sending the next byte.
            //
            // For the last byte, xcvrSes is already deasserted. Host does viaFullAck,
            // then deasserts TIP, polls TREQ (sees deasserted), clears viaFull.
            ST_SEND_WAIT_VIAFULL: begin
                wait_counter <= wait_counter + 1'd1;
                cuda_cb1 <= 1'b0;

                if (!tip) begin
                    // Host deasserted sysSes — transaction done
                    treq_reg <= 1'b0;
                    state <= ST_FINISH;
                    wait_counter <= 16'd0;
`ifdef SIMULATION
                    $display("EGRET_BEH: sysSes deasserted (sent %0d/%0d), transaction done",
                             send_count, send_length);
`endif
                end else if (viafull && !viafull_prev) begin
                    // Host set viaFull (PB4 rising) = acknowledged byte
                    // Now wait for viaFull to clear before sending next byte
                    if (send_count >= send_length) begin
                        // Last byte was ack'd — host will deassert TIP, poll TREQ → done
                        // Already in this state, just keep waiting for !tip
`ifdef SIMULATION
                        $display("EGRET_BEH: Last byte ack'd (viaFull), waiting for sysSes deassert");
`endif
                    end
                    // For non-last bytes, we wait for viaFull to drop, then send next
                end else if (!viafull && viafull_prev && send_count < send_length) begin
                    // viaFull cleared (PB4 falling) — host is ready for next byte
                    state        <= ST_SEND_CLOCK;
                    clk_div      <= 6'd0;
                    bit_count    <= 4'd0;
                    sample_phase <= 1'b0;
                    shift_data   <= send_buf[send_count];
                    cuda_cb2     <= send_buf[send_count][7];
                    cuda_cb2_oe  <= 1'b1;
`ifdef SIMULATION
                    $display("EGRET_BEH: viaFull cleared, sending byte[%0d] = 0x%02x",
                             send_count, send_buf[send_count]);
`endif
                end else if (wait_counter >= 16'd100000) begin
                    // Timeout
                    treq_reg <= 1'b0;
                    state <= ST_IDLE;
`ifdef SIMULATION
                    $display("EGRET_BEH: SEND_WAIT_VIAFULL timeout (sent %0d/%0d)",
                             send_count, send_length);
`endif
                end
            end

            // ==== FINISH: clean up, return to IDLE ====
            ST_FINISH: begin
                wait_counter <= wait_counter + 1'd1;
                treq_reg    <= 1'b0;
                cuda_cb1    <= 1'b0;
                cuda_cb2_oe <= 1'b0;

                if (wait_counter >= 16'd100) begin
                    state <= ST_IDLE;
`ifdef SIMULATION
                    $display("EGRET_BEH: Transaction complete, returning to IDLE");
`endif
                end
            end

            default: state <= ST_IDLE;

            endcase
        end
    end

endmodule
