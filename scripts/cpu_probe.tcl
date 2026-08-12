# Direct decode of the CPU probe: where is the 68020 and what is the bus doing?
#   quartus_stp_tcl -t scripts/cpu_probe.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
puts "instances found:"
foreach inst $info { puts "   idx=[lindex $inst 0]  name='[lindex $inst 3]'"; set idx([lindex $inst 3]) [lindex $inst 0] }
start_insystem_source_probe -device_name $dev -hardware_name $hw
proc rd {n} { global idx; if {![info exists idx($n)]} { return -1 }
  scan [read_probe_data -instance_index $idx($n) -value_in_hex] %x v; return $v }

puts ""
puts "=========== CPU probe, 12 samples ==========="
puts "  bit26 _cpuReset : 1 = CPU RUNNING, 0 = held in reset"
puts "        ^ if this is 0, the sdma stall counter is pinned at 0 and"
puts "          sdma_berr is forced low -- which would explain a dead timeout."
puts ""
puts " sample   addr      AS DTACK RW BERR _cpuReset tg68_rst_n ovl VPA   cycles"
for {set i 0} {$i < 12} {incr i} {
    set a [rd CPUA]
    set c [rd CPUC]
    puts [format "  %2d    0x%06X   %d   %d    %d   %d       %d          %d      %d   %d   %d" \
        $i [expr {$a & 0xFFFFFF}] [expr {($a>>28)&1}] [expr {($a>>29)&1}] \
        [expr {($a>>30)&1}] [expr {($a>>25)&1}] [expr {($a>>26)&1}] \
        [expr {($a>>27)&1}] [expr {($a>>31)&1}] [expr {($a>>24)&1}] $c]
}
puts ""
puts "AS/DTACK are ACTIVE LOW (0 = asserted). rstn 0 = CPU held in reset."

# ---- video liveness -------------------------------------------------------
# NB: must run BEFORE end_insystem_source_probe, or every read returns garbage.
if {[info exists idx(VIDS)]} {
    set v0 [rd VIDS]
    after 400
    set v1 [rd VIDS]
    set f0 [expr {$v0 & 0x0FFFFFFF}]
    set f1 [expr {$v1 & 0x0FFFFFFF}]
    puts ""
    puts "=========== VIDEO ==========="
    puts [format "  vidrst_s=%d  vblank=%d hblank=%d de=%d   frames %d -> %d (delta %d)" \
        [expr {($v1>>31)&1}] [expr {($v1>>30)&1}] [expr {($v1>>29)&1}] [expr {($v1>>28)&1}] $f0 $f1 [expr {$f1-$f0}]]
    if {[expr {($v1>>31)&1}]} {
        puts "  ** VIDEO HELD IN RESET (vidrst_s=1) -- clk_pix dead or n_reset low **"
    } elseif {$f1 == $f0} {
        puts "  ** TIMING GENERATOR STOPPED -- frames not advancing **"
    } else {
        puts "  video is scanning normally; a black screen is the guest's doing."
    }
}

# ---- pseudo-DMA stall forensics ------------------------------------------
if {[info exists idx(SDMA)]} {
    set a0 [rd SDMA]
    after 300
    set a1 [rd SDMA]
    set c0 [expr {$a0 & 0x7FFFFF}]
    set c1 [expr {$a1 & 0x7FFFFF}]
    puts ""
    puts "=========== PSEUDO-DMA STALL ==========="
    puts [format "  sdma_berr=%d  scsiDREQ=%d  selectSCSIDMA=%d  selectSCSI=%d"         [expr {($a1>>31)&1}] [expr {($a1>>30)&1}] [expr {($a1>>29)&1}] [expr {($a1>>28)&1}]]
    puts [format "  _cpuReset=%d  _cpuAS=%d(0=asserted)  _cpuRW=%d(0=write)"         [expr {($a1>>27)&1}] [expr {($a1>>26)&1}] [expr {($a1>>25)&1}]]
    puts [format "  sdma_stall_ctr  %d -> %d   (delta %d, target 8125000)" $c0 $c1 [expr {$c1-$c0}]]
    if {[expr {($a1>>31)&1}]} {
        puts "  -> BERR fired. The CPU should have taken a bus error."
    } elseif {$c1 == $c0 && $c1 == 0} {
        puts "  -> COUNTER PINNED AT ZERO: something is resetting it every cycle."
    } elseif {$c1 == $c0} {
        puts "  -> COUNTER FROZEN mid-count: the increment condition went false."
    } else {
        puts "  -> counter is climbing; timeout simply has not been reached yet."
    }
}

# ---- interrupt-storm forensics -------------------------------------------
if {[info exists idx(IRQS)]} {
    set b0 [rd IRQS]
    after 500
    set b1 [rd IRQS]
    set n0 [expr {$b0 & 0xFFFFFF}]
    set n1 [expr {$b1 & 0xFFFFFF}]
    set ipl [expr {($b1>>29) & 0x7}]
    set name "none"
    if {$ipl == 3} { set name "LEVEL 4 - SCC" }
    if {$ipl == 5} { set name "LEVEL 2 - PseudoVIA (VBlank/slots/ASC)" }
    if {$ipl == 6} { set name "LEVEL 1 - VIA1" }
    puts ""
    puts "=========== INTERRUPTS ==========="
    puts [format "  _cpuIPL = %03b  -> %s" $ipl $name]
    puts [format "  pseudovia_irq=%d  asc_irq=%d  vblank_s=%d  in_iack=%d  overlay=%d"         [expr {($b1>>28)&1}] [expr {($b1>>27)&1}] [expr {($b1>>26)&1}]         [expr {($b1>>25)&1}] [expr {($b1>>24)&1}]]
    puts [format "  interrupts acked: %d -> %d  (delta %d in ~0.5 s)" $n0 $n1 [expr {$n1-$n0}]]
    set d [expr {$n1-$n0}]
    if {$d > 2000} {
        puts "  -> INTERRUPT STORM. A source is stuck asserted; the ISR cannot clear it."
    } elseif {$d > 0 && $d < 200} {
        puts "  -> plausible periodic tick rate (VBlank is ~60/s)."
    } elseif {$d == 0} {
        puts "  -> no interrupts being taken at all."
    }
}

end_insystem_source_probe
