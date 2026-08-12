# Identify WHICH POST subtest the boot ROM is executing, by sampling cpuAddr
# many times and bucketing the ROM-space ($A4xxxx) hits against the landmark
# table in ../MacLC_MiSTer docs/post_diagnostics_and_irq_levels.md.
#
#   quartus_stp_tcl -t scripts/post_stage.tcl
#
# The probe samples at random instants, so a tight cluster of ROM addresses is
# the loop we are in. Data-space addresses are bucketed separately.

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
if {$dev eq ""} { puts "NO DEVICE - Pocket powered on with the core running?"; exit 1 }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
start_insystem_source_probe -device_name $dev -hardware_name $hw
proc rd {n} { global idx; if {![info exists idx($n)]} { return -1 }
  scan [read_probe_data -instance_index $idx($n) -value_in_hex] %x v; return $v }

# landmark -> description (from the MiSTer POST doc)
set marks {
    0xA4644C "PA0 diagnostic-mode check"
    0xA46582 "RAM bank-descriptor scan loop"
    0xA465B0 "RAM bank-descriptor scan loop"
    0xA46C5C "per-bank address/data walking subtest"
    0xA46968 "the big march (clears RAM via movem)"
    0xA4694C "big-march jmp (A6) dispatch"
    0xA47158 "install level-1 ISR at VBR+\$64"
    0xA47170 "VIA1 Timer-1 interrupt-timing self-test"
    0xA472CC "level-1 ISR (counts T1/T2)"
    0xA4A87C "relocation trampoline / config write (clears overlay)"
    0xA462AA "per-subtest ERROR entry (ORs code into D7)"
    0xA4638C "bset #24,D7 -> jump to failure reporter"
    0xA498F0 "POST FAILURE REPORTER (STM)"
    0xA49F00 "POST FAILURE REPORTER spin (STM)"
}

set N 400
array set rom {}
array set other {}
set romhits 0
array set pgm {}
set pgmhits 0
for {set i 0} {$i < $N} {incr i} {
    set a [expr {[rd CPUA] & 0xFFFFFF}]
    set fc [expr {([rd IRQS] >> 21) & 0x7}]
    if {$fc == 6 || $fc == 2} {
        incr pgmhits
        set pb [expr {$a & 0xFFFF00}]
        if {![info exists pgm($pb)]} { set pgm($pb) 0 }
        incr pgm($pb)
    }
    if {$a >= 0xA40000 && $a < 0xA50000} {
        incr romhits
        set b [expr {$a & 0xFFFF00}]
        if {![info exists rom($b)]} { set rom($b) 0 }
        incr rom($b)
    } else {
        set b [expr {$a & 0xFF0000}]
        if {![info exists other($b)]} { set other($b) 0 }
        incr other($b)
    }
}
puts ""
set _hi [expr {([rd DLST] >> 24) & 0xFF}]
puts [format "cpuAddr 31:24 = 0x%02X   (slot_space window is 0xF1..0xFE)" $_hi]
if {$_hi >= 0xF1 && $_hi <= 0xFE} {
    puts "  -> INSIDE slot_space: that path should already bus-error/ACK. Bug is there."
} else {
    puts "  -> OUTSIDE slot_space, so this is the 24-bit slot form and slot_space never sees it."
}
puts ""
puts "sampled cpuAddr $N times -- $romhits landed in ROM POST space (\$A4xxxx)"
puts ""
puts "=== PROGRAM-SPACE fetches (FC=110/010) -- the actual PC ==="
puts [format "  %d of %d samples were instruction fetches" $pgmhits $N]
foreach b [lsort -integer [array names pgm]] {
    set note ""
    foreach {m d} $marks {
        if {abs([expr {$m}] - $b) < 0x300} { set note "   <-- $d" }
    }
    puts [format "  \$%06X   x%-4d%s" $b $pgm($b) $note]
}
puts ""
puts "=== ROM code buckets (256-byte granularity) ==="
foreach b [lsort -integer [array names rom]] {
    set note ""
    foreach {m d} $marks {
        set mv [expr {$m}]
        if {abs($mv - $b) < 0x300} { set note "   <-- $d" }
    }
    puts [format "  \$%06X   x%-4d%s" $b $rom($b) $note]
}
puts ""
puts "=== other address space (64 KB granularity) ==="
foreach b [lsort -integer [array names other]] {
    puts [format "  \$%06X   x%d" $b $other($b)]
}
puts ""
puts "Overlay still on + no \$A4A87C hits = POST never reached the relocation."
puts "Any \$A498xx/\$A49Fxx hits = a subtest FAILED and we are in the reporter."
end_insystem_source_probe
