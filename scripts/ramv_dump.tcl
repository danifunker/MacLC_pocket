# ROMV v4: dump an arbitrary SDRAM word range over JTAG (machine held in
# reset during each 1-word scan). ~20 words/s — meant for sectors, not MBs.
#   quartus_stp_tcl -t scripts/ramv_dump.tcl <hex word base> [nwords]
# Word base is the ABSOLUTE 23-bit SDRAM word address (RAM starts at 0;
# the ROM region starts at 500000). Output: one line per 8 words, hex.
set base 0
set nw   256
if {[llength $quartus(args)] > 0} { scan [lindex $quartus(args) 0] %x base }
if {[llength $quartus(args)] > 1} { set nw [lindex $quartus(args) 1] }

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {ROMV RVSU} { if {![info exists idx($need)]} { puts "MISSING $need (old fabric?)"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set line {}
for {set k 0} {$k < $nw} {incr k} {
    set a [expr {$base + $k}]
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {$a << 5}]] -value_in_hex
    write_source_data -instance_index $idx(ROMV) -value [format "0x%08X" [expr {(1 << 31) | ($a << 5)}]] -value_in_hex
    for {set i 0} {$i < 20} {incr i} {
        scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
        if {($st & 3) == 2} { break }
    }
    scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
    lappend line [format %04X [expr {$s & 0xFFFF}]]
    if {[llength $line] == 8} {
        puts [format "%06X: %s" [expr {$base + $k - 7}] [join $line " "]]
        set line {}
    }
}
if {[llength $line] > 0} {
    puts [format "%06X: %s" [expr {$base + $nw - [llength $line]}] [join $line " "]]
}
end_insystem_source_probe
