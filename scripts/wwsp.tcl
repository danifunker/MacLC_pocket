# WWSP (buildAX): last 8 writes to $3FF7xx (boot-stack band) / $400Exx
# (BootGlobals) with the WRITER's PC. Frozen/re-armed with the IIOP deck
# (iiop.tcl rearm). Decode newest-first.
#   quartus_stp_tcl -t scripts/wwsp.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(WWSP)]} { puts "MISSING WWSP (pre-buildAX fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set raw [read_probe_data -instance_index $idx(WWSP) -value_in_hex]
regsub {^0x} $raw {} raw
# 395 bits -> 99 hex digits
while {[string length $raw] < 99} { set raw "0$raw" }
end_insystem_source_probe

# bit extractor over the hex string (LSB = bit 0)
proc bits {raw lo hi} {
    set nhex [string length $raw]
    set v 0
    for {set b $hi} {$b >= $lo} {incr b -1} {
        set nib [string index $raw [expr {$nhex - 1 - $b/4}]]
        scan $nib %x nv
        set v [expr {($v << 1) | (($nv >> ($b % 4)) & 1)}]
    }
    return $v
}

# layout LSB-first: slot0 [47:0] ... slot7 [383:336], cnt [391:384], wptr [394:392]
set wptr [bits $raw 392 394]
set cnt  [bits $raw 384 391]
puts "WWSP raw = $raw"
puts "wptr=$wptr cnt=$cnt (newest = slot [expr {($wptr + 7) % 8}])"
for {set k 7} {$k >= 0} {incr k -1} {
    set s [expr {($wptr + $k) % 8}]
    set lo [expr {$s * 48}]
    set pc   [bits $raw $lo [expr {$lo + 23}]]
    set data [bits $raw [expr {$lo + 24}] [expr {$lo + 39}]]
    set off  [bits $raw [expr {$lo + 40}] [expr {$lo + 46}]]
    set page [bits $raw [expr {$lo + 47}] [expr {$lo + 47}]]
    set base [expr {$page ? 0x400E00 : 0x3FF700}]
    set addr [expr {$base + ($off << 1)}]
    set tag  [expr {$k == 7 ? "  <- newest" : ""}]
    puts [format "  slot %d: \$%06X <- %04X   wpc=%06X%s" $s $addr $data $pc $tag]
}
puts "ROM wpc -> disasm line 40800000+(pc&7FFFF); RAM wpc = System code"
