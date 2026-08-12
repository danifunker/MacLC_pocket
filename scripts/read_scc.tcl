# Poll the SCC TX-capture probe (SCCT) rapidly and dump {count, last3 bytes}.
# The STM diagnostic banner repeats forever, so sparse samples + the write
# counter reconstruct the stream. Decode: bytes are CPU writes into $F040xx —
# Z8530 ctl-pointer writes (small values like 08) interleave with data chars.
#   quartus_stp_tcl -t scripts/read_scc.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(SCCT)]} { puts "NO SCCT probe in this build"; exit 0 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
puts " poll   cnt   bytes (hex)   ascii"
set prev -1
for {set i 0} {$i < 60} {incr i} {
    scan [read_probe_data -instance_index $idx(SCCT) -value_in_hex] %x v
    set v    [expr {$v & 0xFFFFFFFF}]
    set cnt  [expr {($v >> 24) & 0xFF}]
    set b2   [expr {($v >> 16) & 0xFF}]
    set b1   [expr {($v >> 8) & 0xFF}]
    set b0   [expr {$v & 0xFF}]
    set asc ""
    foreach b [list $b2 $b1 $b0] {
        if {$b >= 32 && $b < 127} { append asc [format %c $b] } else { append asc "." }
    }
    if {$cnt != $prev} {
        puts [format "  %3d   %3d   %02X %02X %02X      %s" $i $cnt $b2 $b1 $b0 $asc]
        set prev $cnt
    }
}
end_insystem_source_probe
