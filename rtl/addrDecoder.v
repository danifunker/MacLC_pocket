/*
    Mac LC Memory Map (V8 System ASIC)
    Based on MAME v8.cpp and maclc.cpp

    Address masking: CPU uses global_mask(0x80ffffff) - bits 30-24 are ignored
    V8 internal addresses are offset by 0xA00000 for CPU address space

    ($000000 - $9FFFFF) RAM up to 10MB
        First 2MB motherboard RAM always at $800000-$9FFFFF
        SIMM RAM starts at $000000
        At boot, ROM is overlaid here until first ROM area access

    ($A00000 - $AFFFFF) ROM 512KB-1MB
        Reading from this area disables the overlay

    ($F00000 - $F01FFF) VIA1
        The VIA is on the upper byte of the data bus, so use even-addressed byte accesses only.
        16 VIA registers with 512-byte stride (A12-A9 select register)

    ($F04000 - $F05FFF) SCC
        Serial Communication Controller
        2-bit register addressing (A1-A0)

    ($F06000 - $F07FFF) SCSI DRQ
        Pseudo-DMA data transfer window

    ($F10000 - $F11FFF) SCSI
        NCR5380 registers
        Register = (offset >> 3) & 0xF

    ($F12000 - $F13FFF) SCSI DRQ
        Additional pseudo-DMA window

    ($F14000 - $F15FFF) ASC
        Apple Sound Chip (4-channel audio)
        Not yet implemented

    ($F16000 - $F17FFF) SWIM
        Floppy controller. On the LC (V8) the SWIM is on the UPPER data byte
        (even-addressed byte accesses, _UDS), like the VIA/SCC — not the lower
        byte/_LDS as on the Mac Plus.
        Register = (offset >> 9) & 0xF  (A12-A9, $200 stride)

    ($F24000 - $F25FFF) Ariel RAMDAC
        Video palette/DAC

    ($F26000 - $F27FFF) PseudoVIA
        GPIO and interrupt controller
        Provides VBlank and slot interrupts

    ($F40000 - $FBFFFF) VRAM
        512KB video RAM
*/

