# STM console with full-transcript readback (needs the SCCR ring, 2026-08-12).
#   quartus_stp_tcl -t scripts/stm_console.tcl "*R"     -> send + full response
#   quartus_stp_tcl -t scripts/stm_console.tcl          -> dump last 96 bytes
set cmd [lindex $quartus(args) 0]
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {SCCR STMC} { if {![info exists idx($need)]} { puts "NO $need instance"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

proc rd_sccr {} { global idx
    scan [read_probe_data -instance_index $idx(SCCR) -value_in_hex] %x v
    return [expr {$v & 0xFFFF}] }
proc ring_at {i} { global idx
    write_source_data -instance_index $idx(SCCR) -value [format "0x%02X" [expr {$i & 0xFF}]] -value_in_hex
    # one dummy read lets the registered ring output settle
    read_probe_data -instance_index $idx(SCCR) -value_in_hex
    return [expr {[rd_sccr] & 0xFF}] }

set before [expr {[rd_sccr] >> 8}]
puts "write-count before: $before"

if {$cmd ne ""} {
    set tog 0
    puts "sending: $cmd"
    foreach ch [split $cmd ""] {
        scan $ch %c code
        set tog [expr {1 - $tog}]
        write_source_data -instance_index $idx(STMC) -value [format "0x%03X" [expr {($tog << 8) | $code}]] -value_in_hex
        read_probe_data -instance_index $idx(STMC) -value_in_hex
        read_probe_data -instance_index $idx(STMC) -value_in_hex
    }
    # wait for the response burst to finish (count stable across polls)
    set stable 0
    set last -1
    for {set i 0} {$i < 120 && $stable < 6} {incr i} {
        set now [expr {[rd_sccr] >> 8}]
        if {$now == $last} { incr stable } else { set stable 0; set last $now }
    }
}
set after [expr {[rd_sccr] >> 8}]
set n [expr {($after - $before) & 0xFF}]
if {$cmd eq ""} { set n 96; }
if {$n == 0} { puts "no new bytes"; set n 24 }
if {$n > 250} { set n 250 }
set start [expr {($after - $n) & 0xFF}]
puts "reading $n bytes ending at count $after:"
set hexline ""
set ascline ""
for {set k 0} {$k < $n} {incr k} {
    set b [ring_at [expr {($start + $k) & 0xFF}]]
    append hexline [format "%02X " $b]
    if {$b >= 32 && $b < 127} { append ascline [format %c $b] } else { append ascline "." }
    if {[expr {($k + 1) % 24}] == 0} { puts "  $hexline  $ascline"; set hexline ""; set ascline "" }
}
if {$hexline ne ""} { puts "  $hexline  $ascline" }
end_insystem_source_probe
