# Decode the BDST probe: the blockdev serving story in one word.
#   quartus_stp_tcl -t scripts/read_bdst.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(BDST)]} { puts "MISSING BDST (old fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
scan [read_probe_data -instance_index $idx(BDST) -value_in_hex] %x v
set v [expr {$v & 0xFFFFFFFF}]
puts [format "BDST raw = %08X" $v]
puts [format "  saw_tmo (OS failed to answer)   : %d" [expr {($v >> 31) & 1}]]
puts [format "  read raised to host             : %d" [expr {($v >> 30) & 1}]]
puts [format "  host acked                      : %d" [expr {($v >> 29) & 1}]]
puts [format "  host completed (done)           : %d" [expr {($v >> 28) & 1}]]
puts [format "  sector delivered to machine     : %d" [expr {($v >> 27) & 1}]]
puts [format "  mount seen                      : %d" [expr {($v >> 26) & 1}]]
puts [format "  mount count (mod 8)             : %d" [expr {($v >> 23) & 7}]]
set blks [expr {$v & 0x7FFFFF}]
puts [format "  img_size blocks (last mount)    : %d (%.1f MB)" $blks [expr {$blks / 2048.0}]]
if {[info exists idx(BDW0)]} {
    scan [read_probe_data -instance_index $idx(BDW0) -value_in_hex] %x w
    set w [expr {$w & 0xFFFFFFFF}]
    puts [format "  last sector words 0,1           : %04X %04X (block 0 expects 4552 0200)" \
        [expr {($w >> 16) & 0xFFFF}] [expr {$w & 0xFFFF}]]
}
if {[info exists idx(BDLB)]} {
    scan [read_probe_data -instance_index $idx(BDLB) -value_in_hex] %x l
    set l [expr {$l & 0xFFFFFFFF}]
    puts [format "  deliveries=%d  last LBA=%d" [expr {($l >> 24) & 0xFF}] [expr {$l & 0xFFFFFF}]]
}
end_insystem_source_probe
