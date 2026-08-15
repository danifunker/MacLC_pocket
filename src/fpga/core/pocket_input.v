// ============================================================================
// pocket_input.v — Analogue Pocket gamepad -> ps2_key / ps2_mouse
//
// WHY THIS MODULE IS THE WHOLE INPUT PORT
//
// On MiSTer a real USB keyboard/mouse is decoded by the HPS (ARM Linux), which
// hands the core two standard buses:
//
//     ps2_key[10:0] / ps2_mouse[24:0]  ->  adb_device  ->  Egret  ->  Mac
//
// Everything to the RIGHT of those two buses is identical on MiSTer and
// Pocket. The Pocket has no HPS and no USB HID, so porting input means
// SYNTHESISING those two buses from the gamepad. adb_device.sv, the Egret HC05
// and the Mac side are untouched.
//
// BUS FORMATS (as consumed by rtl/adb_device.sv:133-145)
//   ps2_key  [10]    strobe: TOGGLES on every event (not a pulse)
//            [9]     1 = pressed, 0 = released
//            [8:0]   PS/2 Set 2 scancode; bit 8 = the E0 "extended" prefix
//   ps2_mouse[24]    strobe: TOGGLES on every report
//            [23:16] dy magnitude      [5] dy sign
//            [15:8]  dx magnitude      [4] dx sign
//            [0]     left button
//
// The strobes are TOGGLES because adb_device synchronises them into the Egret
// clock domain and edge-detects (kstb_s3 != kstb_d). A pulse would be missed.
//
// TWO MODES, ONE STICK
//
// The classic Mac is a mouse-driven machine, but the games worth playing on a
// handheld are keyboard-driven. Rather than pick one, Select toggles:
//
//   KBD mode  D-pad -> arrow keys, A/B/X/Y -> configurable key scancodes
//   PTR mode  D-pad -> mouse motion, A -> mouse button
//
// Feedback is free and needs no on-screen indicator: in PTR mode the cursor
// visibly moves, in KBD mode it does not.
//
// The classic Mac mouse has ONE button, so a single click button is complete —
// there is no right-click to strand.
//
// CLEAN RELEASE ON MODE FLIP is not optional. If the user switches modes with
// a direction held, the Mac would keep a key down or a button clicked forever.
// On every flip this module emits key-up for every held key and clears the
// mouse button before the new mode takes effect.
// ============================================================================

