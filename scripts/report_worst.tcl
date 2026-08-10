# Report the worst setup paths with full From/To node detail.
project_open MacLC
create_timing_netlist -model slow
read_sdc
update_timing_netlist
puts "===== WORST SETUP PATHS (all clocks) ====="
report_timing -setup -npaths 6 -detail summary -stdout
puts "===== WORST SETUP PATH FULL DETAIL ====="
report_timing -setup -npaths 2 -detail full_path -stdout
project_close
