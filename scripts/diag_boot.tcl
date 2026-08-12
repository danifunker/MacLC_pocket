# Boot INTO the STM diagnostic monitor: hold DIAG (PA0 grounded) and strobe
# JBOO in one session, wait for the boot to settle, then exit. PA0 only
# matters at boot time — the machine stays in the monitor after entry, so
# subsequent stm_console sessions can converse freely.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {DIAG JBOO SCCS} { if {![info exists idx($need)]} { puts "MISSING $need"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw
write_source_data -instance_index $idx(DIAG) -value 1
write_source_data -instance_index $idx(JBOO) -value 1
puts "DIAG held + boot strobed; waiting for the monitor..."
for {set i 0} {$i < 500} {incr i} { read_probe_data -instance_index $idx(SCCS) -value_in_hex }
scan [read_probe_data -instance_index $idx(SCCS) -value_in_hex] %x v
puts [format "settled: SCCS=%04X" $v]
write_source_data -instance_index $idx(DIAG) -value 0
end_insystem_source_probe
