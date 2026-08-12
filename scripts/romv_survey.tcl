# Survey the ROM region's current SDRAM content against boot0.rom using ROMV
# v3 range scans: histogram at lg=13 (32 ranges), then binary-descend ONLY
# dirty ranges, capped, with flip-direction stats. Machine stays in reset
# throughout if rom_loaded=0 (post-push, no reload) — content is frozen.
#   quartus_stp_tcl -t scripts/romv_survey.tcl [maxbad] [startrange] [endrange]
# startrange/endrange are 8K-word histogram range indices (0..31 inclusive).
source scratch/rom_words.tcl

set maxbad 400
set startr 0
set endr   31
if {[llength $quartus(args)] > 0} { set maxbad [lindex $quartus(args) 0] }
if {[llength $quartus(args)] > 1} { set startr [lindex $quartus(args) 1] }
if {[llength $quartus(args)] > 2} { set endr   [lindex $quartus(args) 2] }

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

# cumulative sums for O(1) expected-range sums
puts "building cumulative sums..."
set CUM [list 0]
set acc 0
foreach w $ROMW { incr acc $w; lappend CUM $acc }

proc exp_sum {base lg} { global CUM
    expr {([lindex $CUM [expr {$base + (1 << $lg)}]] - [lindex $CUM $base]) & 0xFFFFFFFF}
}
set nscans 0
proc hw_scan_once {base lg} { global idx
    write_source_data -instance_index $idx(ROMV) -value [format "0x%06X" [expr {($base << 5) | $lg}]] -value_in_hex
    write_source_data -instance_index $idx(ROMV) -value [format "0x%06X" [expr {(1 << 23) | ($base << 5) | $lg}]] -value_in_hex
    for {set i 0} {$i < 80} {incr i} {
        after 20
        scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
        if {($st & 3) == 2} { break }
    }
    if {($st & 3) != 2} { return -1 }
    scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
    return [expr {$s & 0xFFFFFFFF}]
}
proc hw_scan {base lg} { global nscans
    incr nscans
    # transient JTAG hiccups happen (~1 in 500 scans); re-arm and retry
    for {set try 0} {$try < 4} {incr try} {
        set s [hw_scan_once $base $lg]
        if {$s >= 0} { return $s }
        puts "  (scan retry base=$base lg=$lg)"
        after 200
    }
    puts "SCAN WEDGED base=$base lg=$lg after 4 tries"
    exit 1
}

set bad {}
set capped 0
proc search {base lg} { global bad ROMW maxbad capped
    if {$capped} { return }
    if {[llength $bad] >= $maxbad} { set capped 1; return }
    set h [hw_scan $base $lg]
    set e [exp_sum $base $lg]
    if {$h == $e} { return }
    if {$lg == 0} {
        set expect [lindex $ROMW $base]
        puts [format "BAD addr=%05X (byte +%06X) stored=%04X expected=%04X xor=%04X" \
            $base [expr {$base * 2}] $h $expect [expr {$h ^ $expect}]]
        lappend bad [list $base $h $expect]
        return
    }
    set half [expr {$lg - 1}]
    search $base $half
    search [expr {$base + (1 << $half)}] $half
}

# ---- pass 1: 32-range histogram at lg=13 (8192 words each) ----
puts "histogram (ranges $startr..$endr of 8K words):"
set dirty {}
for {set r $startr} {$r <= $endr} {incr r} {
    set base [expr {$r * 8192}]
    set h [hw_scan $base 13]
    set e [exp_sum $base 13]
    if {$h != $e} {
        lappend dirty $base
        puts [format "  range %2d @%05X: DIRTY (stored %08X expected %08X delta %08X)" \
            $r $base $h $e [expr {($h - $e) & 0xFFFFFFFF}]]
    }
}
puts [format "dirty ranges: %d / 32" [llength $dirty]]

# ---- pass 2: descend dirty ranges only ----
foreach base $dirty {
    if {$capped} { break }
    search $base 13
}

# ---- stats ----
puts "===================="
if {$capped} {
    puts [format "CAPPED at %d bad words (more exist) after %d scans" [llength $bad] $nscans]
} else {
    puts [format "TOTAL BAD WORDS: %d (%d scans)" [llength $bad] $nscans]
}
if {[llength $bad] > 0} {
    set up 0; set down 0; set mixed 0
    array set abit {}
    array set dbit {}
    for {set b 0} {$b < 18} {incr b} { set abit($b) 0 }
    for {set b 0} {$b < 16} {incr b} { set dbit($b) 0 }
    foreach rec $bad {
        lassign $rec adr st ex
        set gained [expr {$st & ~$ex & 0xFFFF}]
        set lost   [expr {~$st & $ex & 0xFFFF}]
        if {$gained && !$lost} { incr up } elseif {$lost && !$gained} { incr down } else { incr mixed }
        for {set b 0} {$b < 18} {incr b} { if {$adr & (1 << $b)} { incr abit($b) } }
        set x [expr {$st ^ $ex}]
        for {set b 0} {$b < 16} {incr b} { if {$x & (1 << $b)} { incr dbit($b) } }
    }
    puts [format "flip direction: pure 0->1: %d   pure 1->0: %d   mixed: %d" $up $down $mixed]
    set n [llength $bad]
    puts "addr bit set-counts (bit: count/total):"
    for {set b 17} {$b >= 0} {incr b -1} { puts -nonewline [format " a%d:%d" $b $abit($b)] }
    puts ""
    puts "data bit flip-counts:"
    for {set b 15} {$b >= 0} {incr b -1} { puts -nonewline [format " d%d:%d" $b $dbit($b)] }
    puts ""
}
write_source_data -instance_index $idx(ROMV) -value 0x000000 -value_in_hex
end_insystem_source_probe
