# Read the SCCS probe: live SCC channel-A TX/RX engine state.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(SCCS)]} { puts "NO SCCS probe"; exit 0 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
scan [read_probe_data -instance_index $idx(SCCS) -value_in_hex] %x v
puts [format "SCCS raw=%04X" $v]
puts [format "  rx_delivered  = %d (wraps at 16)" [expr {($v >> 12) & 0xF}]]
puts [format "  frame_errors  = %d (wraps at 16)" [expr {($v >> 8) & 0xF}]]
puts [format "  post_loopback = %d" [expr {($v >> 7) & 1}]]
puts [format "  sync_mode     = %d" [expr {($v >> 6) & 1}]]
puts [format "  tx_empty_latch= %d" [expr {($v >> 5) & 1}]]
puts [format "  tx_buffer_full= %d" [expr {($v >> 4) & 1}]]
puts [format "  tx_busy       = %d   <- stuck 1 = engine wedged" [expr {($v >> 3) & 1}]]
puts [format "  tx_line       = %d   (idle = 1)" [expr {($v >> 2) & 1}]]
puts [format "  local_loopback= %d" [expr {($v >> 1) & 1}]]
puts [format "  rx_nonempty   = %d" [expr {$v & 1}]]
end_insystem_source_probe
