# IIOP (buildAS): the faulting fetch, data included. Decodes the 248-bit
# probe: last 4 completed FETCH cycles {pc,data}, last 2 completed cycles of
# any busstate {bs,addr,data}, frozen at the vector-4 dispatch read ($10).
#   quartus_stp_tcl -t scripts/iiop.tcl          read/decode
#   quartus_stp_tcl -t scripts/iiop.tcl rearm    re-arm (unfreeze + clear)
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(IIOP)]} { puts "MISSING IIOP (pre-buildAS fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set cmd [lindex $quartus(args) 0]
if {$cmd eq "rearm"} {
    # source is 1 bit; write alternating values via arg (any edge re-arms).
    set v [lindex $quartus(args) 1]
    if {$v eq ""} { set v 1 }
    write_source_data -instance_index $idx(IIOP) -value $v
    puts "IIOP re-armed (source=$v; any edge clears+unfreezes)"
    end_insystem_source_probe
    exit 0
}

set raw [read_probe_data -instance_index $idx(IIOP) -value_in_hex]
regsub {^0x} $raw {} raw
# pad to 62 hex digits (248 bits)
while {[string length $raw] < 62} { set raw "0$raw" }
puts "IIOP raw = $raw"
# widths from LSB: f0..f3 40 each, a0 42, a1 42, wptr 2(+pad), frozen 1
# parse as big integer via chunked scans (Tcl handles big hex via string ops)
proc bits {raw lo hi} {
    # returns integer value of bit range [lo..hi] of the hex string raw (LSB=bit0)
    set nhex [string length $raw]
    set v 0
    for {set b $hi} {$b >= $lo} {incr b -1} {
        set hexidx [expr {$nhex - 1 - $b/4}]
        set nib [string index $raw $hexidx]
        scan $nib %x nv
        set bit [expr {($nv >> ($b & 3)) & 1}]
        set v [expr {($v << 1) | $bit}]
    }
    return $v
}
set frozen [bits $raw 247 247]
set wptr   [bits $raw 244 245]
puts "frozen=$frozen fetch_wptr=$wptr (newest fetch = slot [expr {($wptr+3)%4}])"
for {set i 0} {$i < 4} {incr i} {
    set lo [expr {$i*40}]
    set pc   [bits $raw [expr {$lo+16}] [expr {$lo+39}]]
    set data [bits $raw $lo [expr {$lo+15}]]
    set tag ""
    if {$i == (($wptr+3)%4)} { set tag "  <- newest" }
    puts [format "  fetch slot %d: pc=%06X data=%04X%s" $i $pc $data $tag]
}
foreach {nm lo} {any0 160 any1 202} {
    set data [bits $raw $lo [expr {$lo+15}]]
    set addr [bits $raw [expr {$lo+16}] [expr {$lo+39}]]
    set bs   [bits $raw [expr {$lo+40}] [expr {$lo+41}]]
    puts [format "  %s: busstate=%d addr=%06X data=%04X   (upper=newer; bs 0=fetch 2=read 3=write)" $nm $bs $addr $data]
}
if {[info exists idx(IIO2)]} {
    set raw2 [read_probe_data -instance_index $idx(IIO2) -value_in_hex]
    regsub {^0x} $raw2 {} raw2
    while {[string length $raw2] < 26} { set raw2 "0$raw2" }
    # LSB first: fe_last[23:0], fe_prev[23:0], fe_cnt[7:0], ah0, ah1, fh0..fh3
    set lastD [bits $raw2 0 15];  set lastA [bits $raw2 16 23]
    set prevD [bits $raw2 24 39]; set prevA [bits $raw2 40 47]
    set cnt   [bits $raw2 48 55]
    set ah0   [bits $raw2 56 63]; set ah1 [bits $raw2 64 71]
    puts [format "  PDS probe: %d slot-space cycles; prev a\[8:1\]=%02X data=%04X, last a\[8:1\]=%02X data=%04X (kernel view; expect FFFF)" \
        $cnt $prevA $prevD $lastA $lastD]
    puts [format "  addr TOP BYTES: any0_hi=%02X any1_hi=%02X  fetch_hi(slot0..3)=%02X %02X %02X %02X" \
        $ah0 $ah1 [bits $raw2 72 79] [bits $raw2 80 87] [bits $raw2 88 95] [bits $raw2 96 103]]
}
end_insystem_source_probe
