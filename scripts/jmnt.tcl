# JMNT lever (buildAR): inject a dataslot_update mount event into a freshly
# JTAG-pushed fabric, replacing the "you re-mount via OSD" step of every
# capture round. Serving still comes from the Analogue OS (target_dataslot_read
# against whatever file the OS currently associates with the slot) -- this only
# tells the fabric that the slot is mounted and how big the image is.
#
#   quartus_stp_tcl -t scripts/jmnt.tcl <slot> <bytes>
#   quartus_stp_tcl -t scripts/jmnt.tcl status
#
#   slot  : 310 (HD1) | 311 (HD2) | 320 (CD) | 210 (floppy), or hd0/hd1/cd/flp
#   bytes : image size in bytes. MUST match (or over-declare) the real file:
#           an over-declared capacity is benign (the guest reads within the
#           HFS volume), an under-declared one truncates the disk.
#           Known images: maclc.hda = 41992192, Mac68KColorGames_v1.hda =
#           786473472 (mined from the 08-13 session transcript).
#
# Verify with read_bdst.tcl afterwards: "mount seen" latches and img_size
# blocks = bytes/512. The machine's "?" scan loop picks the disk up on its
# own; jboot for a full clean round.
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(JMNT)]} { puts "MISSING JMNT (pre-buildAR fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw

set cmd [lindex $quartus(args) 0]
if {$cmd eq "" || $cmd eq "status"} {
    scan [read_probe_data -instance_index $idx(JMNT) -value_in_hex] %x f
    puts "JMNT present, fire bit = $f (probe loops back source\[48\])"
    end_insystem_source_probe
    exit 0
}

array set slotmap {hd0 310 hd1 311 cd 320 flp 210}
set slot $cmd
if {[info exists slotmap($slot)]} { set slot $slotmap($slot) }
if {![string is integer -strict $slot]} { puts "bad slot: $cmd"; exit 1 }
set bytes [lindex $quartus(args) 1]
if {![string is integer -strict $bytes]} { puts "bad/missing byte size: $bytes"; exit 1 }

# Fire = invert the looped-back bit so every invocation lands one edge.
scan [read_probe_data -instance_index $idx(JMNT) -value_in_hex] %x fire
set fire [expr {(~$fire) & 1}]
set val [format "0x%013llX" [expr {($fire << 48) | (($slot & 0xFFFF) << 32) | ($bytes & 0xFFFFFFFF)}]]
write_source_data -instance_index $idx(JMNT) -value $val -value_in_hex
puts "JMNT fired: slot $slot size $bytes bytes ([expr {$bytes / 512}] blocks) fire=$fire"
puts "  confirm with read_bdst.tcl (mount seen / img_size blocks)"
end_insystem_source_probe
