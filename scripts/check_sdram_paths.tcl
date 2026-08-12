project_open ap_core
create_timing_netlist -model slow
read_sdc
update_timing_netlist
puts "=== clocks that exist ==="
foreach_in_collection c [get_clocks] { puts "  [get_clock_info $c -name]" }
set wr [get_timing_paths -setup -npaths 3 -to [get_ports {dram_dq[*] dram_a[*] dram_we_n}] -detail path_only]
set nwr 0; foreach_in_collection p $wr { incr nwr; puts "WRITE slack=[get_path_info $p -slack] to=[get_node_info -name [get_path_info $p -to]]" }
if {$nwr==0} { puts "*** WRITE PATHS: NONE ANALYSED — the constraint is a no-op ***" }
set rd [get_timing_paths -setup -npaths 3 -from [get_ports {dram_dq[*]}] -detail path_only]
set nrd 0; foreach_in_collection p $rd { incr nrd; puts "READ  slack=[get_path_info $p -slack] to=[get_node_info -name [get_path_info $p -to]]" }
if {$nrd==0} { puts "*** READ PATHS: NONE ANALYSED ***" }
puts "counts: write=$nwr read=$nrd"
delete_timing_netlist
project_close
