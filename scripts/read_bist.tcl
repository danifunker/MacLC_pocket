# Read the SDRAM BIST probe (added 2026-08-11, never read until now).
#   quartus_stp_tcl -t scripts/read_bist.tcl
# dbg_bist = { bist_st[1:0], bist_ran, bist_errs[15:0], bist_first[12:0] }
#   bist_st: 0 idle, 1 write pass, 2 read/compare pass, 3 done
#   bist_errs: mismatch count (saturates at 0xFFFF)
#   bist_first: bist_addr[12:0] of first failing sample (0x1FFF = none)
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(BIST)]} { puts "NO BIST probe in this build"; exit 0 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
scan [read_probe_data -instance_index $idx(BIST) -value_in_hex] %x v
set v [expr {$v & 0xFFFFFFFF}]
set st    [expr {($v >> 30) & 0x3}]
set ran   [expr {($v >> 29) & 0x1}]
set errs  [expr {($v >> 13) & 0xFFFF}]
set first [expr {$v & 0x1FFF}]
puts "=============== SDRAM BIST (CPU-style write/read, 8192 samples x 512-word stride, 8 MB) ==============="
puts [format "  raw = 0x%08X" $v]
puts [format "  state    : %d  (0=never started, 1=writing, 2=reading, 3=DONE)" $st]
puts [format "  ran      : %d" $ran]
puts [format "  errors   : %d %s" $errs [expr {$errs == 0xFFFF ? "(SATURATED - >=65535)" : ""}]]
if {$first == 0x1FFF} {
    puts "  first bad: none"
} else {
    # bist_addr = {bist_idx,10'd0} >> 1 with stride 512 -> sample index = first>>? ; report raw field
    puts [format "  first bad: sample field 0x%04X (word addr = field << 9)" $first]
}
if {$st == 3 && $errs == 0} {
    puts "  -> SDRAM write+read PASSES under CPU-style access across the 8 MB range."
} elseif {$st == 3} {
    puts "  -> SDRAM BIST FOUND ERRORS - memory integrity is bad at this phase/build."
} elseif {$st == 0} {
    puts "  -> BIST never started (needs rom_loaded && in-reset window)."
} else {
    puts "  -> BIST wedged mid-run - the read/write handshake into pocket_sdram is suspect."
}
end_insystem_source_probe
