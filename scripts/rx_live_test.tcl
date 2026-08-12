# Send one '*' then rapidly poll SCCS: watch rx_delivered and rx_nonempty live.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
start_insystem_source_probe -device_name $dev -hardware_name $hw
# toggle bit 8 relative to the arg (alternate 1/0 across runs via arg)
set tog [lindex $quartus(args) 0]
if {$tog eq ""} { set tog 1 }
write_source_data -instance_index $idx(STMC) -value [format "0x%03X" [expr {($tog << 8) | 0x2A}]] -value_in_hex
for {set i 0} {$i < 14} {incr i} {
    scan [read_probe_data -instance_index $idx(SCCS) -value_in_hex] %x v
    puts [format "poll %2d: SCCS=%04X delivered=%d ferr=%d nonempty=%d" \
        $i [expr {$v & 0xFFFF}] [expr {($v >> 12) & 0xF}] [expr {($v >> 8) & 0xF}] [expr {$v & 1}]]
}
end_insystem_source_probe
