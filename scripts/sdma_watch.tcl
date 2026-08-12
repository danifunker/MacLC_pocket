# Watch sdma_stall_ctr closely: does it ever REACH 8,125,000 and fire BERR,
# or does something reset it first? Samples as fast as JTAG allows.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
start_insystem_source_probe -device_name $dev -hardware_name $hw
proc rd {n} { global idx; if {![info exists idx($n)]} { return -1 }
  scan [read_probe_data -instance_index $idx($n) -value_in_hex] %x v; return $v }

puts ""
puts "sample  stall_ctr   berr dreq selDMA  AS  rst   (target 8125000)"
set prev -1
set drops 0
set maxseen 0
for {set i 0} {$i < 60} {incr i} {
    set a [rd SDMA]
    set c [expr {$a & 0x7FFFFF}]
    if {$c > $maxseen} { set maxseen $c }
    set mark ""
    if {$prev >= 0 && $c < $prev} { set mark "   <== RESET (dropped from $prev)"; incr drops }
    puts [format "  %2d   %9d     %d    %d     %d     %d   %d%s" $i $c \
        [expr {($a>>31)&1}] [expr {($a>>30)&1}] [expr {($a>>29)&1}] \
        [expr {($a>>26)&1}] [expr {($a>>27)&1}] $mark]
    set prev $c
}
puts ""
puts [format "  highest value seen : %d   (timeout target 8125000)" $maxseen]
puts [format "  resets observed    : %d" $drops]
if {$drops > 0} {
    puts "  -> THE COUNTER IS BEING RESET before it can reach the timeout."
    puts "     Reset terms are (!_cpuReset) and (_cpuAS). Whichever is glitching"
    puts "     is why sdma_berr never fires and the bus cycle never terminates."
} elseif {$maxseen < 8125000} {
    puts "  -> counter never reached the target while sampling; keep watching."
}
end_insystem_source_probe
