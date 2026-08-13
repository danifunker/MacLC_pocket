# Slow single-word peeks: read one ROM word in isolation via a lg=0 ROMV scan.
#   quartus_stp_tcl -t scripts/romv_peek.tcl 9E0 9E1 8BC 100
source scratch/rom_words.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
start_insystem_source_probe -device_name $dev -hardware_name $hw
foreach ah $quartus(args) {
    scan $ah %x a
    # three isolated reads of the same word, well separated in time
    set vals {}
    for {set r 0} {$r < 3} {incr r} {
        write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {((0x500000 + $a) << 5)}]] -value_in_hex
        write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {(1 << 31) | ((0x500000 + $a) << 5)}]] -value_in_hex
        for {set i 0} {$i < 10} {incr i} {
            scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
            if {($st & 3) == 2} { break }
        }
        scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
        lappend vals [format %04X [expr {$s & 0xFFFF}]]
    }
    puts [format "addr %05X: slow reads = %s   expected = %04X" $a $vals [lindex $ROMW $a]]
}
end_insystem_source_probe
