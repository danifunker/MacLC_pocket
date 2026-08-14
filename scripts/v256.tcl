# V256 (buildAW): VRAM-SIMM-size lever.
#   quartus_stp_tcl -t scripts/v256.tcl          read current setting
#   quartus_stp_tcl -t scripts/v256.tcl 512      force the OLD 512K SIMM (A/B)
#   quartus_stp_tcl -t scripts/v256.tcl 256      back to 256K (the default)
# The machine samples the VRAM wrap test at driver init, so pair any change
# with a jboot. source resets to 0 (= 256K) on every fabric push.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(V256)]} { puts "MISSING V256 (pre-buildAW fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set cmd [lindex $quartus(args) 0]
if {$cmd eq "512"} {
    write_source_data -instance_index $idx(V256) -value 1
    puts "V256: forcing 512K VRAM SIMM (legacy). jboot to apply."
} elseif {$cmd eq "256"} {
    write_source_data -instance_index $idx(V256) -value 0
    puts "V256: 256K VRAM SIMM (default). jboot to apply."
}
set v [read_probe_data -instance_index $idx(V256)]
puts "V256 readback: [expr {$v ? "512K (legacy forced)" : "256K (shipping)"}]"
end_insystem_source_probe
