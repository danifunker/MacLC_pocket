# FRZE lever (buildAD): freeze the machine (hold reset, RAM intact) for the
# ROMV v4 oracle. SDRAM refresh keeps running; the corpse keeps.
#   quartus_stp_tcl -t scripts/frze.tcl status      read {frozen, dlv}
#   quartus_stp_tcl -t scripts/frze.tcl on          manual freeze NOW
#   quartus_stp_tcl -t scripts/frze.tcl off         release (also disarms)
#   quartus_stp_tcl -t scripts/frze.tcl arm <N>     auto-freeze at dlv >= N
#   quartus_stp_tcl -t scripts/frze.tcl arm +<K>    ... at current dlv + K
# The delivery counter is CUMULATIVE across rounds (8-bit, wraps): the +K
# form reads it first. Arm BEFORE jboot; the hit latches until 'off'.
set cmd "status"
set arg ""
if {[llength $quartus(args)] > 0} { set cmd [lindex $quartus(args) 0] }
if {[llength $quartus(args)] > 1} { set arg [lindex $quartus(args) 1] }

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(FRZE)]} { puts "MISSING FRZE (pre-buildAD fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw

proc rd {} { global idx
    scan [read_probe_data -instance_index $idx(FRZE) -value_in_hex] %x p
    return [list [expr {($p >> 8) & 1}] [expr {$p & 0xFF}]]
}

switch -- $cmd {
    on {
        write_source_data -instance_index $idx(FRZE) -value 0x200 -value_in_hex
        lassign [rd] f d
        puts "FROZEN=$f dlv=$d (manual)"
    }
    off {
        write_source_data -instance_index $idx(FRZE) -value 0x000 -value_in_hex
        lassign [rd] f d
        puts "FROZEN=$f dlv=$d (released + disarmed)"
    }
    arm {
        lassign [rd] f d
        if {[string index $arg 0] eq "+"} {
            set thr [expr {($d + [string range $arg 1 end]) & 0xFF}]
        } else {
            set thr [expr {$arg & 0xFF}]
        }
        write_source_data -instance_index $idx(FRZE) -value [format "0x%03X" [expr {0x100 | $thr}]] -value_in_hex
        puts "ARMED at dlv >= $thr (current dlv=$d, frozen=$f)"
    }
    default {
        lassign [rd] f d
        puts "FROZEN=$f dlv=$d"
    }
}
end_insystem_source_probe
