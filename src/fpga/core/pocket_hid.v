// ============================================================================
// pocket_hid.v — Analogue Dock USB keyboard/mouse -> ps2_key / ps2_mouse
//
// The Dock's HID data arrives on the SAME controller ports the gamepad uses;
// there is no separate interface and nothing in src/fpga/apf/ has to change.
// APF publishes a keyboard on controller 3 and a mouse on controller 4:
//
//   MOUSE  (controller 4)
//     cont4_key[31:28] == 4'h5   device is a mouse
//     cont4_key[15:0]            report counter — a CHANGE means a new report
//     cont4_joy[31:16]           buttons: bit0 left, bit1 right, bit2 middle
//     cont4_joy[15:0]            relative X, signed
//     cont4_trig[15:0]           relative Y, signed
//
//   KEYBOARD (controller 3)
//     cont3_key[31:28] == 4'h4   device is a keyboard
//     cont3_key[15:8]            modifiers, USB HID order (see MOD_* below)
//     cont3_joy[31:24,23:16,15:8,7:0] + cont3_trig[15:8,7:0]
//                                six concurrent 8-bit HID usage codes
//
// Verified against open-fpga/core-example-kbmouse-targetdata and independently
// against the Amiga core's driver (../Analogue-Amiga
// src/MPUBIOS/drivers/KMIO/inputs.cpp), which agree exactly. That core does
// its decoding in RISC-V firmware, so only the wire format is borrowed here —
// the translation below is ours.
//
// OUTPUT is the same pair of buses pocket_input.v synthesises, so everything
// downstream (adb_device -> Egret -> Mac) is untouched and already validated:
//   ps2_key  [10] TOGGLE strobe  [9] pressed  [8:0] PS/2 Set 2 (bit8 = E0)
//   ps2_mouse[24] TOGGLE strobe  [23:16] dy  [15:8] dx  [7:0] status
//
// WHY PS/2 SET 2 AND NOT ADB DIRECTLY: adb_device.sv already contains a
// complete, hardware-validated Set 2 decode. Emitting Set 2 reuses it whole
// rather than opening a second untested path into the Egret.
//
// ★ HID HAS NO KEY-RELEASE EVENT. A key is released by VANISHING from the
// six-slot array. This module must synthesise every key-up by diffing the new
// report against the previous one. Miss one and that key stays down on the Mac
// forever — the same hazard pocket_input's clean-release logic exists to stop.
// ============================================================================

