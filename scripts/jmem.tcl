# JMEM (buildAS): JTAG override of the memory-size register on a pushed
# fabric (the OS never rewrites opt_mem_size after a push -- RESUME §0).
# Sampled at machine reset: set this, then jboot.
#   quartus_stp_tcl -t scripts/jmem.tcl 2      force 2 MB
#   quartus_stp_tcl -t scripts/jmem.tcl 10     force 10 MB
#   quartus_stp_tcl -t scripts/jmem.tcl off    release (RTL default = 10 MB)
#   quartus_stp_tcl -t scripts/jmem.tcl        status
set hw ""
foreach h [get_hardware_names] { if {[string match "USB-Blaster*" $h]} { set hw $h; break } }
if {$hw eq ""} { foreach h [get_hardware_names] { set hw $h; break } }
set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CE*" $d]} { set dev $d; break } }
set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]
array set idx {}
foreach inst $info { set idx([lindex $inst 3]) [lindex $inst 0] }
if {![info exists idx(JMEM)]} { puts "MISSING JMEM (pre-buildAS fabric?)"; exit 1 }
start_insystem_source_probe -device_name $dev -hardware_name $hw
set cmd [lindex $quartus(args) 0]
switch -- $cmd {
    2   { write_source_data -instance_index $idx(JMEM) -value 0x2 -value_in_hex
          puts "JMEM: OVERRIDE 2 MB (jboot to apply)" }
    10  { write_source_data -instance_index $idx(JMEM) -value 0x3 -value_in_hex
          puts "JMEM: OVERRIDE 10 MB (jboot to apply)" }
    off { write_source_data -instance_index $idx(JMEM) -value 0x0 -value_in_hex
          puts "JMEM: released (opt_mem_size register rules; RTL default 10 MB)" }
    default {
        scan [read_probe_data -instance_index $idx(JMEM) -value_in_hex] %x p
        puts "JMEM: enable=[expr {($p>>1)&1}] value=[expr {$p&1}] (1=10MB)"
    }
}
end_insystem_source_probe
