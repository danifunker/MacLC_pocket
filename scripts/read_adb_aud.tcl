# Read the MacLC ADB + AUD In-System probes over JTAG.
#   quartus_stp_tcl -t scripts/read_adb_aud.tcl
#
# AUD (32b): [15:0]=ASC write count   [31:16]=ASC read count   (both sticky)
# ADB (64b): [7:0]=last command [11:8]=mouse_addr [15:12]=kbd_addr
#            [23:16]=mtalk(mouse Talk-R0 polls)  [31:24]=mmove(PS2 moves seen)
#            [39:32]=mresp(mouse data sent)       [47:40]=ktalk(kbd polls)
#            [55:48]=kbd_evt(keys into FIFO)      [63:56]=ksrq(kbd Service Requests)

set hw ""
foreach h [get_hardware_names] { foreach d [get_device_names -hardware_name $h] { if {[string match "*5CSE*" $d]} { set hw $h; set dev $d; break } }; if {$hw ne ""} break }
puts "hw=$hw dev=$dev"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
set idxADB -1; set idxAUD -1; set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "ADB"} { set idxADB $i }
    if {$nm eq "AUD"} { set idxAUD $i }
    incr i
}
catch { end_insystem_source_probe }
start_insystem_source_probe -device_name $dev -hardware_name $hw
after 300
proc rd {i} { for {set r 0} {$r < 6} {incr r} { if {![catch {read_probe_data -instance_index $i -value_in_hex} v]} { return [expr 0x$v] }; after 40 }; return 0 }
proc fld {v sh m} { return [expr ($v >> $sh) & $m] }

if {$idxAUD >= 0} {
    set v [rd $idxAUD]
    set wr [fld $v 0 0xFFFF]; set rdc [fld $v 16 0xFFFF]
    puts "AUD: ASC writes=$wr  ASC reads=$rdc"
    puts "AUD: => [expr {$wr>0 ? {CPU FEEDS ASC (issue is ASC sample-gen / output)} : ($rdc>0 ? {CPU PROBES ASC but NEVER writes (ROM/OS audio path)} : {CPU never touches ASC (selectASC decode / not mapped)})}]"
}

if {$idxADB >= 0} {
    set v0 [rd $idxADB]
    set v1 $v0
    for {set k 0} {$k < 80} {incr k} { set v1 [rd $idxADB]; after 60 }
    puts "ADB: mouse_addr=[fld $v1 8 0xF]  kbd_addr=[fld $v1 12 0xF]  last_cmd=[format %02x [fld $v1 0 0xFF]]"
    puts "ADB over ~5s window (TYPE ON THE KEYBOARD now!):"
    puts "  mtalk  mouse-polls : [fld $v0 16 0xFF] -> [fld $v1 16 0xFF]"
    puts "  mmove  PS2-moves   : [fld $v0 24 0xFF] -> [fld $v1 24 0xFF]"
    puts "  mresp  data-sent   : [fld $v0 32 0xFF] -> [fld $v1 32 0xFF]"
    puts "  ktalk  kbd-polls   : [fld $v0 40 0xFF] -> [fld $v1 40 0xFF]"
    puts "  kbd_evt keys->FIFO : [fld $v0 48 0xFF] -> [fld $v1 48 0xFF]"
    puts "  ksrq   kbd SRQs    : [fld $v0 56 0xFF] -> [fld $v1 56 0xFF]"
    puts "ADB: => [expr {[fld $v1 48 0xFF]==[fld $v0 48 0xFF] ? {kbd_evt FLAT: keys NOT reaching adb_device (PS2/decode path)} : ([fld $v1 40 0xFF]!=[fld $v0 40 0xFF] ? {kbd IS polled (ktalk climbs) - keyboard path OK} : {keys reach FIFO + SRQ asserted but Egret never polls kbd (Egret SRQ/autopoll issue)})}]"
}

end_insystem_source_probe
