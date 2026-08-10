# Sample the raw cpuAddr (PADR) + bus state (PSTA) many times to catch the
# wedge loop's OPERAND read address (A0+$10) — the RAM variable the BGT spins on.
# PADR = {8'd0, cpuAddr}; PSTA bit24=AS_n, [3]=RW, [2:0]=FC, selects in [17:8].
#   quartus_stp_tcl -t scripts/sample_padr.tcl [n]
set n 400
if {$argc >= 1} { set n [lindex $argv 0] }

set hw ""
foreach h [get_hardware_names] {
    if {[string match "DE-SoC*" $h]} { set hw $h; break }
}
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
array set idx {}
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "PADR"} { set idx(PADR) $i }
    if {$nm eq "PSTA"} { set idx(PSTA) $i }
    incr i
}
start_insystem_source_probe -device_name $dev -hardware_name $hw
for {set s 0} {$s < $n} {incr s} {
    set a [read_probe_data -instance_index $idx(PADR) -value_in_hex]
    set p [read_probe_data -instance_index $idx(PSTA) -value_in_hex]
    scan $a %x av
    scan $p %x pv
    set rw [expr {($pv >> 3) & 1}]
    set as_n [expr {($pv >> 24) & 1}]
    puts [format "PADR %06X RW%d AS%d" [expr {$av & 0xFFFFFF}] $rw $as_n]
}
catch { end_insystem_source_probe -hardware_name $hw }
