# Read the MacLC_Pocket cold-boot forensics probes and decode them.
#
#   quartus_stp_tcl -t scripts/boot_state.tcl    (or: bash scripts/read_boot_probes.sh)
#
# Deck (instantiated only when USE_BOOT_ISSP is set in src/fpga/ap_core.qsf):
#   BOOT  dbg_boot_bus       mac_lc_pocket.sv
#   ROMC  words retired into SDRAM at the ROM window
#   FLPC  words retired into the floppy window
#   BRGC  words the Analogue OS handed the loader   (apf_bridge_loader)
#   POPC  words the loader popped toward the machine
#   DLST  download/arbitration status word          (core_top.sv)
#
# Adapted from ../MacLC_MiSTer scripts/cpu_state.tcl. Two differences that
# matter: the Pocket is a 5CEBA4 behind a plain USB-Blaster (not a DE-SoC
# USB-Blaster II behind a 5CSE), and there is no HPS, so this is the only
# on-target introspection the project has.

# ---- cable + device ------------------------------------------------------
set hw ""
foreach h [get_hardware_names] {
    if {[string match "USB-Blaster*" $h]} { set hw $h; break }
}
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
if {$hw eq ""} { puts "NO CABLE - is the USB-Blaster plugged in and the driver loaded?"; exit 1 }

set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CEBA4*" $d] || [string match "*5CE*" $d]} { set dev $d; break }
}
if {$dev eq ""} { puts "NO DEVICE on $hw - is the Pocket powered on with the core running?"; exit 1 }
puts "cable = $hw"
puts "device= $dev"

# ---- instance table ------------------------------------------------------
if {[catch {get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw} info]} {
    puts ""
    puts "NO ISSP INSTANCES FOUND."
    puts "The running bitstream has no probe deck. Rebuild with USE_BOOT_ISSP"
    puts "set in src/fpga/ap_core.qsf and reprogram."
    exit 1
}
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }

start_insystem_source_probe -device_name $dev -hardware_name $hw

proc rd {name} {
    global idx
    if {![info exists idx($name)]} { return -1 }
    set v [read_probe_data -instance_index $idx($name) -value_in_hex]
    scan $v %x n
    return $n
}
proc bit {v n} { return [expr {($v >> $n) & 1}] }
proc yn  {b}   { return [expr {$b ? "YES" : "no "}] }

set boot [rd BOOT]
set romc [rd ROMC]
set flpc [rd FLPC]
set brgc [rd BRGC]
set popc [rd POPC]
set dlst [rd DLST]

puts ""
puts "=============== DOWNLOAD PATH (the ROM-reload question) ==============="
puts [format "  BRGC  words OS -> loader      : %10d  (0x%08X)" $brgc $brgc]
puts [format "  POPC  words loader -> machine : %10d  (0x%08X)" $popc $popc]
puts [format "  ROMC  words -> SDRAM (ROM)    : %10d  (0x%08X)" $romc $romc]
puts [format "  FLPC  words -> SDRAM (floppy) : %10d  (0x%08X)" $flpc $flpc]
puts ""
puts "  A 512 KB boot0.rom is 262144 words (0x40000)."
if {$brgc > 0 && $romc == $brgc && $popc == $brgc} {
    puts "  -> all three AGREE: the download path delivered everything it was given."
} elseif {$brgc > 0 && $popc < $brgc} {
    puts [format "  -> LOSS IN THE LOADER FIFO: %d words pushed, only %d popped." $brgc $popc]
} elseif {$popc > 0 && $romc < $popc} {
    puts [format "  -> LOSS AT THE SDRAM ARBITER: %d popped, only %d retired." $popc $romc]
} elseif {$brgc == 0} {
    puts "  -> THE OS NEVER DELIVERED A SINGLE WORD. The ROM slot was not"
    puts "     streamed to this configuration at all."
}


# ---- ROM CONTENT verification --------------------------------------------
set rsum [rd RSUM]
set raxs [rd RAXS]
if {$rsum >= 0} {
    puts ""
    puts "=============== ROM CONTENT (not just word count) ==============="
    puts [format "  sum of data words     : 0x%08X   expect 0x350F8EEE" $rsum]
    puts [format "  sum of (index ^ data) : 0x%08X   expect 0xF486F3D8" $raxs]
    set rsum [expr {$rsum & 0xFFFFFFFF}]
    set raxs [expr {$raxs & 0xFFFFFFFF}]
    if {$rsum == 0x350F8EEE && $raxs == 0xF486F3D8} {
        puts "  -> ROM CONTENT AND ADDRESSING ARE BOTH CORRECT."
    } elseif {$rsum == 0x350F8EEE} {
        puts "  -> data is right but ADDRESSING IS WRONG (words landed at wrong offsets)."
    } elseif {$raxs == 0xF486F3D8} {
        puts "  -> addressing right, data wrong (unlikely combination - check the probe)."
    } else {
        puts "  -> ROM DID NOT LAND CORRECTLY. Content and/or addressing are corrupt."
        puts "     (The boot0.rom FILE is verified good: embedded checksum matches.)"
    }
}

