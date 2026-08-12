# Continuously inject '*' for ~90s so a char is always arriving when the
# ROM's post-failure serial window opens. Run while the user reloads the ROM.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(STMC)]} { puts "NO STMC"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
set tog 0
for {set i 0} {$i < 400} {incr i} {
    set tog [expr {1 - $tog}]
    write_source_data -instance_index $idx(STMC) -value [format "0x%03X" [expr {($tog << 8) | 0x2A}]] -value_in_hex
    read_probe_data -instance_index $idx(STMC) -value_in_hex
}
scan [read_probe_data -instance_index $idx(STMC) -value_in_hex] %x sent
puts [format "spam done: injector sent-count %d" [expr {$sent & 0xFF}]]
end_insystem_source_probe