`default_nettype none

module pocket_input #(
	// Mouse motion per report, in mouse units. The Mac's cursor acceleration
	// makes small steady deltas feel better than large ones.
	parameter integer PTR_STEP_SLOW = 1,
	parameter integer PTR_STEP_FAST = 6,
	// Reports per second in PTR mode. A real ADB mouse reports at ~90 Hz;
	// adb_device polls on its own schedule so this only sets cursor speed.
	parameter integer CLK_HZ        = 32_500_000,
	parameter integer PTR_RATE_HZ   = 100,
	// Hold a direction this long before the fast step kicks in (~0.4 s).
	parameter integer PTR_RAMP_MS   = 400
)(
	input  wire        clk,          // clk_sys (32.5 MHz)
	input  wire        reset,

	// Analogue Pocket controller 1. Bit assignment per the APF core_top
	// header: 0=up 1=down 2=left 3=right 4=A 5=B 6=X 7=Y 8=L1 9=R1
	// 14=select 15=start.
	input  wire [15:0] cont1_key,

	// Per-button key mappings (buildBF): PS/2 Set 2 scancodes, bit 8 = E0.
	// Already RESOLVED by core_top (the Custom indirection happens there);
	// 9'h000 = unmapped (the button emits nothing). clk domain, quasi-static
	// (interact writes are rare and human-paced).
	input  wire [8:0]  map_a,
	input  wire [8:0]  map_b,
	input  wire [8:0]  map_x,
	input  wire [8:0]  map_y,
	input  wire [8:0]  map_l,
	input  wire [8:0]  map_r,
	input  wire [8:0]  map_start,

	// Power-on input mode from Core Settings (buildBG): 1 = mouse (PTR),
	// 0 = keyboard. Tracked LIVE until the user first presses Select, so a
	// menu change applies immediately; after that Select owns the mode.
	input  wire        ptr_default,

	// Synthesised buses into adb_device
	output reg  [10:0] ps2_key,
	output reg  [24:0] ps2_mouse,

	// 1 = pointer mode, 0 = keyboard mode. Exposed for debug/LED only.
	output wire        ptr_mode
);

	// ---- PS/2 Set 2 scancodes (bit 8 = E0 extended) ----------------------
	// Verified against the decode table in rtl/adb_device.sv.
	localparam [8:0] SC_UP     = 9'h175;  // -> ADB 0x3E
	localparam [8:0] SC_DOWN   = 9'h172;  // -> ADB 0x3D
	localparam [8:0] SC_LEFT   = 9'h16B;  // -> ADB 0x3B
	localparam [8:0] SC_RIGHT  = 9'h174;  // -> ADB 0x3C
	localparam [8:0] SC_LSHIFT = 9'h012;  // -> ADB 0x38
	localparam [8:0] SC_ENTER  = 9'h05A;  // -> ADB 0x24
	localparam [8:0] SC_SPACE  = 9'h029;  // -> ADB 0x31
	localparam [8:0] SC_ESC    = 9'h076;  // -> ADB 0x35
	localparam [8:0] SC_N      = 9'h031;  // -> ADB 0x2D
	localparam [8:0] SC_CMD    = 9'h011;  // LEFT ALT -> ADB 0x37 (Command)

	// ---- Button bit positions in cont1_key -------------------------------
	localparam integer B_UP     = 0;
	localparam integer B_DOWN   = 1;
	localparam integer B_LEFT   = 2;
	localparam integer B_RIGHT  = 3;
	localparam integer B_A      = 4;
	localparam integer B_B      = 5;
	localparam integer B_X      = 6;
	localparam integer B_Y      = 7;
	localparam integer B_L1     = 8;
	localparam integer B_R1     = 9;
	localparam integer B_SELECT = 14;
	localparam integer B_START  = 15;

	// KBD-mode key slots, in scan order. Index 0..7 maps to the eight
	// keyboard-producing buttons; the D-pad four are first so PTR mode can
	// simply skip them.
	// Slots 0..3 are the D-pad (suppressed in PTR mode, where it drives the
	// mouse). Slot 4 is A, which is the mouse BUTTON in PTR mode and so is also
	// suppressed there. Slots 5..10 type in BOTH modes -- Command in particular
	// has to work while pointing, since the Mac uses it with the mouse.
	// buildBF: slots 4..10 take their scancodes from the map_* inputs (the old
	// fixed assignments are now the interact.json defaults); slot 10 adds R1,
	// previously unused. A map of 9'h000 means "unmapped" and is masked out of
	// `want` below, so it can never emit a code-000 event.
	localparam integer NKEYS = 11;

	function [8:0] key_for;
		input integer idx;
		begin
			case (idx)
				0: key_for = SC_UP;
				1: key_for = SC_DOWN;
				2: key_for = SC_LEFT;
				3: key_for = SC_RIGHT;
				4: key_for = map_a;      // default Return; mouse click in PTR
				5: key_for = map_b;      // default Space
				6: key_for = map_x;      // default Shift
				7: key_for = map_y;      // default N
				8: key_for = map_l;      // default Escape
				9: key_for = map_start;  // default Command
				10: key_for = map_r;     // default Q (new slot)
				default: key_for = 9'h000;
			endcase
		end
	endfunction

	function button_for;
		input integer idx;
		input [15:0] keys;
		begin
			case (idx)
				0: button_for = keys[B_UP];
				1: button_for = keys[B_DOWN];
				2: button_for = keys[B_LEFT];
				3: button_for = keys[B_RIGHT];
				4: button_for = keys[B_A];
				5: button_for = keys[B_B];
				6: button_for = keys[B_X];
				7: button_for = keys[B_Y];
				8: button_for = keys[B_L1];
				9: button_for = keys[B_START];
				10: button_for = keys[B_R1];
				default: button_for = 1'b0;
			endcase
		end
	endfunction

	// ---- Input synchroniser ----------------------------------------------
	// cont1_key is generated in the clk_74a domain; bring it over cleanly.
	reg [15:0] keys_meta, keys;
	always @(posedge clk) begin
		keys_meta <= cont1_key;
		keys      <= keys_meta;
	end

	// ---- Mode toggle on Select -------------------------------------------
	// Rising edge only, so press-and-hold does not oscillate. Select is used
	// (not A/B) so the toggle never collides with click or action.
	// buildBG: until the user's FIRST Select press, the mode FOLLOWS the
	// ptr_default setting (so the persisted power-on choice — and live menu
	// changes — apply without a rebuild-baked constant). mode_flip is now a
	// change DETECTOR on mode_ptr rather than a Select-edge side effect, so
	// the clean-release drain fires however the mode changes.
	reg mode_ptr  = 1'b1;              // matches ptr_default's RTL default
	reg mode_d    = 1'b1;
	reg sel_d     = 1'b0;
	reg sel_taken = 1'b0;              // user has taken manual control
	wire mode_flip = (mode_ptr != mode_d);   // 1-cycle: mode just changed
	always @(posedge clk) begin
		if (reset) begin
			mode_ptr  <= ptr_default;
			mode_d    <= ptr_default;
			sel_d     <= 1'b0;
			sel_taken <= 1'b0;
		end else begin
			mode_d <= mode_ptr;
			sel_d  <= keys[B_SELECT];
			if (keys[B_SELECT] && !sel_d) begin
				mode_ptr  <= ~mode_ptr;
				sel_taken <= 1'b1;
			end else if (!sel_taken) begin
				mode_ptr <= ptr_default;
			end
		end
	end
	assign ptr_mode = mode_ptr;

	// ======================================================================
	// Keyboard event generator
	// ======================================================================
	// Scans the eight key slots one per clock looking for a change against
	// the last reported state, and emits one ps2_key event per change. One
	// event per clock is far faster than any human input, so the scan never
	// falls behind and no queue is needed.
	//
	// `held` is what the Mac currently believes is down. On a mode flip we
	// force the desired state to all-released, which makes the same scanner
	// emit the key-up events — that is the clean-release guarantee.

	reg  [NKEYS-1:0] held;             // as last reported to the Mac
	reg  [3:0]       scan;             // 0..NKEYS-1 (11 slots -> 4 bits)
	reg              releasing;        // draining held keys after a mode flip
	// The scancode each held slot was PRESSED with. Releases must emit this,
	// not key_for(scan): if the user remaps a button while holding it, the
	// release otherwise carries the NEW code and the OLD key sticks down on
	// the Mac forever (buildBF).
	reg  [8:0]       held_code [0:NKEYS-1];

	wire [NKEYS-1:0] want_raw = { button_for(10, keys),
	                              button_for(9, keys), button_for(8, keys),
	                              button_for(7, keys), button_for(6, keys),
	                              button_for(5, keys), button_for(4, keys),
	                              button_for(3, keys), button_for(2, keys),
	                              button_for(1, keys), button_for(0, keys) };

	// A slot whose map is 9'h000 is UNMAPPED: it must never want, or the
	// scanner would emit code-000 events. The D-pad four are always mapped.
	wire [NKEYS-1:0] mapped = { |map_r, |map_start, |map_l, |map_y,
	                            |map_x, |map_b, |map_a, 4'b1111 };

	// In PTR mode the D-pad drives the mouse and A is the mouse button, so
	// slots 0..4 must read as released. B/X/Y/L/R/Start keep typing in both
	// modes -- Command especially, which is used together with the mouse.
	wire [NKEYS-1:0] want = releasing ? {NKEYS{1'b0}}
	                      : mode_ptr  ? ({want_raw[10:5], 5'b00000} & mapped)
	                                  : (want_raw & mapped);

	wire scan_bit_held = held[scan];
	wire scan_bit_want = want[scan];

	always @(posedge clk) begin
		if (reset) begin
			ps2_key   <= 11'd0;
			held      <= {NKEYS{1'b0}};
			scan      <= 4'd0;
			releasing <= 1'b0;
		end else begin
			// A mode flip starts a drain pass; it ends when nothing is held.
			if (mode_flip)      releasing <= 1'b1;
			else if (held == 0) releasing <= 1'b0;

			// NKEYS is 11, not a power of two, so the wrap must be explicit --
			// a free-running 4-bit counter would index slots 11..15, which do
			// not exist and would emit key_for()'s default 9'h000.
			scan <= (scan == NKEYS-1) ? 4'd0 : scan + 4'd1;

			if (scan_bit_want != scan_bit_held) begin
				// Emit exactly one event and record the new state. Presses
				// carry the CURRENT map; releases carry the code the press
				// used (see held_code above).
				ps2_key    <= { ~ps2_key[10], scan_bit_want,
				                scan_bit_want ? key_for(scan) : held_code[scan] };
				held[scan] <= scan_bit_want;
				if (scan_bit_want) held_code[scan] <= key_for(scan);
			end
		end
	end

	// ======================================================================
	// Mouse report generator
	// ======================================================================
	// Emits a report at PTR_RATE_HZ whenever anything would change: a
	// direction is held, or the button state differs from what was reported.
	// A held direction ramps from PTR_STEP_SLOW to PTR_STEP_FAST after
	// PTR_RAMP_MS so both pixel-accurate placement and crossing the screen
	// are practical.

	localparam integer TICK_DIV   = CLK_HZ / PTR_RATE_HZ;
	localparam integer RAMP_TICKS = (PTR_RATE_HZ * PTR_RAMP_MS) / 1000;

	reg [23:0] tick_cnt;               // 24b covers any sane CLK_HZ/rate
	reg        tick;
	always @(posedge clk) begin
		if (reset) begin
			tick_cnt <= 0;
			tick     <= 1'b0;
		end else if (tick_cnt == TICK_DIV-1) begin
			tick_cnt <= 0;
			tick     <= 1'b1;
		end else begin
			tick_cnt <= tick_cnt + 1'b1;
			tick     <= 1'b0;
		end
	end

	wire dir_up    = mode_ptr & keys[B_UP];
	wire dir_down  = mode_ptr & keys[B_DOWN];
	wire dir_left  = mode_ptr & keys[B_LEFT];
	wire dir_right = mode_ptr & keys[B_RIGHT];
	wire any_dir   = dir_up | dir_down | dir_left | dir_right;

	// Button: A clicks in PTR mode. Forced released the instant we leave PTR
	// mode so a click can never stick across a flip.
	wire btn_want = mode_ptr & keys[B_A];

	reg [15:0] hold_ticks;             // how long a direction has been held
	reg        btn_reported;

	wire [7:0] step = (hold_ticks >= RAMP_TICKS[15:0]) ? PTR_STEP_FAST[7:0]
	                                                   : PTR_STEP_SLOW[7:0];

	// Deltas as 9-bit TWO'S COMPLEMENT.
	//
	// This is the subtle part. adb_device rebuilds each axis as
	//     mX = {ps2_mouse[4], ps2_mouse[15:8]}
	// i.e. it concatenates the sign bit onto the 8-bit field and treats the
	// result as one 9-bit signed number — the PS/2 convention, where the byte
	// is the LOW 8 BITS of a 9-bit two's complement value and the "sign" bit
	// is simply bit 8. It is NOT sign-and-magnitude: sending a magnitude with
	// the sign set would move the cursor by (256 - n) in the wrong direction.
	// So the byte is just dx[7:0] and the sign bit is just dx[8].
	//
	// Y SIGN: this used to assume "Mac screen Y grows downward and so does the
	// delta adb_device expects, so D-pad down is positive". That was wrong --
	// on hardware the cursor moved inverted. adb_device takes the PS/2
	// convention, where POSITIVE dy is UP. Do not 'correct' this back without
	// testing on hardware.
	wire signed [8:0] dx = dir_left  ? -$signed({1'b0, step}) :
	                       dir_right ?  $signed({1'b0, step}) : 9'sd0;
	wire signed [8:0] dy = dir_up    ?  $signed({1'b0, step}) :
	                       dir_down  ? -$signed({1'b0, step}) : 9'sd0;

	// ps2_mouse[7:0] is the PS/2 status byte:
	//   [7] y overflow  [6] x overflow  [5] y sign  [4] x sign
	//   [3] always 1    [2] middle      [1] right   [0] left
	// Overflow is always 0 here: step never exceeds 127.
	function [7:0] status_byte;
		input ysign;
		input xsign;
		input btn;
		begin
			status_byte = {2'b00, ysign, xsign, 1'b1, 2'b00, btn};
		end
	endfunction

	always @(posedge clk) begin
		if (reset) begin
			ps2_mouse    <= 25'd0;
			hold_ticks   <= 16'd0;
			btn_reported <= 1'b0;
		end else begin
			if (tick) begin
				if (any_dir) begin
					if (hold_ticks != 16'hFFFF) hold_ticks <= hold_ticks + 1'b1;
				end else begin
					hold_ticks <= 16'd0;
				end
			end

			// Report immediately if the button changed (a click must not wait
			// for the next tick), otherwise on a tick if there is motion.
			if (btn_want != btn_reported) begin
				btn_reported <= btn_want;
				ps2_mouse <= { ~ps2_mouse[24],
				               8'd0,                       // dy = 0
				               8'd0,                       // dx = 0
				               status_byte(1'b0, 1'b0, btn_want) };
			end else if (tick && any_dir) begin
				ps2_mouse <= { ~ps2_mouse[24],
				               dy[7:0],
				               dx[7:0],
				               status_byte(dy[8], dx[8], btn_reported) };
			end
		end
	end

endmodule

`default_nettype wire
