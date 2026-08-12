# Send a command string to the ROM's STM diagnostic monitor over the JTAG
# serial injector (STMC), then dump the SCC TX capture (echo + response).
#   quartus_stp_tcl -t scripts/stm_send.tcl "*V"
# STM commands (see MacLC_MiSTer docs/diagnostic_mode_reference.md):
#   *V version   *R status/error code   *A ascii-arg mode   *S service mode
#   *T000400010000 = run critical test 04 (ROM checksum) once, etc.
set cmd [lindex $quartus(args) 0]
if {$cmd eq ""} { puts "usage: stm_send.tcl <string>"; exit 1 }
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(STMC)]} { puts "NO STMC instance in this build"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw

# current toggle state = bit 8 of the source's last written value; start at 0
set tog 0
puts "sending: $cmd"
foreach ch [split $cmd ""] {
    scan $ch %c code
    set tog [expr {1 - $tog}]
    write_source_data -instance_index $idx(STMC) -value [format "0x%03X" [expr {($tog << 8) | $code}]] -value_in_hex
    # pacing: two probe reads over JTAG comfortably exceed one 9600-baud frame
    read_probe_data -instance_index $idx(STMC) -value_in_hex
    read_probe_data -instance_index $idx(STMC) -value_in_hex
}
scan [read_probe_data -instance_index $idx(STMC) -value_in_hex] %x sent
puts [format "injector sent-count now %d" [expr {$sent & 0xFF}]]

# read the SCC TX capture for the echo/answer
if {[info exists idx(SCCT)]} {
    puts " poll   cnt   bytes (hex)   ascii"
    set prev -1
    for {set i 0} {$i < 120} {incr i} {
        scan [read_probe_data -instance_index $idx(SCCT) -value_in_hex] %x v
        set v   [expr {$v & 0xFFFFFFFF}]
        set cnt [expr {($v >> 24) & 0xFF}]
        set b2  [expr {($v >> 16) & 0xFF}]
        set b1  [expr {($v >> 8) & 0xFF}]
        set b0  [expr {$v & 0xFF}]
        set asc ""
        foreach b [list $b2 $b1 $b0] {
            if {$b >= 32 && $b < 127} { append asc [format %c $b] } else { append asc "." }
        }
        if {$cnt != $prev} {
            puts [format "  %3d   %3d   %02X %02X %02X      %s" $i $cnt $b2 $b1 $b0 $asc]
            set prev $cnt
        }
    }
}
end_insystem_source_probe
