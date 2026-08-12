# Fire the JTAG boot strobe: forces rom_loaded (ROM persists in SDRAM) and
# pulses a full machine reset. Boots the Mac with no OSD interaction.
#   quartus_stp_tcl -t scripts/jboot.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(JBOO)]} { puts "NO JBOO instance"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
scan [read_probe_data -instance_index $idx(JBOO) -value_in_hex] %x cur
# read current source value is not possible; just toggle twice-safe: write 1 then 0 would double-fire.
# Single toggle: write the opposite of a remembered state is unavailable — use one write of 1,
# which differs from the power-up 0 the first time; subsequent runs alternate via the arg.
set val [lindex $quartus(args) 0]
if {$val eq ""} { set val 1 }
write_source_data -instance_index $idx(JBOO) -value $val
puts "JBOOT strobe written (source=$val) — machine reset+boot armed"
end_insystem_source_probe