set dhld [rd DHLD]
if {$dhld >= 0} {
    puts ""
    puts [format "  download held for SDRAM init : %d clk_sys cycles (%.1f us)" $dhld [expr {$dhld/32.5}]]
    if {$dhld > 0} {
        puts "  -> THE RACE WAS REAL: words were ready before SDRAM could store them."
        puts "     Without the sdram_ready gate those writes were silently discarded."
    } else {
        puts "  -> SDRAM was already initialised when the download began."
    }
}


# ---- SDRAM BIST ----------------------------------------------------------
set bist [rd BIST]
if {$bist >= 0} {
    set st    [expr {($bist >> 30) & 0x3}]
    set ran   [expr {($bist >> 29) & 0x1}]
    set errs  [expr {($bist >> 13) & 0xFFFF}]
    set first [expr {$bist & 0x1FFF}]
    puts ""
    puts "=============== SDRAM BIST (CPU-style write then read) ==============="
    set names {0 idle 1 writing 2 reading 3 done}
    puts [format "  state=%d (%s)  completed=%s" $st [dict get $names $st] [yn $ran]]
    if {$ran} {
        puts [format "  mismatches: %d of 8192 samples" $errs]
        if {$errs == 0} {
            puts "  -> RAM WRITE+READ IS CORRECT across 8 MB. SDRAM is not the fault."
        } elseif {$errs >= 8192} {
            puts "  -> EVERY sample failed. RAM writes are not working at all."
        } else {
            puts [format "  -> PARTIAL FAILURE. first bad sample index %d" $first]
            puts "     A clean low range with failures higher up = the SIMM range."
        }
    } else {
        puts "  -> BIST has not run (needs rom_loaded, no download, machine in reset)."
    }
}

puts ""
puts "=============== ARBITRATION (DLST = 0x[format %08X $dlst]) ==============="
puts [format "  pll_locked            %s" [yn [bit $dlst 0]]]
puts [format "  reset_n (APF host)    %s" [yn [bit $dlst 1]]]
puts [format "  dio_index             %d      <- machine's reset hold needs 0 for ROM" [expr {($dlst >> 2) & 0xFF}]]
puts [format "  dio_download (OR)     %s" [yn [bit $dlst 10]]]
puts [format "  ldr_dio_download      %s" [yn [bit $dlst 11]]]
puts [format "  bd_dio_download       %s   <- stuck high = blockdev envelope bug" [yn [bit $dlst 12]]]
puts [format "  rom_done / flp_allow  %s" [yn [bit $dlst 13]]]
puts [format "  loader_busy           %s" [yn [bit $dlst 14]]]
puts [format "  loader_active         %s" [yn [bit $dlst 15]]]
puts [format "  dataslot_requestwrite %s" [yn [bit $dlst 16]]]
puts [format "  dataslot_allcomplete  %s" [yn [bit $dlst 17]]]
puts [format "  PRAM load resolved    %s   <- if 'no', the 68020 is HELD IN RESET" [yn [bit $dlst 18]]]
puts [format "  blockdev FSM state    %2d  (0 idle 3 req 4 wait-on-OS 13-15 pram-copy 16-18 pram-validate)" [expr {($dlst >> 19) & 0x1F}]]

puts ""
puts "=============== BOOT STATE (BOOT = 0x[format %08X $boot]) ==============="
puts [format "  memoryOverlayOn       %s   <- must go 'no' for a healthy boot" [yn [bit $boot 27]]]
puts [format "  n_reset released      %s" [yn [bit $boot 26]]]
puts [format "  rom_loaded latched    %s" [yn [bit $boot 25]]]
puts ""
puts "  --- Egret handoff (this is the CPU-vs-Egret reset ordering) ---"
puts [format "  egret running         %s" [yn [bit $boot 17]]]
puts [format "  port_test_done        %s" [yn [bit $boot 18]]]
puts [format "  handshake_done        %s   <- did the Egret handshake ever finish?" [yn [bit $boot 19]]]
puts [format "  treq / tip / byteack  %d / %d / %d" [bit $boot 20] [bit $boot 21] [bit $boot 22]]
puts [format "  reset_680x0 (hold)    %s   <- 1 = Egret still holding the 68020" [yn [bit $boot 23]]]
puts [format "  cpu_reset_out         %s" [yn [bit $boot 24]]]
puts ""
puts "  --- VIA shift register (Egret serial link) ---"
puts [format "  SR active / dir       %d / %d" [bit $boot 13] [bit $boot 14]]
puts [format "  cb1 / cb2             %d / %d" [bit $boot 15] [bit $boot 16]]
puts [format "  shift_reg             0x%02X" [expr {($boot >> 3) & 0xFF}]]
puts [format "  bit_cnt               %d" [expr {$boot & 0x7}]]
puts ""
puts "  (bits 11/12 edge_pending/fall_pending are NOT read - those registers"
puts "   have no functional fanout in this via6522.sv; see RESUME.md SS6.)"
puts ""

end_insystem_source_probe
