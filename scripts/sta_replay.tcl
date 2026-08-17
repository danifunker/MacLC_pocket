# Re-analyse an ALREADY-FITTED netlist. No refit: same placement, same routing.
# Reads the SDCs exactly the way the compile flow does — apf_constraints.sdc
# first (it creates the base clocks, runs derive_pll_clocks, and itself chains
# to core/core_constraints.sdc), then the two qsf-listed files.
# Run from the tree's src/fpga directory.
project_open ap_core

create_timing_netlist -model slow -speed 8

read_sdc "apf/apf_constraints.sdc"
read_sdc "core/core_constraints.sdc"
read_sdc "core/maclc_constraints.sdc"

update_timing_netlist

puts "@@@@ PER-CLOCK WORST SETUP SLACK"
foreach_in_collection clk [get_clocks] {
    set n [get_clock_info -name $clk]
    foreach_in_collection path [get_timing_paths -setup -npaths 1 -to_clock $n] {
        puts [format "@@ setup %-78s %s" $n [get_path_info $path -slack]]
    }
}
puts "@@@@ PER-CLOCK WORST HOLD SLACK"
foreach_in_collection clk [get_clocks] {
    set n [get_clock_info -name $clk]
    foreach_in_collection path [get_timing_paths -hold -npaths 1 -to_clock $n] {
        puts [format "@@ hold  %-78s %s" $n [get_path_info $path -slack]]
    }
}

puts "@@@@ WORST 12 SETUP PATHS (where the critical cone actually is)"
foreach_in_collection path [get_timing_paths -setup -npaths 12] {
    puts [format "@@ %8s  FROM %s" [get_path_info $path -slack] [get_node_info -name [get_path_info $path -from]]]
    puts [format "@@ %8s    TO %s" ""                            [get_node_info -name [get_path_info $path -to]]]
}

delete_timing_netlist
project_close
