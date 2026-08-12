# One-session STM interrogation: hold DIAG (PA0 grounded), boot via JBOO,
# wait for the ROM to enter the monitor, then converse and dump transcripts.
# Sources reset to 0 at session start, so EVERYTHING must happen in here.
#   quartus_stp_tcl -t scripts/stm_full_session.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {DIAG JBOO STMC SCCR SCCS} { if {![info exists idx($need)]} { puts "MISSING $need"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

proc sccr {} { global idx
    scan [read_probe_data -instance_index $idx(SCCR) -value_in_hex] %x v
    return [expr {$v & 0xFFFFF}] }
proc ring_at {i} { global idx
    write_source_data -instance_index $idx(SCCR) -value [format "0x%02X" [expr {$i & 0xFF}]] -value_in_hex
    read_probe_data -instance_index $idx(SCCR) -value_in_hex
    return [expr {[sccr] & 0xFFF}] }
proc dump_new {from to} {
    set ports {ctB ctA dtB dtA}
    set n [expr {($to - $from) & 0xFF}]
    if {$n == 0} { puts "  (no new entries)"; return }
    set line ""
    for {set k 0} {$k < $n} {incr k} {
        set e [ring_at [expr {($from + $k) & 0xFF}]]
        set rw [expr {($e >> 11) & 1}]
        set pt [lindex $ports [expr {($e >> 9) & 3}]]
        set b  [expr {$e & 0xFF}]
        set a "."
        if {$b >= 32 && $b < 127} { set a [format %c $b] }
        append line [format "%s-%s-%02X(%s) " [expr {$rw ? "R" : "W"}] $pt $b $a]
        if {[expr {($k+1) % 6}] == 0} { puts "  $line"; set line "" }
    }
    if {$line ne ""} { puts "  $line" }
}
proc send_str {s} { global idx tog
    foreach ch [split $s ""] {
        scan $ch %c code
        set tog [expr {1 - $tog}]
        write_source_data -instance_index $idx(STMC) -value [format "0x%03X" [expr {($tog << 8) | $code}]] -value_in_hex
        read_probe_data -instance_index $idx(STMC) -value_in_hex
        read_probe_data -instance_index $idx(STMC) -value_in_hex
    }
}
proc wait_polls {n} { global idx
    for {set i 0} {$i < $n} {incr i} { read_probe_data -instance_index $idx(SCCS) -value_in_hex }
}

set tog 0
puts "== DIAG=1 (PA0 grounded), strobing boot =="
write_source_data -instance_index $idx(DIAG) -value 1
write_source_data -instance_index $idx(JBOO) -value 1
wait_polls 300
set c0 [expr {[sccr] >> 12}]
puts "== after boot: ring count = $c0 (boot-time SCC activity below) =="
dump_new 0 $c0

puts "== sending *V =="
send_str "*V"
wait_polls 150
set c1 [expr {[sccr] >> 12}]
dump_new $c0 $c1

puts "== sending *R =="
send_str "*R"
wait_polls 150
set c2 [expr {[sccr] >> 12}]
dump_new $c1 $c2

puts "== DIAG released =="
write_source_data -instance_index $idx(DIAG) -value 0
end_insystem_source_probe
