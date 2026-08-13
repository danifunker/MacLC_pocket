# PCRB (buildAO): steerable 64-PC window with TWO trigger modes.
#   quartus_stp_tcl -t scripts/pcrb.tcl arm <K> [matchPC]
#     K       : countdown after the trigger, in units of 16 ring-writes
#     matchPC : optional 24-bit hex PC — trigger fires on a FETCH of this
#               address (e.g. A14882 = the ioResult-wait exit; 0/omitted =
#               delivery-count trigger via `frze.tcl trig` only)
#   quartus_stp_tcl -t scripts/pcrb.tcl           dump (oldest -> newest)
# At the freeze: EGS1/EGS3 (Egret handshake + HC05 PC), PSN1/PSN2 (SCSI bus)
# latch automatically; EGS2 counts [trigger..freeze]. read_bdst.tcl decodes.
# ROM PC -> disasm line = 40800000 + (pc & 7FFFF).
set cmd "dump"
set arg 128
set match 0
if {[llength $quartus(args)] > 0} { set cmd [lindex $quartus(args) 0] }
if {[llength $quartus(args)] > 1} { set arg [lindex $quartus(args) 1] }
if {[llength $quartus(args)] > 2} { scan [lindex $quartus(args) 2] %x match }

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {PCRB PCRS} { if {![info exists idx($need)]} { puts "MISSING $need (pre-buildAO fabric?)"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

scan [read_probe_data -instance_index $idx(PCRS) -value_in_hex] %x st
set frozen [expr {($st >> 6) & 1}]
set wptr   [expr {$st & 0x3F}]
puts "frozen=$frozen wptr=$wptr"

if {$cmd eq "arm"} {
    set k [expr {$arg & 0x1FF}]
    set base [expr {(wide($k) << 38) | wide($match)}]
    write_source_data -instance_index $idx(PCRB) -value [format "0x%012llX" $base] -value_in_hex
    write_source_data -instance_index $idx(PCRB) -value [format "0x%012llX" [expr {$base | (wide(1) << 47)}]] -value_in_hex
    write_source_data -instance_index $idx(PCRB) -value [format "0x%012llX" $base] -value_in_hex
    if {$match != 0} {
        puts [format "PCRB re-armed, K=%d, PC-match trigger at %06X" $k $match]
    } else {
        puts [format "PCRB re-armed, K=%d (delivery trigger via frze.tcl trig)" $k]
    }
} else {
    for {set k 0} {$k < 64} {incr k} {
        set i [expr {($wptr + $k) & 0x3F}]
        write_source_data -instance_index $idx(PCRB) -value [format "0x%012llX" [expr {wide($i) << 32}]] -value_in_hex
        scan [read_probe_data -instance_index $idx(PCRB) -value_in_hex] %x v
        puts [format "%2d: %08X" $k [expr {$v & 0xFFFFFFFF}]]
    }
    puts "(63 = newest)"
}
end_insystem_source_probe