`default_nettype none

module pocket_hid #(
	parameter integer CLK_HZ      = 32_500_000,
	// Mouse reports per second toward the Mac. A real ADB mouse reports at
	// ~90 Hz; a USB gaming mouse can produce 1000 reports/s, so motion is
	// ACCUMULATED between ticks rather than dropped (see mouse section).
	parameter integer PTR_RATE_HZ = 100
)(
	input  wire        clk,            // clk_sys (32.5 MHz)
	input  wire        reset,

	// Raw APF controller ports (clk_74a domain — synchronised below)
	input  wire [31:0] cont3_key,
	input  wire [31:0] cont3_joy,
	input  wire [15:0] cont3_trig,
	input  wire [31:0] cont4_key,
	input  wire [31:0] cont4_joy,
	input  wire [15:0] cont4_trig,

	output reg  [10:0] ps2_key,
	output reg  [24:0] ps2_mouse,

	// 1 = a device of that class is present on the Dock. core_top uses these
	// only for arbitration/debug; absence must leave the gamepad untouched.
	output wire        kbd_present,
	output wire        mouse_present
);

	// ---- Clock-domain crossing -------------------------------------------
	// These buses are written in clk_74a. Each report is guarded by its own
	// counter/type field, and reports are >=1 us apart (>=32 clk_sys cycles)
	// while a 2FF sync settles in 2, so sampling the payload once the counter
	// has changed is safe. The extra SETTLE delay below covers the case where
	// APF updates payload and counter in an order we cannot observe.
	reg [31:0] k3_key_s1, k3_key_s2, k3_joy_s1, k3_joy_s2;
	reg [15:0] k3_trg_s1, k3_trg_s2;
	reg [31:0] k4_key_s1, k4_key_s2, k4_joy_s1, k4_joy_s2;
	reg [15:0] k4_trg_s1, k4_trg_s2;
	always @(posedge clk) begin
		k3_key_s1 <= cont3_key;  k3_key_s2 <= k3_key_s1;
		k3_joy_s1 <= cont3_joy;  k3_joy_s2 <= k3_joy_s1;
		k3_trg_s1 <= cont3_trig; k3_trg_s2 <= k3_trg_s1;
		k4_key_s1 <= cont4_key;  k4_key_s2 <= k4_key_s1;
		k4_joy_s1 <= cont4_joy;  k4_joy_s2 <= k4_joy_s1;
		k4_trg_s1 <= cont4_trig; k4_trg_s2 <= k4_trg_s1;
	end

	localparam [3:0] TYPE_KBD   = 4'h4;
	localparam [3:0] TYPE_MOUSE = 4'h5;
	assign kbd_present   = (k3_key_s2[31:28] == TYPE_KBD);
	assign mouse_present = (k4_key_s2[31:28] == TYPE_MOUSE);

	// ======================================================================
	// MOUSE
	// ======================================================================
	// A new report is a CHANGE in the counter — never equality, and never an
	// assumption that it increments by one (reports can be missed and the
	// counter wraps).
	localparam integer TICK_DIV = CLK_HZ / PTR_RATE_HZ;

	reg [15:0] m_cnt_prev;
	reg signed [15:0] dx_acc, dy_acc;   // accumulate between ADB-rate ticks
	reg        btn_state, btn_reported;
	reg [23:0] tick_cnt;
	reg        tick;

	wire signed [15:0] hid_dx = $signed(k4_joy_s2[15:0]);
	wire signed [15:0] hid_dy = $signed(k4_trg_s2[15:0]);
	// The Mac mouse has ONE button, so any physical button is that button.
	wire hid_btn = |k4_joy_s2[18:16];

	// Drain the accumulator into one 9-bit two's complement delta, saturating.
	// ps2_mouse[15:8] is the LOW BYTE of a 9-bit signed value and the status
	// bit is simply bit 8 — NOT sign-and-magnitude (pocket_input.v documents
	// this at length; getting it wrong moves the cursor by 256-n backwards).
	function signed [8:0] sat9;
		input signed [15:0] v;
		begin
			// -256 must be written as the literal bit pattern: 9'sd256 does
			// not fit in 9 signed bits, so `-9'sd256` overflows and Quartus
			// warns (10259). 9'sb1_0000_0000 IS -256 in two's complement.
			if (v > 16'sd255)       sat9 = 9'sd255;
			else if (v < -16'sd256) sat9 = 9'sb1_0000_0000;
			else                    sat9 = v[8:0];
		end
	endfunction

	wire signed [8:0] dx_out = sat9(dx_acc);
	// ★ Y SIGN: USB HID counts Y POSITIVE DOWNWARD; adb_device takes the PS/2
	// convention where POSITIVE dy is UP. The negation is required. Hardware
	// already caught this once on the gamepad path — do not "simplify" it away
	// without testing on a real Mac desktop.
	wire signed [8:0] dy_out = sat9(-dy_acc);

	function [7:0] status_byte;
		input ysign, xsign, btn;
		begin
			status_byte = {2'b00, ysign, xsign, 1'b1, 2'b00, btn};
		end
	endfunction

	always @(posedge clk) begin
		if (reset) begin
			ps2_mouse    <= 25'd0;
			m_cnt_prev   <= 16'd0;
			dx_acc       <= 16'sd0;
			dy_acc       <= 16'sd0;
			btn_state    <= 1'b0;
			btn_reported <= 1'b0;
			tick_cnt     <= 24'd0;
			tick         <= 1'b0;
		end else begin
			tick <= 1'b0;
			if (tick_cnt == TICK_DIV-1) begin tick_cnt <= 24'd0; tick <= 1'b1; end
			else                              tick_cnt <= tick_cnt + 24'd1;

			// New report -> accumulate. Never drop motion: a 1000 Hz mouse
			// produces ~10 reports per 100 Hz tick and all of them count.
			if (mouse_present && (k4_key_s2[15:0] != m_cnt_prev)) begin
				m_cnt_prev <= k4_key_s2[15:0];
				dx_acc     <= dx_acc + hid_dx;
				dy_acc     <= dy_acc + hid_dy;
				btn_state  <= hid_btn;
			end

			// A click must not wait for the next tick.
			if (btn_state != btn_reported) begin
				btn_reported <= btn_state;
				ps2_mouse <= { ~ps2_mouse[24], 8'd0, 8'd0,
				               status_byte(1'b0, 1'b0, btn_state) };
			end else if (tick && (dx_acc != 0 || dy_acc != 0)) begin
				ps2_mouse <= { ~ps2_mouse[24], dy_out[7:0], dx_out[7:0],
				               status_byte(dy_out[8], dx_out[8], btn_reported) };
				// Subtract exactly what was sent so saturated motion is
				// carried into the next report instead of being discarded.
				dx_acc <= dx_acc - $signed({{7{dx_out[8]}}, dx_out});
				dy_acc <= dy_acc + $signed({{7{dy_out[8]}}, dy_out});
			end
		end
	end

	// ======================================================================
	// KEYBOARD
	// ======================================================================
	// HID modifier bit order within cont3_key[15:8].
	localparam integer MOD_LCTRL = 0, MOD_LSHIFT = 1, MOD_LALT = 2, MOD_LGUI = 3;
	localparam integer MOD_RCTRL = 4, MOD_RSHIFT = 5, MOD_RALT = 6, MOD_RGUI = 7;

	// Modifier -> PS/2 Set 2. The mapping puts a PC keyboard's modifiers in
	// the physically correct Mac positions: Alt sits where Command does and
	// the GUI/Windows key sits where Option does.
	//   LALT/RALT -> 0x011/0x111 -> ADB 0x37 Command
	//   LGUI/RGUI -> 0x11F       -> ADB 0x3A Option
	function [8:0] mod_code;
		input integer b;
		begin
			case (b)
				MOD_LCTRL : mod_code = 9'h014;
				MOD_LSHIFT: mod_code = 9'h012;
				MOD_LALT  : mod_code = 9'h011;
				MOD_LGUI  : mod_code = 9'h11F;
				MOD_RCTRL : mod_code = 9'h014;
				MOD_RSHIFT: mod_code = 9'h059;
				MOD_RALT  : mod_code = 9'h111;
				MOD_RGUI  : mod_code = 9'h11F;
				default   : mod_code = 9'h000;
			endcase
		end
	endfunction

	// USB HID usage code -> PS/2 Set 2 (bit 8 = the E0 extended prefix).
	// 0 means "no mapping" and is never emitted. Verified against the decode
	// table in rtl/adb_device.sv.
	function [8:0] hid2ps2;
		input [7:0] u;
		begin
			case (u)
				8'h04: hid2ps2 = 9'h01C; 8'h05: hid2ps2 = 9'h032; // a b
				8'h06: hid2ps2 = 9'h021; 8'h07: hid2ps2 = 9'h023; // c d
				8'h08: hid2ps2 = 9'h024; 8'h09: hid2ps2 = 9'h02B; // e f
				8'h0A: hid2ps2 = 9'h034; 8'h0B: hid2ps2 = 9'h033; // g h
				8'h0C: hid2ps2 = 9'h043; 8'h0D: hid2ps2 = 9'h03B; // i j
				8'h0E: hid2ps2 = 9'h042; 8'h0F: hid2ps2 = 9'h04B; // k l
				8'h10: hid2ps2 = 9'h03A; 8'h11: hid2ps2 = 9'h031; // m n
				8'h12: hid2ps2 = 9'h044; 8'h13: hid2ps2 = 9'h04D; // o p
				8'h14: hid2ps2 = 9'h015; 8'h15: hid2ps2 = 9'h02D; // q r
				8'h16: hid2ps2 = 9'h01B; 8'h17: hid2ps2 = 9'h02C; // s t
				8'h18: hid2ps2 = 9'h03C; 8'h19: hid2ps2 = 9'h02A; // u v
				8'h1A: hid2ps2 = 9'h01D; 8'h1B: hid2ps2 = 9'h022; // w x
				8'h1C: hid2ps2 = 9'h035; 8'h1D: hid2ps2 = 9'h01A; // y z
				8'h1E: hid2ps2 = 9'h016; 8'h1F: hid2ps2 = 9'h01E; // 1 2
				8'h20: hid2ps2 = 9'h026; 8'h21: hid2ps2 = 9'h025; // 3 4
				8'h22: hid2ps2 = 9'h02E; 8'h23: hid2ps2 = 9'h036; // 5 6
				8'h24: hid2ps2 = 9'h03D; 8'h25: hid2ps2 = 9'h03E; // 7 8
				8'h26: hid2ps2 = 9'h046; 8'h27: hid2ps2 = 9'h045; // 9 0
				8'h28: hid2ps2 = 9'h05A;                          // Return
				8'h29: hid2ps2 = 9'h076;                          // Esc
				8'h2A: hid2ps2 = 9'h066;                          // Backspace
				8'h2B: hid2ps2 = 9'h00D;                          // Tab
				8'h2C: hid2ps2 = 9'h029;                          // Space
				8'h2D: hid2ps2 = 9'h04E; 8'h2E: hid2ps2 = 9'h055; // - =
				8'h2F: hid2ps2 = 9'h054; 8'h30: hid2ps2 = 9'h05B; // [ ]
				8'h31: hid2ps2 = 9'h05D;                          // backslash
				8'h33: hid2ps2 = 9'h04C; 8'h34: hid2ps2 = 9'h052; // ; '
				8'h35: hid2ps2 = 9'h00E;                          // `
				8'h36: hid2ps2 = 9'h041; 8'h37: hid2ps2 = 9'h049; // , .
				8'h38: hid2ps2 = 9'h04A;                          // /
				8'h39: hid2ps2 = 9'h058;                          // Caps Lock
				8'h3A: hid2ps2 = 9'h005; 8'h3B: hid2ps2 = 9'h006; // F1 F2
				8'h3C: hid2ps2 = 9'h004; 8'h3D: hid2ps2 = 9'h00C; // F3 F4
				8'h3E: hid2ps2 = 9'h003; 8'h3F: hid2ps2 = 9'h00B; // F5 F6
				8'h40: hid2ps2 = 9'h083; 8'h41: hid2ps2 = 9'h00A; // F7 F8
				8'h42: hid2ps2 = 9'h001; 8'h43: hid2ps2 = 9'h009; // F9 F10
				8'h44: hid2ps2 = 9'h078; 8'h45: hid2ps2 = 9'h007; // F11 F12
				8'h49: hid2ps2 = 9'h170;                          // Insert
				8'h4A: hid2ps2 = 9'h16C;                          // Home
				8'h4B: hid2ps2 = 9'h17D;                          // Page Up
				8'h4C: hid2ps2 = 9'h171;                          // Delete fwd
				8'h4D: hid2ps2 = 9'h169;                          // End
				8'h4E: hid2ps2 = 9'h17A;                          // Page Down
				8'h4F: hid2ps2 = 9'h174;                          // Right
				8'h50: hid2ps2 = 9'h16B;                          // Left
				8'h51: hid2ps2 = 9'h172;                          // Down
				8'h52: hid2ps2 = 9'h175;                          // Up
				default: hid2ps2 = 9'h000;
			endcase
		end
	endfunction

	// ---- Report latch -----------------------------------------------------
	// cont3 carries no counter, so a report is "new" when the six codes or the
	// modifier byte differ from what we last ACCEPTED. A report arriving while
	// the differ is still walking is held until it goes idle.
	wire [7:0] rc0 = k3_joy_s2[31:24], rc1 = k3_joy_s2[23:16];
	wire [7:0] rc2 = k3_joy_s2[15:8],  rc3 = k3_joy_s2[7:0];
	wire [7:0] rc4 = k3_trg_s2[15:8],  rc5 = k3_trg_s2[7:0];
	wire [7:0] rmod = k3_key_s2[15:8];

	reg [7:0] cur [0:5];        // codes as last reported to the Mac
	reg [7:0] cur_mod;
	reg [7:0] nxt [0:5];        // the report being applied
	reg [7:0] nxt_mod;
	reg       busy;
	reg [4:0] step;             // 0-5 release, 6-11 press, 12-19 modifiers

	wire report_changed = kbd_present &&
	     (rc0 != cur[0] || rc1 != cur[1] || rc2 != cur[2] ||
	      rc3 != cur[3] || rc4 != cur[4] || rc5 != cur[5] || rmod != cur_mod);

	// A code is "still held" if it appears anywhere in the other array. Code 0
	// is the empty slot and never matches. HID also reports 8'h01 in every
	// slot for rollover overflow; treat it as empty so a jammed keyboard
	// cannot inject a phantom key.
	function slot_empty;
		input [7:0] c;
		begin slot_empty = (c == 8'h00) || (c == 8'h01); end
	endfunction

	function in_next;
		input [7:0] c;
		begin
			in_next = !slot_empty(c) &&
			          (c == nxt[0] || c == nxt[1] || c == nxt[2] ||
			           c == nxt[3] || c == nxt[4] || c == nxt[5]);
		end
	endfunction

	function in_cur;
		input [7:0] c;
		begin
			in_cur = !slot_empty(c) &&
			         (c == cur[0] || c == cur[1] || c == cur[2] ||
			          c == cur[3] || c == cur[4] || c == cur[5]);
		end
	endfunction

	integer i;
	always @(posedge clk) begin
		if (reset) begin
			ps2_key <= 11'd0;
			busy    <= 1'b0;
			step    <= 5'd0;
			cur_mod <= 8'd0;
			nxt_mod <= 8'd0;
			for (i = 0; i < 6; i = i + 1) begin
				cur[i] <= 8'd0;
				nxt[i] <= 8'd0;
			end
		end else if (!busy) begin
			// Idle: take a snapshot and start walking it.
			if (report_changed) begin
				nxt[0] <= rc0; nxt[1] <= rc1; nxt[2] <= rc2;
				nxt[3] <= rc3; nxt[4] <= rc4; nxt[5] <= rc5;
				nxt_mod <= rmod;
				busy    <= 1'b1;
				step    <= 5'd0;
			end
		end else begin
			step <= step + 5'd1;

			if (step <= 5'd5) begin
				// RELEASES first, so a key that moved slots is not released
				// after its own re-press.
				if (!slot_empty(cur[step]) && !in_next(cur[step]) &&
				    hid2ps2(cur[step]) != 9'h000)
					ps2_key <= { ~ps2_key[10], 1'b0, hid2ps2(cur[step]) };
			end else if (step <= 5'd11) begin
				if (!slot_empty(nxt[step-6]) && !in_cur(nxt[step-6]) &&
				    hid2ps2(nxt[step-6]) != 9'h000)
					ps2_key <= { ~ps2_key[10], 1'b1, hid2ps2(nxt[step-6]) };
			end else begin
				if (nxt_mod[step-12] != cur_mod[step-12])
					ps2_key <= { ~ps2_key[10], nxt_mod[step-12],
					             mod_code(step-12) };
			end

			if (step == 5'd19) begin
				// Commit only now: every comparison above reads cur[] and the
				// walk must see a stable snapshot from start to finish.
				for (i = 0; i < 6; i = i + 1) cur[i] <= nxt[i];
				cur_mod <= nxt_mod;
				busy    <= 1'b0;
			end
		end
	end

endmodule

`default_nettype wire
