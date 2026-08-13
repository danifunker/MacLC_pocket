# ROMV v4: sum an arbitrary SDRAM word range (one scan; ~instant for small
# lg, ~2.5 s for lg=23 = the whole part). Compare against expected sums
# computed offline from the source file.
#   quartus_stp_tcl -t scripts/ramv_sum.tcl <hex word base> <log2len> [n]
# Runs n scans (default 3) so repeat-scan stability comes for free.
set base 0
set lg   9
set n    3
if {[llength $quartus(args)] > 0} { scan [lindex $quartus(args) 0] %x base }
if {[llength $quartus(args)] > 1} { set lg [lindex $quartus(args) 1] }
if {[llength $quartus(args)] > 2} { set n  [lindex $quartus(args) 2] }

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {ROMV RVSU RVAX} { if {![info exists idx($need)]} { puts "MISSING $need (old fabric?)"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

for {set r 1} {$r <= $n} {incr r} {
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {($base << 5) | $lg}]] -value_in_hex
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {(1 << 31) | ($base << 5) | $lg}]] -value_in_hex
    set st 0
    for {set i 0} {$i < 400} {incr i} {
        after 20
        scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
        if {($st & 3) == 2} { break }
    }
    scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
    scan [read_probe_data -instance_index $idx(RVAX) -value_in_hex] %x a
    puts [format "scan %d: base=%06X lg=%d  sum=%08X axsum=%08X %s" \
        $r $base $lg [expr {$s & 0xFFFFFFFF}] [expr {$a & 0xFFFFFFFF}] \
        [expr {($st & 3) == 2 ? "" : "(DID NOT COMPLETE)"}]]
}
end_insystem_source_probe
