# PCRB (buildAH): dump the boot code's check-and-decide instruction stream.
# FRZE (trig mode) fires at the round's final delivery WITHOUT freezing the
# machine; the ring keeps capturing K*16 more writes, then freezes — a
# steerable 64-PC window planted K*16 ring-writes past the last sector.
#   quartus_stp_tcl -t scripts/pcrb.tcl arm <K>   re-open ring, set countdown
#                                                 (K 0..511, window lands
#                                                 K*16 writes post-trigger)
#   quartus_stp_tcl -t scripts/pcrb.tcl           dump (oldest -> newest)
# Full capture flow (fresh round):
#   frze.tcl off ; frze.tcl trig +59 ; pcrb.tcl arm <K> ; jboot ; wait ;
#   pcrb.tcl > dump.txt   — sweep K across runs to walk the window forward.
# ROM PCs are 00A0xxxx: disasm line = 40800000 + (pc & 7FFFF)
# (docs/MacLC_ROM_disasm.txt). RAM PCs = boot blocks / System / driver code.
set cmd "dump"
set arg 128
if {[llength $quartus(args)] > 0} { set cmd [lindex $quartus(args) 0] }
if {[llength $quartus(args)] > 1} { set arg [lindex $quartus(args) 1] }

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {PCRB PCRS} { if {![info exists idx($need)]} { puts "MISSING $need (pre-buildAH fabric?)"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

scan [read_probe_data -instance_index $idx(PCRS) -value_in_hex] %x st
set frozen [expr {($st >> 6) & 1}]
set wptr   [expr {$st & 0x3F}]
puts "frozen=$frozen wptr=$wptr"

if {$cmd eq "arm"} {
    set k [expr {$arg & 0x1FF}]
    write_source_data -instance_index $idx(PCRB) -value 0x0000 -value_in_hex
    write_source_data -instance_index $idx(PCRB) -value [format "0x%04X" [expr {0x8000 | ($k << 6)}]] -value_in_hex
    write_source_data -instance_index $idx(PCRB) -value [format "0x%04X" [expr {$k << 6}]] -value_in_hex
    puts "PCRB re-armed, K=$k (window lands [expr {$k * 16}] ring-writes past the FRZE trigger)"
} else {
    for {set k 0} {$k < 64} {incr k} {
        set i [expr {($wptr + $k) & 0x3F}]
        write_source_data -instance_index $idx(PCRB) -value [format "0x%04X" $i] -value_in_hex
        scan [read_probe_data -instance_index $idx(PCRB) -value_in_hex] %x v
        puts [format "%2d: %08X" $k [expr {$v & 0xFFFFFFFF}]]
    }
    puts "(63 = newest)"
}
end_insystem_source_probe
