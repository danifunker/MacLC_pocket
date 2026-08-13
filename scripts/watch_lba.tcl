# Watch the SCSI read stream live: deliveries + last LBA every ~2 s for ~40 s.
#   quartus_stp_tcl -t scripts/watch_lba.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
start_insystem_source_probe -device_name $dev -hardware_name $hw
for {set i 0} {$i < 20} {incr i} {
    scan [read_probe_data -instance_index $idx(BDLB) -value_in_hex] %x l
    set l [expr {$l & 0xFFFFFFFF}]
    scan [read_probe_data -instance_index $idx(SDCT) -value_in_hex] %x sc
    set sc [expr {$sc & 0xFFFFFFFF}]
    puts [format "t=%2ds deliveries=%3d lastLBA=%6d | bursts=%d beats(prev/cur)=%d/%d" \
        [expr {$i * 2}] [expr {($l >> 24) & 0xFF}] [expr {$l & 0xFFFFFF}] \
        [expr {($sc >> 24) & 0xFF}] [expr {($sc >> 12) & 0xFFF}] [expr {$sc & 0xFFF}]]
    after 2000
}
end_insystem_source_probe
