# ROM retention verify: trigger the ROMV scan (reads the 512 KB ROM region
# back OUT of SDRAM, machine held in reset ~32 ms) and compare against the
# known-good sums. THE decay oracle.
#   quartus_stp_tcl -t scripts/romv.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {ROMV RVSU RVAX} { if {![info exists idx($need)]} { puts "MISSING $need"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw
write_source_data -instance_index $idx(ROMV) -value 1
# scan is ~32 ms; a few JTAG polls dwarf it
for {set i 0} {$i < 20} {incr i} {
    scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
    if {($st & 0x3) == 2} { break }
}
scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
scan [read_probe_data -instance_index $idx(RVAX) -value_in_hex] %x a
set s [expr {$s & 0xFFFFFFFF}]
set a [expr {$a & 0xFFFFFFFF}]
puts [format "status=%d  sum=%08X (expect 350F8EEE)  axsum=%08X (expect F486F3D8)" [expr {$st & 3}] $s $a]
if {$s == 0x350F8EEE && $a == 0xF486F3D8} {
    puts "-> ROM RETENTION GOOD: SDRAM holds the ROM byte-perfect."
} else {
    puts "-> ROM CONTENT IN SDRAM DIFFERS — decay or scan-pipeline offset."
}
write_source_data -instance_index $idx(ROMV) -value 0
end_insystem_source_probe
