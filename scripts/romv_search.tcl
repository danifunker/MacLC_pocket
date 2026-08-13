# Binary-search the ROM region for corrupt words using ROMV v2 range scans.
# Needs scratch/rom_words.tcl (gen_rom_words.py). Finds every mismatching
# word's address and the stored-vs-expected values.
#   quartus_stp_tcl -t scripts/romv_search.tcl
source scratch/rom_words.tcl

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {ROMV RVSU RVAX} { if {![info exists idx($need)]} { puts "MISSING $need"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

# hardware range scan: returns the sum of len=2^lg words starting at base
proc hw_scan {base lg} { global idx
    # go=0 first (arm), then go=1 with the range (rising edge starts)
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {((0x500000 + $base) << 5) | $lg}]] -value_in_hex
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {(1 << 31) | ((0x500000 + $base) << 5) | $lg}]] -value_in_hex
    for {set i 0} {$i < 25} {incr i} {
        scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
        if {($st & 3) == 2} { break }
    }
    scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
    return [expr {$s & 0xFFFFFFFF}]
}
# expected sum over [base, base+2^lg)
proc exp_sum {base lg} { global ROMW
    set n [expr {1 << $lg}]
    set s 0
    for {set k 0} {$k < $n} {incr k} { incr s [lindex $ROMW [expr {$base + $k}]] }
    return [expr {$s & 0xFFFFFFFF}]
}

set bad {}
proc search {base lg} { global bad ROMW idx
    set h [hw_scan $base $lg]
    set e [exp_sum $base $lg]
    if {$h == $e} { return }
    if {$lg == 0} {
        set stored $h
        set expect [lindex $ROMW $base]
        puts [format "BAD WORD: addr=%05X (byte %06X)  stored=%04X expected=%04X  xor=%04X" \
            $base [expr {$base * 2}] $stored $expect [expr {$stored ^ $expect}]]
        lappend bad [list $base $stored $expect]
        return
    }
    set half [expr {$lg - 1}]
    search $base $half
    search [expr {$base + (1 << $half)}] $half
}

puts "searching (adaptive descent, ~seconds per level)..."
search 0 18
puts [format "TOTAL BAD WORDS: %d" [llength $bad]]
if {[llength $bad] > 0} {
    puts "address bit analysis (word addresses):"
    foreach b $bad {
        set adr [lindex $b 0]
        puts [format "  %05X = %018b" $adr $adr]
    }
}
end_insystem_source_probe
