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
    return [expr {$v & 0xFFFFF}] }
proc ring_at {i} { global idx
    write_source_data -instance_index $idx(SCCR) -value [format "0x%02X" [expr {$i & 0xFF}]] -value_in_hex
    # one dummy read lets the registered ring output settle
    read_probe_data -instance_index $idx(SCCR) -value_in_hex
    return [expr {[rd_sccr] & 0xFFF}] }

set before [expr {[rd_sccr] >> 12}]
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
        set now [expr {[rd_sccr] >> 12}]
        if {$now == $last} { incr stable } else { set stable 0; set last $now }
    }
}
set after [expr {[rd_sccr] >> 12}]
set n [expr {($after - $before) & 0xFF}]
if {$cmd eq ""} { set n 96; }
if {$n == 0} { puts "no new bytes"; set n 24 }
if {$n > 250} { set n 250 }
set start [expr {($after - $n) & 0xFF}]
puts "reading $n entries ending at count $after:  (r/w port byte)"
set line ""
set ports {ctB ctA dtB dtA}
for {set k 0} {$k < $n} {incr k} {
    set e [ring_at [expr {($start + $k) & 0xFF}]]
    set rw [expr {($e >> 11) & 1}]
    set pt [lindex $ports [expr {($e >> 9) & 3}]]
    set b  [expr {$e & 0xFF}]
    set a "."
    if {$b >= 32 && $b < 127} { set a [format %c $b] }
    append line [format "%s-%s-%02X(%s) " [expr {$rw ? "R" : "W"}] $pt $b $a]
    if {[expr {($k + 1) % 6}] == 0} { puts "  $line"; set line "" }
}
if {$line ne ""} { puts "  $line" }
end_insystem_source_probe