module addrDecoder(
    input [23:0] address,
    input _cpuAS,
    input _cpuRW,
    input memoryOverlayOn,
    input [7:0] ram_config,       // V8 RAM config WRITTEN by ROM: bits[7:6] gate mb mirror
    input [7:0] ram_config_phys,  // PHYSICAL RAM config — real installed SIMM size
    input ram_configured,    // 1 once ROM programs V8 config; enables $0 mb mirror

    output reg selectRAM,
    output reg selectROM,
    output reg selectSCSI,
    output reg selectSCSIDMA,   // SCSI pseudo-DMA window (DRQ regions $F06000/$F12000)
    output reg selectSCC,
    output reg selectIWM,
    output reg selectASC,
    output reg selectVIA,

    // Mac LC Specific Selects
    output reg selectAriel,
    output reg selectPseudoVIA,
    output reg selectVRAM,
    output reg selectUnmapped
);

    // Decode SIMM byte size from the PHYSICAL config (real installed SIMM), NOT the
    // ROM-written register. MAME sizes the SIMM from m_ram_size; the writable config
    // only gates placement. For a 2MB machine (no SIMM) this keeps $0 a true $800000
    // mirror instead of a phantom separate SIMM bank. See addrController_top.v.
    wire [23:0] simm_byte_size = (ram_config_phys[7:6] == 2'b00) ? 24'h000000 :  // 0MB
                                  (ram_config_phys[7:6] == 2'b01) ? 24'h200000 :  // 2MB
                                  (ram_config_phys[7:6] == 2'b10) ? 24'h400000 :  // 4MB
                                                                    24'h800000;   // 8MB

    // Motherboard RAM placement (match MAME v8.cpp ram_size()): the 2MB
    // motherboard RAM is ALWAYS installed at mb_location, which sits directly
    // after any SIMM (mb_location = SIMM size). With no SIMM (config[7:6]=00)
    // the motherboard RAM lands at $000000-$1FFFFF. It is additionally
    // mirrored at $800000-$9FFFFF (the always-present V8 image). Only the 8MB
    // SIMM config (config[7:6]=11) drops the low motherboard placement.
    wire [23:0] mb_location = simm_byte_size;          // == 0 when no SIMM
    wire        mb_present  = (ram_config[7:6] != 2'b11);

    // Valid RAM ranges:
    //   SIMM:            $000000 to simm_byte_size-1 (only if SIMM present)
    //   Motherboard low: [mb_location, mb_location+2MB) (the soldered 2MB)
    //   Motherboard high:$800000-$9FFFFF (always-present 2MB mirror)
    wire in_simm_range = (ram_config_phys[7:6] != 2'b00) && (address[23:0] < simm_byte_size);
    // The motherboard-low mirror (e.g. $0-$1FFFFF when no SIMM) is gated on
    // ram_configured. MAME installs it only after the ROM programs the V8 config
    // (ram_size(data)); during the boot RAM-bank probe the map is ram_size(0xc0)
    // == $800000-$9FFFFF only. Without this gate the probe finds a phantom 2MB
    // bank at $0, whose march then clobbers the $9FFFEC descriptor table through
    // the $0<->$800000 SDRAM mirror, hanging the boot. (in_simm_range is NOT
    // gated: for SIMM configs MAME maps the real SIMM at $0 during enumeration.)
    wire in_motherboard_low = ram_configured && mb_present &&
                              (address[23:0] >= mb_location) &&
                              (address[23:0] <  (mb_location + 24'h200000));
    wire in_motherboard_range = (address[23:21] == 3'b100);  // $800000-$9FFFFF

    always @(*) begin
        // Defaults - active low accent for active state
        selectRAM = 0;
        selectROM = 0;
        selectSCSI = 0;
        selectSCSIDMA = 0;
        selectSCC = 0;
        selectIWM = 0;
        selectASC = 0;
        selectVIA = 0;
        selectAriel = 0;
        selectPseudoVIA = 0;
        selectVRAM = 0;
        selectUnmapped = 0;

        if (!_cpuAS) begin
            // ==========================================================
            // Mac LC (V8) Memory Map - CPU Addresses
            // ==========================================================

            // --- ROM ($A00000 - $AFFFFF) ---
            if (address[23:20] == 4'hA) begin
                selectROM = 1;
            end

            // --- RAM or Overlay ROM ($000000 - $9FFFFF) ---
            else if (address[23:20] < 4'hA) begin
                if (memoryOverlayOn && _cpuRW) begin
                    // Overlay active: ROM appears at $000000 for READS
                    selectROM = 1;
                end else if (in_simm_range || in_motherboard_low || in_motherboard_range) begin
                    // Normal operation: RAM only where it physically exists
                    selectRAM = 1;
                end else begin
                    // Address in $000000-$9FFFFF but no RAM here
                    selectUnmapped = 1;
                end
            end

            // --- Peripheral I/O ($F00000 - $FFFFFF) ---
            else if (address[23:20] == 4'hF) begin
                casez (address[19:12])
                    // VIA1: $F00000-$F01FFF
                    8'b0000_00??: selectVIA = 1;

                    // SCC: $F04000-$F05FFF
                    8'b0000_010?: selectSCC = 1;

                    // SCSI DRQ: $F06000-$F07FFF (pseudo-DMA window)
                    8'b0000_011?: begin selectSCSI = 1; selectSCSIDMA = 1; end

                    // SCSI: $F10000-$F11FFF (NCR5380 registers)
                    8'b0001_000?: selectSCSI = 1;

                    // SCSI DRQ: $F12000-$F13FFF (pseudo-DMA window)
                    8'b0001_001?: begin selectSCSI = 1; selectSCSIDMA = 1; end

                    // ASC: $F14000-$F15FFF
                    8'b0001_010?: selectASC = 1;

                    // SWIM/IWM: $F16000-$F17FFF
                    8'b0001_011?: selectIWM = 1;

                    // Ariel RAMDAC: $F24000-$F25FFF
                    8'b0010_010?: selectAriel = 1;

                    // PseudoVIA: $F26000-$F27FFF
                    8'b0010_011?: selectPseudoVIA = 1;

                    // VRAM: $F40000-$FBFFFF
                    // $F4xxxx = 0100, $F5xxxx = 0101, $F6xxxx = 0110, $F7xxxx = 0111
                    // $F8xxxx = 1000, $F9xxxx = 1001, $FAxxxx = 1010, $FBxxxx = 1011
                    8'b01??_????: selectVRAM = 1;  // $F40000-$F7FFFF
                    8'b10??_????: selectVRAM = 1;  // $F80000-$FBFFFF

                    default: selectUnmapped = 1;
                endcase
            end
            // Addresses $B00000-$EFFFFF are unmapped
            else begin
                selectUnmapped = 1;
            end
        end
    end
endmodule
