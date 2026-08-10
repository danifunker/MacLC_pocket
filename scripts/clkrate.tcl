# Measure effective core clock via VBL tick rate (PVID[31:24], 60.15 Hz healthy).
# Usage: quartus_stp_tcl -t scratch/clkrate.tcl [window_ms]
set win 3000
if {$argc >= 1} { set win [lindex $argv 0] }
set hw ""
foreach h [get_hardware_names] { if {[string match "DE-SoC*" $h]} { set hw $h; break } }
if {$hw eq ""} {
    foreach h [get_hardware_names] {
        if {![catch {get_device_names -hardware_name $h} devs]} {
            foreach d $devs { if {[string match "*5CSE*" $d]} { set hw $h; break } }
        }
        if {$hw ne ""} break
    }
}
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
set idx -1
set i 0
foreach inst $info { if {[lindex $inst 3] eq "PVID"} { set idx $i }; incr i }
if {$idx < 0} { puts "NO PVID PROBE"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
proc vbl {} {
    global idx
    set v [read_probe_data -instance_index $idx -value_in_hex]
    scan $v %x n
    return [expr {($n >> 24) & 0xFF}]
}
set v0 [vbl]
set t0 [clock milliseconds]
after $win
set v1 [vbl]
set t1 [clock milliseconds]
end_insystem_source_probe
set dt [expr {($t1 - $t0) / 1000.0}]
set dv [expr {($v1 - $v0) & 0xFF}]
set rate [expr {$dv / $dt}]
puts [format "VBL_RATE %.2f Hz over %.2f s (ticks=%d) — healthy=60.15, ratio=%.3f" $rate $dt $dv [expr {$rate / 60.15}]]
