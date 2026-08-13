# SDCP (buildAE): dump the captured last pseudo-DMA burst — 512 beats of
# 16-bit bus data. Byte-mode bursts carry each byte duplicated ({b,b});
# word-mode carries words. Run against a FROZEN machine (FRZE) so the wander
# cannot overwrite the capture.
#   quartus_stp_tcl -t scripts/sdcp.tcl > burst.txt
# Output: one line per 8 beats, hex. Offline: collapse byte-mode duplicates
# and diff against the master image sector.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(SDCP)]} { puts "MISSING SDCP (pre-buildAE fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set line {}
for {set k 0} {$k < 512} {incr k} {
    write_source_data -instance_index $idx(SDCP) -value [format "0x%03X" $k] -value_in_hex
    scan [read_probe_data -instance_index $idx(SDCP) -value_in_hex] %x v
    lappend line [format %04X [expr {$v & 0xFFFF}]]
    if {[llength $line] == 8} {
        puts [format "%03X: %s" [expr {$k - 7}] [join $line " "]]
        set line {}
    }
}
end_insystem_source_probe
