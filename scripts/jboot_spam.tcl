# Fire the boot strobe, then immediately stream '*' so a character is waiting
# whenever the boot's serial-poll window opens (early diag or STM spin).
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {JBOO STMC SCCS} { if {![info exists idx($need)]} { puts "NO $need"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw
write_source_data -instance_index $idx(JBOO) -value 1
puts "boot strobed; streaming '*'..."
set tog 0
for {set i 0} {$i < 120} {incr i} {
    set tog [expr {1 - $tog}]
    write_source_data -instance_index $idx(STMC) -value [format "0x%03X" [expr {($tog << 8) | 0x2A}]] -value_in_hex
    read_probe_data -instance_index $idx(STMC) -value_in_hex
}
scan [read_probe_data -instance_index $idx(SCCS) -value_in_hex] %x v
puts [format "after stream: delivered=%d ferr=%d nonempty=%d" \
    [expr {($v >> 12) & 0xF}] [expr {($v >> 8) & 0xF}] [expr {$v & 1}]]
end_insystem_source_probe
