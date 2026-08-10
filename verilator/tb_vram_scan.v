/* tb_vram_scan.v — packed-VRAM write -> scanout readback, at 512x384.
 *
 * WHY: the Pocket cut narrowed every address in the framebuffer path
 * (vram_waddr/vram_raddr 18->17 bits, vram_bram DEPTH 196608->98304) and
 * HALVED the scanline line buffer (1024->512 entries, index [8:0]->[7:0]).
 * Those are exactly the edits that would corrupt the image while leaving the
 * CPU perfectly healthy — which is the symptom being chased. Diagnosing that
 * through the full-system sim costs ~20 minutes per look; this runs in
 * seconds and isolates the two modules that actually matter.
 *
 * ORACLE: fill the packed framebuffer so every 16-bit word encodes its own
 * location: data = {row[7:0], col[7:0]}. At 8bpp each word is two pixels, so
 * the scanned-out palette index sequence for row R must be
 *      R, 0,  R, 1,  R, 2,  R, 3, ...
 * i.e. EVEN pixels give the row number and ODD pixels give the column. Any
 * row-addressing error shows up as a wrong even pixel; any line-buffer or
 * disp_idx error shows up as a wrong odd pixel or a wrapped column.
 *
 * Run (from verilator/):
 *   verilator --binary --timing -Mdir obj_tb_vram_scan -o Vtb_vram_scan \
 *       tb_vram_scan.v ../rtl/maclc_v8_video.sv ../rtl/vram_bram.sv \
 *       --top-module tb_vram_scan -Wno-WIDTH -Wno-WIDTHEXPAND \
 *       -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-PINMISSING
 *   ./obj_tb_vram_scan/Vtb_vram_scan
 */

`timescale 1ns/1ps

module tb_vram_scan;

	reg clk = 0;
	always #31.9 clk = ~clk;          // ~15.67 MHz pixel clock

	reg reset = 1;

	// ---- video mode under test -------------------------------------------
	// 3'd3 = 8bpp, the Pocket maximum. words_per_line must come out 256.
	reg [2:0] video_mode = 3'd3;

	wire [10:0] words_per_line;
	wire [16:0] vram_raddr;
	wire [15:0] vram_rdata;
	wire  [7:0] palette_addr;
	wire        de, hsync, vsync, hblank, vblank, ce_pix;
	wire  [7:0] vga_r, vga_g, vga_b;

	// ---- framebuffer ------------------------------------------------------
	reg  [16:0] a_addr = 0;
	reg  [15:0] a_din  = 0;
	reg   [1:0] a_be   = 2'b00;
	reg         a_we   = 0;

	vram_bram fb (
		.a_clk  (clk),
		.a_addr (a_addr),
		.a_din  (a_din),
		.a_be   (a_be),
		.a_we   (a_we),
		.a_dout (),
		.b_clk  (clk),
		.b_addr (vram_raddr),
		.b_dout (vram_rdata)
	);

	maclc_v8_video dut (
		.clk_sys          (clk),      // FPGA config: this IS the pixel clock
		.clk8_en_p        (1'b0),
		.pix_ce           (1'b1),
		.reset            (reset),
		.video_mode       (video_mode),
		.monitor_id       (4'h2),
		.test_bypass_vram (1'b0),
		.test_pattern_sel (2'b00),
		.hsync (hsync), .vsync (vsync), .hblank (hblank), .vblank (vblank),
		.vga_r (vga_r), .vga_g (vga_g), .vga_b (vga_b),
		.de (de), .ce_pix (ce_pix),
		.palette_addr (palette_addr),
		.palette_data (24'h000000),
		.words_per_line (words_per_line),
		.vram_raddr (vram_raddr),
		.vram_rdata (vram_rdata)
	);

	integer row, col, errors, checked;
	integer px_in_line, cur_row;
	reg [7:0] expect_idx;

	// Fill the packed framebuffer: word (row*256 + col) = {row, col}.
	task fill_framebuffer;
		begin
			for (row = 0; row < 384; row = row + 1) begin
				for (col = 0; col < 256; col = col + 1) begin
					@(negedge clk);
					a_addr <= row * 256 + col;
					a_din  <= {row[7:0], col[7:0]};
					a_be   <= 2'b11;
					a_we   <= 1'b1;
				end
			end
			@(negedge clk);
			a_we <= 1'b0;
			a_be <= 2'b00;
		end
	endtask

	initial begin
		errors  = 0;
		checked = 0;

		repeat (4) @(negedge clk);
		reset = 0;

		$display("tb_vram_scan: filling 384x256 packed words...");
		fill_framebuffer;
		$display("tb_vram_scan: words_per_line = %0d (expect 256 for 8bpp@512)",
		         words_per_line);
		if (words_per_line !== 11'd256) begin
			$display("FAIL: words_per_line = %0d, expected 256", words_per_line);
			errors = errors + 1;
		end

		// Let the frame restart cleanly, then verify the first few lines.
		@(posedge vblank);
		@(negedge vblank);

		px_in_line = 0;
		cur_row    = 0;

		// Sample palette_addr during active video for the first 3 rows.
		while (cur_row < 3) begin
			@(posedge clk);
			if (de) begin
				// even pixel -> row byte, odd pixel -> column byte
				expect_idx = (px_in_line[0] == 1'b0)
				             ? cur_row[7:0]
				             : ((px_in_line >> 1) & 8'hFF);
				if (px_in_line < 16) begin
					if (palette_addr !== expect_idx) begin
						$display("FAIL row %0d px %0d: palette_addr=%02h expected=%02h",
						         cur_row, px_in_line, palette_addr, expect_idx);
						errors = errors + 1;
					end else begin
						$display("  ok  row %0d px %0d: %02h", cur_row, px_in_line, palette_addr);
					end
					checked = checked + 1;
				end
				px_in_line = px_in_line + 1;
			end else if (px_in_line != 0) begin
				if (px_in_line !== 512) begin
					$display("FAIL row %0d: active line was %0d px, expected 512",
					         cur_row, px_in_line);
					errors = errors + 1;
				end else begin
					$display("  ok  row %0d: 512 active pixels", cur_row);
				end
				px_in_line = 0;
				cur_row    = cur_row + 1;
			end
		end

		$display("");
		$display("tb_vram_scan: %0d checks, %0d errors", checked, errors);
		if (errors == 0) $display("PASS");
		else             $display("FAIL");
		$finish;
	end

	// Watchdog: a broken scanout must not hang the run.
	initial begin
		#80_000_000;
		$display("FAIL: timeout (no vblank / de activity)");
		$finish;
	end

endmodule
