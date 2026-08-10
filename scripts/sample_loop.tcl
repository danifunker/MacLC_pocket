# Rapid sampler for the live PIFD {PC[15:0], opcode} and PDRD
# {ioaddr[19:4], value} pairs — reconstructs a stable wedge/poll loop from
# repeated JTAG snapshots (remote disassembler). Ported from lbmactwo
# (it decoded the System 7 TIB settle loop with exactly this).
#
#   quartus_stp_tcl -t scripts/sample_loop.tcl [n_samples] > samples.txt
#   python scripts/loop_disasm.py samples.txt
#
# Output lines (parse-friendly):
#   IFPAIR <addr16hex> <op16hex>
#   IORD   <addrfield16hex> <val16hex>

set n 80
if {$argc >= 1} { set n [lindex $argv 0] }

set hw ""
foreach h [get_hardware_names] {
    if {[string match "DE-SoC*" $h]} { set hw $h; break }
}
if {$hw eq ""} {
    foreach h [get_hardware_names] {
        if {![catch {get_device_names -hardware_name $h} devs]} {
            foreach d $devs { if {[string match "*5CSE*" $d]} { set hw $h; break } }
        }
        if {$hw ne ""} break
    }
}
set dev ""
if {$hw ne ""} {
    foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d; break } }
}
puts "hw=$hw dev=$dev"

set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
set i 0
foreach inst $info {
    set nm [lindex $inst 3]
    if {$nm eq "PIFD"} { set idx(PIFD) $i }
    if {$nm eq "PDRD"} { set idx(PDRD) $i }
    incr i
}
if {![info exists idx(PIFD)]} { puts "NO PIFD probe"; exit 1 }

start_insystem_source_probe -device_name $dev -hardware_name $hw
for {set s 0} {$s < $n} {incr s} {
    set fp [read_probe_data -instance_index $idx(PIFD) -value_in_hex]
    scan $fp %x fpv
    puts [format "IFPAIR %04X %04X" [expr {($fpv >> 16) & 0xFFFF}] [expr {$fpv & 0xFFFF}]]
    if {[info exists idx(PDRD)]} {
        set dr [read_probe_data -instance_index $idx(PDRD) -value_in_hex]
        scan $dr %x drv
        puts [format "IORD %04X %04X" [expr {($drv >> 16) & 0xFFFF}] [expr {$drv & 0xFFFF}]]
    }
}
end_insystem_source_probe -device_name $dev -hardware_name $hw
