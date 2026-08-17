// tb_pocket_hid.v — what does pocket_hid ACTUALLY emit?
//
// WHY THIS EXISTS. Four hardware builds carrying a mouse-button path failed
// (F-line + video corruption) across two structurally different
// implementations and four fitter seeds, while every build without one was
// stable. Seed rolling cannot explain that, and three rounds of me reasoning
// about this module produced three wrong diagnoses. This bench replaces the
// argument with a measurement.
//
// THE HYPOTHESIS UNDER TEST: the button path emits ps2_mouse events at some
// pathological rate. Every event makes adb_device raise an ADB Service
// Request at the Egret, so an event storm becomes an interrupt storm on the
// 68020 — which would plausibly present as a hung or corrupted machine while
// looking exactly like a bad fit.
//
// Run: bash verilator/run_tb_pocket_hid.sh
//
// Wire format (cont4 = mouse), as used by pocket_hid:
//   cont4_key[31:28] = 4'h5 type   cont4_key[15:0] = report counter
//   cont4_joy[31:16] = buttons     cont4_joy[15:8]  = X delta (8-bit signed)
//   cont4_trig[15:8] = Y delta

`timescale 1ns/1ps

module tb_pocket_hid;

    reg clk = 1'b0;
    reg reset = 1'b1;
    always #15.384 clk = ~clk;          // 32.5 MHz

    reg [31:0] cont3_key = 32'd0, cont3_joy = 32'd0;
    reg [15:0] cont3_trig = 16'd0;
    reg [31:0] cont4_key = 32'd0, cont4_joy = 32'd0;
    reg [15:0] cont4_trig = 16'd0;
    reg [1:0]  speed_sel = 2'd0;

    wire [10:0] ps2_key;
    wire [24:0] ps2_mouse;
    wire        kbd_present, mouse_present;

    pocket_hid dut (
        .clk(clk), .reset(reset),
        .cont3_key(cont3_key), .cont3_joy(cont3_joy), .cont3_trig(cont3_trig),
        .cont4_key(cont4_key), .cont4_joy(cont4_joy), .cont4_trig(cont4_trig),
        .speed_sel(speed_sel),
        .ps2_key(ps2_key), .ps2_mouse(ps2_mouse),
        .kbd_present(kbd_present), .mouse_present(mouse_present)
    );

    // ---- event counting ---------------------------------------------------
    integer m_events = 0;
    integer k_events = 0;
    reg m_d, k_d;
    reg counting = 1'b0;
    always @(posedge clk) begin
        m_d <= ps2_mouse[24];
        k_d <= ps2_key[10];
        if (counting) begin
            if (ps2_mouse[24] !== m_d) m_events = m_events + 1;
            if (ps2_key[10]   !== k_d) k_events = k_events + 1;
        end
    end

    integer fails = 0;
    task expect_m;
        input integer want;
        input [255:0] what;
        begin
            if (m_events !== want) begin
                $display("  FAIL  %0s: expected %0d mouse events, got %0d",
                         what, want, m_events);
                fails = fails + 1;
            end else begin
                $display("  ok    %0s: %0d mouse events", what, m_events);
            end
        end
    endtask

    task arm; begin @(posedge clk); m_events = 0; k_events = 0; counting = 1'b1; end endtask
    task idle; input integer n; integer i; begin for (i=0;i<n;i=i+1) @(posedge clk); end endtask

    reg [15:0] ctr = 16'd0;

    // One HID mouse report: bumps the counter the way APF does.
    task report;
        input signed [7:0] dx;
        input signed [7:0] dy;
        input btn;
        begin
            ctr = ctr + 16'd1;
            cont4_joy  = {15'd0, btn, dx, 8'd0};
            cont4_trig = {dy, 8'd0};
            cont4_key  = {4'h5, 12'd0, ctr};
            idle(4);
        end
    endtask

    // A button change with NO new report — the case that matters. APF's
    // counter does not necessarily advance for a press/release on a still
    // mouse, which is the whole reason the button path exists.
    task button_only;
        input btn;
        begin
            cont4_joy = {15'd0, btn, cont4_joy[15:0]};
            idle(4);
        end
    endtask

    initial begin
        $display("=== tb_pocket_hid ===");
        cont4_key = {4'h5, 12'd0, 16'd0};
        idle(10);
        reset = 1'b0;
        idle(10);

        // ---- 1. an idle, present mouse must be SILENT ---------------------
        // A storm here is the hypothesis: continuous events = continuous ADB
        // service requests = an interrupt storm on the guest.
        arm; idle(20000);
        expect_m(0, "idle mouse, 20000 clocks");

        // ---- 2. one motion report = exactly one event ---------------------
        arm; report(8'sd5, 8'sd0, 1'b0); idle(200);
        expect_m(1, "single motion report");

        // ---- 3. button press with NO counter change -----------------------
        arm; button_only(1'b1); idle(200);
        expect_m(1, "button press, counter unchanged");

        // ---- 4. and it must then go quiet ---------------------------------
        arm; idle(20000);
        expect_m(0, "held button, 20000 clocks");

        // ---- 5. release ---------------------------------------------------
        arm; button_only(1'b0); idle(200);
        expect_m(1, "button release, counter unchanged");

        arm; idle(20000);
        expect_m(0, "after release, 20000 clocks");

        // ---- 6. a click DURING motion -------------------------------------
        arm;
        report(8'sd3, 8'sd2, 1'b0);
        report(8'sd3, 8'sd2, 1'b1);      // press arrives with motion
        report(8'sd3, 8'sd2, 1'b1);
        report(8'sd3, 8'sd2, 1'b0);      // release arrives with motion
        idle(200);
        expect_m(4, "4 reports, button changing mid-stream");

        // ---- 7. mouse UNPLUGGED while the button is held ------------------
        // The nasty one: if the module cannot report the release after the
        // device vanishes, the Mac holds the button down forever.
        arm;
        button_only(1'b1); idle(100);
        cont4_key = 32'd0;               // device gone
        idle(20000);
        $display("  info  unplug-with-button-held: %0d events, ps2_mouse btn bit = %0b",
                 m_events, ps2_mouse[0]);

        // ---- 8. device returns --------------------------------------------
        arm;
        cont4_key = {4'h5, 12'd0, ctr};
        idle(20000);
        $display("  info  device returns: %0d events", m_events);

        $display("");
        if (fails == 0) $display("RESULT: PASS (no storm, no missed edge)");
        else            $display("RESULT: %0d FAILURE(S)", fails);
        $finish;
    end

endmodule
