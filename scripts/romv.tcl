# ROM retention verify (ROMV v3, completion-paired reads): full-ROM scans of
# the 512 KB region read back OUT of SDRAM (machine held in reset ~0.5 s per
# scan) compared against the known-good sums. THE decay oracle.
# Runs 3 scans by default so repeat-scan stability comes for free.
#   quartus_stp_tcl -t scripts/romv.tcl [nscans]
# Trigger encoding (v4): src[31]=go rising edge, src[27:5]=ABSOLUTE 23-bit
# SDRAM word base (ROM region at word 500000), src[4:0]=log2len.
# Full ROM = arm 0x0A000012 then fire 0x8A000012. (v3 ref sums still apply:
# the 500000 base adds 5*2^38 across 2^18 XOR terms, which is 0 mod 2^32.)
set nscans 3
if {[llength $quartus(args)] > 0} { set nscans [lindex $quartus(args) 0] }

set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
foreach need {ROMV RVSU RVAX} { if {![info exists idx($need)]} { puts "MISSING $need"; exit 1 } }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set ref_s [expr {0x350F8EEE}]
set ref_a [expr {0xF486F3D8}]
set allmatch 1
for {set n 1} {$n <= $nscans} {incr n} {
    # arm (go=0) then fire (go=1 rising edge)
    write_source_data -instance_index $idx(ROMV) -value 0x0A000012 -value_in_hex
    write_source_data -instance_index $idx(ROMV) -value 0x8A000012 -value_in_hex
    set st 0
    for {set i 0} {$i < 100} {incr i} {
        after 50
        scan [read_probe_data -instance_index $idx(ROMV) -value_in_hex] %x st
        if {($st & 0x3) == 2} { break }
    }
    scan [read_probe_data -instance_index $idx(RVSU) -value_in_hex] %x s
    scan [read_probe_data -instance_index $idx(RVAX) -value_in_hex] %x a
    set s [expr {$s & 0xFFFFFFFF}]
    set a [expr {$a & 0xFFFFFFFF}]
    if {($st & 0x3) != 2} {
        puts [format "scan %d: DID NOT COMPLETE (status=%d) sum=%08X axsum=%08X" $n [expr {$st & 3}] $s $a]
        set allmatch 0
        continue
    }
    set verdict [expr {($s == $ref_s && $a == $ref_a) ? "MATCH" : "DIFFER"}]
    if {$verdict ne "MATCH"} { set allmatch 0 }
    puts [format "scan %d: status=%d  sum=%08X  axsum=%08X  -> %s" $n [expr {$st & 3}] $s $a $verdict]
}
puts "reference:      sum=350F8EEE  axsum=F486F3D8  (intact boot0.rom)"
if {$allmatch} {
    puts "-> ROM RETENTION GOOD: SDRAM holds the ROM byte-perfect, stable across scans."
} else {
    puts "-> MISMATCH: real content difference (stable) or instrument fault (unstable)."
    puts "   Next: scripts/romv_search.tcl to locate words (needs scratch/rom_words.tcl)."
}
# leave go low so the next fire is a clean rising edge
write_source_data -instance_index $idx(ROMV) -value 0x000000 -value_in_hex
end_insystem_source_probe
