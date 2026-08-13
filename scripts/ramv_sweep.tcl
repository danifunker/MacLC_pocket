# ROMV v4: sweep a word range as fixed-size window sums — the coarse pass of
# the differential-freeze workflow (freeze two deterministic rounds at
# successive delivery counts; windows whose sums differ hold that delivery's
# RAM landing; descend with ramv_sum/ramv_dump).
#   quartus_stp_tcl -t scripts/ramv_sweep.tcl [lg] [hex start] [hex end]
# Defaults: lg=15 (32K-word/64KB windows) over 0..100000 (2 MB RAM).
# Output: one line per window: "base sum axsum".
set lg    15
set start 0
set end   0x100000
if {[llength $quartus(args)] > 0} { set lg [lindex $quartus(args) 0] }
if {[llength $quartus(args)] > 1} { scan [lindex $quartus(args) 1] %x start }
if {[llength $quartus(args)] > 2} { scan [lindex $quartus(args) 2] %x end }

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

set wlen [expr {1 << $lg}]
for {set b $start} {$b < $end} {incr b $wlen} {
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {($b << 5) | $lg}]] -value_in_hex
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {(1 << 31) | ($b << 5) | $lg}]] -value_in_hex
    set st 0
    for {set i 0} {$i < 600} {incr i} {
        after 10
        scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
        if {($st & 3) == 2} { break }
    }
    scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
    scan [read_probe_data -instance_index $idx(RVAX) -value_in_hex] %x a
    puts [format "%06X %08X %08X%s" $b [expr {$s & 0xFFFFFFFF}] [expr {$a & 0xFFFFFFFF}] \
        [expr {($st & 3) == 2 ? "" : " INCOMPLETE"}]]
}
end_insystem_source_probe
