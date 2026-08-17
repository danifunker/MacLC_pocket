# placement_probe.tcl — dump the PHYSICAL placement of a timing path's nodes.
#
# This is the deepest readable view of a build. The .rbf/.sof bitstream itself
# is a proprietary undocumented format — diffing it tells you nothing (and is
# actively misleading, since it is compressed: two functionally identical
# builds differ in ~86% of their bytes). What IS readable is the fitted
# netlist in the compilation database: every node's LAB/register coordinate.
#
# Comparing these coordinates between a good and a bad build answers the
# question the whole investigation now turns on:
#   - same logic, different COORDINATES  -> placement/electrical marginality
#   - different node names or node COUNT -> synthesis restructured the cone,
#                                           i.e. the "netlist alignment" class
#                                           MiSTer's anchor comment describes
#
# Requires the build's db/ directory. Run from that build's src/fpga.
project_open ap_core
create_timing_netlist -model slow -speed 8
read_sdc "apf/apf_constraints.sdc"
read_sdc "core/core_constraints.sdc"
read_sdc "core/maclc_constraints.sdc"
update_timing_netlist

# The CPU-side SDRAM write cone — the path family implicated by the
# Finder-load failure signature.
puts "@@@@ SDRAM WRITE CONE — node placement"
set n 0
foreach_in_collection p [get_timing_paths -setup -npaths 3 \
                          -to [get_ports {dram_dq[*]}] -detail full_path] {
    incr n
    puts [format "@@ path %d  slack=%s" $n [get_path_info $p -slack]]
    foreach_in_collection pt [get_path_info $p -arrival_points] {
        set nd [get_point_info $pt -node]
        if {$nd eq ""} { continue }
        puts [format "@@    %-46s %s" \
              [get_node_info -name $nd] [get_node_info -location $nd]]
    }
}
delete_timing_netlist
project_close
