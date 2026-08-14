# Decode the BDST probe: the blockdev serving story in one word.
#   quartus_stp_tcl -t scripts/read_bdst.tcl
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(BDST)]} { puts "MISSING BDST (old fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
scan [read_probe_data -instance_index $idx(BDST) -value_in_hex] %x v
set v [expr {$v & 0xFFFFFFFF}]
puts [format "BDST raw = %08X" $v]
puts [format "  saw_tmo (OS failed to answer)   : %d" [expr {($v >> 31) & 1}]]
puts [format "  read raised to host             : %d" [expr {($v >> 30) & 1}]]
puts [format "  host acked                      : %d" [expr {($v >> 29) & 1}]]
puts [format "  host completed (done)           : %d" [expr {($v >> 28) & 1}]]
puts [format "  sector delivered to machine     : %d" [expr {($v >> 27) & 1}]]
puts [format "  mount seen                      : %d" [expr {($v >> 26) & 1}]]
puts [format "  mount count (mod 8)             : %d" [expr {($v >> 23) & 7}]]
set blks [expr {$v & 0x7FFFFF}]
puts [format "  img_size blocks (last mount)    : %d (%.1f MB)" $blks [expr {$blks / 2048.0}]]
if {[info exists idx(BDW0)]} {
    scan [read_probe_data -instance_index $idx(BDW0) -value_in_hex] %x w
    set w [expr {$w & 0xFFFFFFFF}]
    puts [format "  last sector words 0,1           : %04X %04X (block 0 expects 4552 0200)" \
        [expr {($w >> 16) & 0xFFFF}] [expr {$w & 0xFFFF}]]
}
if {[info exists idx(BDLB)]} {
    scan [read_probe_data -instance_index $idx(BDLB) -value_in_hex] %x l
    set l [expr {$l & 0xFFFFFFFF}]
    puts [format "  deliveries=%d  last LBA=%d" [expr {($l >> 24) & 0xFF}] [expr {$l & 0xFFFFFF}]]
}
if {[info exists idx(BDWR)]} {
    scan [read_probe_data -instance_index $idx(BDWR) -value_in_hex] %x wr
    set wr [expr {$wr & 0xFFFFFFFF}]
    puts [format "  WRITES: err=%d count=%d last write LBA=%d" \
        [expr {($wr >> 31) & 1}] [expr {($wr >> 24) & 0x7F}] [expr {$wr & 0xFFFFFF}]]
}
if {[info exists idx(BDWW)]} {
    scan [read_probe_data -instance_index $idx(BDWW) -value_in_hex] %x ww
    set ww [expr {$ww & 0xFFFFFFFF}]
    puts [format "  last WRITTEN sector words 0,1   : %04X %04X (staged, file order)" \
        [expr {($ww >> 16) & 0xFFFF}] [expr {$ww & 0xFFFF}]]
}
if {[info exists idx(AMNT)]} {
    scan [read_probe_data -instance_index $idx(AMNT) -value_in_hex] %x am
    set am [expr {$am & 0xFFFFFFFF}]
    # Launch-time auto-mount scan (core_top AMNT). state 7 = scan finished.
    # On a card boot expect fired>=1, armed=1, state=7. After a JTAG push the
    # table is wiped: fired=0/armed=0 is NORMAL there (use jmnt.tcl instead).
    puts [format "  AMNT launch scan: fired=%d armed=%d state=%d entry=%d last_id=%d" \
        [expr {($am >> 28) & 0xF}] [expr {($am >> 27) & 1}] [expr {($am >> 24) & 7}] \
        [expr {($am >> 16) & 0x1F}] [expr {$am & 0xFFFF}]]
}
if {[info exists idx(SDW0)]} {
    scan [read_probe_data -instance_index $idx(SDW0) -value_in_hex] %x sw
    set sw [expr {$sw & 0xFFFFFFFF}]
    puts [format "  CPU-received words 0,1 (last burst): %04X %04X   <- compare with blockdev words above" \
        [expr {($sw >> 16) & 0xFFFF}] [expr {$sw & 0xFFFF}]]
}
if {[info exists idx(SDCT)]} {
    scan [read_probe_data -instance_index $idx(SDCT) -value_in_hex] %x sc
    set sc [expr {$sc & 0xFFFFFFFF}]
    puts [format "  bursts=%d  prev-burst beats=%d  current=%d   (word sector=256 beats, byte=512)" \
        [expr {($sc >> 24) & 0xFF}] [expr {($sc >> 12) & 0xFFF}] [expr {$sc & 0xFFF}]]
}
if {[info exists idx(SCS1)]} {
    scan [read_probe_data -instance_index $idx(SCS1) -value_in_hex] %x s1
    set s1 [expr {$s1 & 0xFFFFFFFF}]
    puts [format "  SCS1=%08X  phase0=%d phase1=%d io_rd=%d%d io_wr=%d%d io_ack=%d%d" $s1 \
        [expr {($s1 >> 24) & 7}] [expr {($s1 >> 27) & 7}] \
        [expr {($s1 >> 21) & 1}] [expr {($s1 >> 20) & 1}] \
        [expr {($s1 >> 19) & 1}] [expr {($s1 >> 18) & 1}] \
        [expr {($s1 >> 17) & 1}] [expr {($s1 >> 16) & 1}]]
    puts [format "        out_en=%d SEL=%d BSY=%d tbsy=%d%d mounted=%d%d adata=%d busdata=%02X" \
        [expr {($s1 >> 15) & 1}] [expr {($s1 >> 14) & 1}] [expr {($s1 >> 13) & 1}] \
        [expr {($s1 >> 12) & 1}] [expr {($s1 >> 11) & 1}] \
        [expr {($s1 >> 10) & 1}] [expr {($s1 >> 9) & 1}] \
        [expr {($s1 >> 8) & 1}] [expr {$s1 & 0xFF}]]
}
if {[info exists idx(CDA1)]} {
    scan [read_probe_data -instance_index $idx(CDA1) -value_in_hex] %x c1
    set c1 [expr {$c1 & 0xFFFFFFFF}]
    puts [format "  CD: toc_rdy=%d no_media=%d mounted=%d ok=%d sense_asc=%02X sense_key=%X cmds=%d last_op=%02X" \
        [expr {($c1 >> 31) & 1}] [expr {($c1 >> 30) & 1}] [expr {($c1 >> 29) & 1}] \
        [expr {($c1 >> 28) & 1}] [expr {($c1 >> 20) & 0xFF}] [expr {($c1 >> 16) & 0xF}] \
        [expr {($c1 >> 8) & 0xFF}] [expr {$c1 & 0xFF}]]
}
if {[info exists idx(CDPH)]} {
    scan [read_probe_data -instance_index $idx(CDPH) -value_in_hex] %x cp
    set cp [expr {$cp & 0xFFFF}]
    puts [format "  CD LIVE: bsy=%d phase=%d hs=%02X hs2=%X   (bsy=1 with phase!=0 parked = the disk-deafening wedge)" \
        [expr {($cp >> 15) & 1}] [expr {($cp >> 12) & 7}] [expr {($cp >> 4) & 0xFF}] [expr {$cp & 0xF}]]
}
if {[info exists idx(PSN1)]} {
    scan [read_probe_data -instance_index $idx(PSN1) -value_in_hex] %x p1
    set p1 [expr {$p1 & 0xFFFFFFFF}]
    puts [format "  PSN1(@window)=%08X phase0=%d phase1=%d io_rd=%d%d io_ack=%d%d | out_en=%d SEL=%d BSY=%d tbsy=%d%d mounted=%d%d busdata=%02X" $p1 \
        [expr {($p1 >> 24) & 7}] [expr {($p1 >> 27) & 7}] \
        [expr {($p1 >> 21) & 1}] [expr {($p1 >> 20) & 1}] \
        [expr {($p1 >> 17) & 1}] [expr {($p1 >> 16) & 1}] \
        [expr {($p1 >> 15) & 1}] [expr {($p1 >> 14) & 1}] [expr {($p1 >> 13) & 1}] \
        [expr {($p1 >> 12) & 1}] [expr {($p1 >> 11) & 1}] \
        [expr {($p1 >> 10) & 1}] [expr {($p1 >> 9) & 1}] [expr {$p1 & 0xFF}]]
}
if {[info exists idx(PSN2)]} {
    scan [read_probe_data -instance_index $idx(PSN2) -value_in_hex] %x p2
    set p2 [expr {$p2 & 0xFFFFFFFF}]
    puts [format "  PSN2(@window) opcodes tgt0=%02X tgt1=%02X rst=%d hs2_t1=%X hs2_t0=%X" \
        [expr {($p2 >> 16) & 0xFF}] [expr {($p2 >> 24) & 0xFF}] \
        [expr {($p2 >> 8) & 0xFF}] [expr {($p2 >> 4) & 0xF}] [expr {$p2 & 0xF}]]
}
if {[info exists idx(EGS1)]} {
    scan [read_probe_data -instance_index $idx(EGS1) -value_in_hex] %x e1
    set e1 [expr {$e1 & 0xFFFFFFFF}]
    puts [format "  EGRET@window: SR=%02X bit=%d edgeP=%d fallP=%d act=%d dir=%d CB1=%d CB2=%d | TREQ=%d TIP=%d BYTEACK=%d run=%d" \
        [expr {($e1 >> 16) & 0xFF}] [expr {($e1 >> 12) & 7}] \
        [expr {($e1 >> 11) & 1}] [expr {($e1 >> 10) & 1}] \
        [expr {($e1 >> 9) & 1}] [expr {($e1 >> 8) & 1}] \
        [expr {($e1 >> 7) & 1}] [expr {($e1 >> 6) & 1}] \
        [expr {($e1 >> 5) & 1}] [expr {($e1 >> 4) & 1}] \
        [expr {($e1 >> 3) & 1}] [expr {($e1 >> 2) & 1}]]
}
if {[info exists idx(EGS2)]} {
    scan [read_probe_data -instance_index $idx(EGS2) -value_in_hex] %x e2
    set e2 [expr {$e2 & 0xFFFFFFFF}]
    puts [format "  EGRET counters since arm: cb1_falls=%d byteack_tgl=%d tip_tgl=%d" \
        [expr {($e2 >> 20) & 0xFFF}] [expr {($e2 >> 10) & 0x3FF}] [expr {$e2 & 0x3FF}]]
}
if {[info exists idx(EGS3)]} {
    scan [read_probe_data -instance_index $idx(EGS3) -value_in_hex] %x e3
    puts [format "  HC05 PC @window: %04X   (map: rtl/egret/egret_rom_disasm.md)" [expr {$e3 & 0xFFFF}]]
}
if {[info exists idx(SCS2)]} {
    scan [read_probe_data -instance_index $idx(SCS2) -value_in_hex] %x s2
    set s2 [expr {$s2 & 0xFFFFFFFF}]
    puts [format "  SCS2=%08X  LAST OPCODE tgt0=%02X tgt1=%02X  rst_count=%d hs2_t1=%X hs2_t0=%X" $s2 \
        [expr {($s2 >> 16) & 0xFF}] [expr {($s2 >> 24) & 0xFF}] \
        [expr {($s2 >> 8) & 0xFF}] [expr {($s2 >> 4) & 0xF}] [expr {$s2 & 0xF}]]
    puts "        (opcodes: 00=TUR 03=REQ-SENSE 08=READ6 12=INQUIRY 15=MODE-SEL 1A=MODE-SENSE 25=READCAP 28=READ10)"
}
end_insystem_source_probe
