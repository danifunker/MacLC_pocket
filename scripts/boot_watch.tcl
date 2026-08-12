# Rapidly resample the cold-boot probes and report what is MOVING.
# A single read cannot tell a stalled machine from a spinning one; this can.
#
#   quartus_stp_tcl -t scripts/boot_watch.tcl
#
# Prints one line per distinct BOOT value seen, plus counter deltas, so a
# frozen machine shows exactly one line and a looping one shows several.

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
if {$hw eq ""} { puts "NO CABLE"; exit 1 }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
if {$dev eq ""} { puts "NO DEVICE"; exit 1 }

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
start_insystem_source_probe -device_name $dev -hardware_name $hw

proc rd {name} {
    global idx
    if {![info exists idx($name)]} { return -1 }
    scan [read_probe_data -instance_index $idx($name) -value_in_hex] %x n
    return $n
}

set N 40
array set seen {}
set order {}
array set aseen {}
set aorder {}
set first_romc [rd ROMC]
set first_brgc [rd BRGC]
set first_popc [rd POPC]
set first_cpuc [rd CPUC]

for {set i 0} {$i < $N} {incr i} {
    set b [rd BOOT]
    if {![info exists seen($b)]} { set seen($b) 0; lappend order $b }
    incr seen($b)
    set a [rd CPUA]
    if {$a >= 0} {
        set pc [expr {$a & 0xFFFFFF}]
        if {![info exists aseen($pc)]} { set aseen($pc) 0; lappend aorder $pc }
        incr aseen($pc)
    }
}
set last_cpuc [rd CPUC]

# ---- CPU liveness: the question a frozen BOOT bus cannot answer -----------
if {$first_cpuc >= 0} {
    set dcyc [expr {$last_cpuc - $first_cpuc}]
    puts ""
    puts "=============== CPU LIVENESS ==============="
    puts [format "  bus cycles: %d -> %d   (delta %d)" $first_cpuc $last_cpuc $dcyc]
    if {$dcyc == 0} {
        puts "  VERDICT: CPU IS STOPPED. Not a poll loop -- no bus cycles at all."
        puts "           Either halted (double bus fault) or held in reset."
        set a [rd CPUA]
        puts [format "           last addr=0x%06X  AS=%d DTACK=%d RW=%d BERR=%d rst_n=%d overlay=%d" \
            [expr {$a & 0xFFFFFF}] [expr {($a>>28)&1}] [expr {($a>>29)&1}] \
            [expr {($a>>30)&1}] [expr {($a>>25)&1}] [expr {($a>>27)&1}] [expr {($a>>31)&1}]]
    } else {
        puts "  VERDICT: CPU IS EXECUTING. Addresses touched while sampling:"
        set shown 0
        foreach pc $aorder {
            if {$shown >= 12} { puts "    ... and [expr {[llength $aorder]-12}] more"; break }
            puts [format "    0x%06X   x%d" $pc $aseen($pc)]
            incr shown
        }
        if {[llength $aorder] <= 4} {
            puts "  -> a very tight address set = the polling loop we are stuck in."
        }
    }
}
set last_romc [rd ROMC]
set last_brgc [rd BRGC]
set last_popc [rd POPC]

puts ""
puts "sampled BOOT $N times -> [llength $order] distinct value(s)"
puts ""
foreach b $order {
    puts [format "  0x%08X  seen %2d/%d   overlay=%d n_reset=%d hs_done=%d treq=%d tip=%d back=%d rst680=%d | SRact=%d cb1=%d cb2=%d SR=0x%02X cnt=%d" \
        $b $seen($b) $N \
        [expr {($b>>27)&1}] [expr {($b>>26)&1}] [expr {($b>>19)&1}] \
        [expr {($b>>20)&1}] [expr {($b>>21)&1}] [expr {($b>>22)&1}] [expr {($b>>23)&1}] \
        [expr {($b>>13)&1}] [expr {($b>>15)&1}] [expr {($b>>16)&1}] \
        [expr {($b>>3)&0xFF}] [expr {$b&0x7}]]
}
puts ""
puts [format "  ROMC %d -> %d   (delta %d)" $first_romc $last_romc [expr {$last_romc-$first_romc}]]
puts [format "  BRGC %d -> %d   (delta %d)" $first_brgc $last_brgc [expr {$last_brgc-$first_brgc}]]
puts [format "  POPC %d -> %d   (delta %d)" $first_popc $last_popc [expr {$last_popc-$first_popc}]]
puts ""
if {[llength $order] == 1} {
    puts "  VERDICT: FROZEN. Nothing in the boot bus is moving at all."
} else {
    puts "  VERDICT: MOVING. The machine is executing/cycling, not hung on one state."
}
end_insystem_source_probe
