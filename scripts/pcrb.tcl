# PCRB (buildAF): dump the dying instruction stream — the 64 fetch PCs
# captured before the machine's crash reset.
#   quartus_stp_tcl -t scripts/pcrb.tcl          dump (oldest -> newest)
#   quartus_stp_tcl -t scripts/pcrb.tcl arm      re-open the ring (do this
#                                                AFTER jboot, once the round
#                                                is running — jboot's own
#                                                reset would freeze it)
# ROM PCs are 00A0xxxx (docs/MacLC_ROM_disasm.txt); RAM PCs = System/driver.
set cmd "dump"
if {[llength $quartus(args)] > 0} { set cmd [lindex $quartus(args) 0] }

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {PCRB PCRS} { if {![info exists idx($need)]} { puts "MISSING $need (pre-buildAF fabric?)"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

scan [read_probe_data -instance_index $idx(PCRS) -value_in_hex] %x st
set frozen [expr {($st >> 6) & 1}]
set wptr   [expr {$st & 0x3F}]
puts "frozen=$frozen wptr=$wptr"

if {$cmd eq "arm"} {
    write_source_data -instance_index $idx(PCRB) -value 0x00 -value_in_hex
    write_source_data -instance_index $idx(PCRB) -value 0x80 -value_in_hex
    write_source_data -instance_index $idx(PCRB) -value 0x00 -value_in_hex
    puts "PCRB re-armed (will freeze at the next machine reset)"
} else {
    # oldest entry is at wptr (the ring overwrites forward)
    for {set k 0} {$k < 64} {incr k} {
        set i [expr {($wptr + $k) & 0x3F}]
        write_source_data -instance_index $idx(PCRB) -value [format "0x%02X" $i] -value_in_hex
        scan [read_probe_data -instance_index $idx(PCRB) -value_in_hex] %x v
        puts [format "%2d: %08X" $k [expr {$v & 0xFFFFFFFF}]]
    }
    puts "(63 = newest = last fetch before the reset)"
}
end_insystem_source_probe
