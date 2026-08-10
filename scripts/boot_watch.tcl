# Rapid whole-boot probe sampler: waits for the MacLC core to appear on the
# JTAG chain (i.e. survives being started while the menu core is up), then
# samples the key probes in a tight loop inside ONE quartus_stp session
# (~5 samples/sec) for the given duration.
#
#   quartus_stp_tcl -t scripts/boot_watch.tcl [seconds] > scratch/boot_watch_log.txt
#
# Output: one line per sample:
#   T<ms> PACT=h PIFA=h PSCS=h PSC3=h PSNC=h PSWL=h PSC6=h PVID=h PASC=h
# Decode offline (layouts in rtl/dbg_probes.sv / scripts/cpu_state.tcl).

set dur 75
if {$argc >= 1} { set dur [lindex $argv 0] }

# Optional 2nd arg: side-channel log file. Quartus block-buffers stdout under
# redirection (4 KB chunks, flush stdout does NOT reach the OS), so live
# monitoring needs a plain Tcl file channel flushed per line.
set side ""
if {$argc >= 2} { set side [open [lindex $argv 1] w] }
proc emit {s} {
    global side
    puts $s
    flush stdout
    if {$side ne ""} { puts $side $s; flush $side }
}

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
emit "hw=$hw dev=$dev"
if {$dev eq ""} { emit "NO DEVICE"; exit 1 }

# Wait (up to 10 min) for a bitstream with ISSP probes — i.e. the MacLC core.
emit "WAITING for MacLC core (probes) on the chain..."
set info ""
for {set w 0} {$w < 1200} {incr w} {
    if {![catch {set info [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw]}] && [llength $info] > 0} break
    after 500
}
if {$info eq ""} { emit "TIMEOUT waiting for probes"; exit 1 }
emit "CORE UP — sampling for $dur s"

array set idx {}
set i 0
foreach inst $info { set idx([lindex $inst 3]) $i; incr i }

proc rd {name} {
    global idx dev hw
    if {![info exists idx($name)]} { return 0 }
    if {[catch {set v [read_probe_data -instance_index $idx($name) -value_in_hex]}]} { return -1 }
    scan $v %x n
    return $n
}

start_insystem_source_probe -device_name $dev -hardware_name $hw
set t0 [clock milliseconds]
set dead 0
while {[clock milliseconds] - $t0 < $dur * 1000} {
    set line [format "T%06d" [expr {[clock milliseconds] - $t0}]]
    set allff 1
    foreach p {PACT PIFA PSCS PSC2 PSC3 PSCW PSNC PSWL PSC6 PVID PSTA PADR PEXC PEX3} {
        set v [rd $p]
        # Only probes that exist in this bitstream may veto the all-FF
        # (reconfig) detector — a missing probe reads as a constant 0.
        if {[info exists idx($p)] && $v != 0xFFFFFFFF && $v != -1} { set allff 0 }
        append line [format " %s=%08X" $p $v]
    }
    emit $line
    if {$allff} {
        incr dead
        if {$dead >= 20} {
            # FPGA reconfigured under us (core reload): the ISSP session is
            # stale and will return all-ones forever. Re-attach: close the
            # session, wait for probes to reappear, re-enumerate, resume.
            emit "RECONFIG_DETECTED — re-attaching..."
            catch { end_insystem_source_probe }
            set info ""
            while {[clock milliseconds] - $t0 < $dur * 1000} {
                if {![catch {set info [get_insystem_source_probe_instance_info \
                        -device_name $dev -hardware_name $hw]}] && [llength $info] > 0} break
                after 300
            }
            if {$info eq ""} break
            array unset idx
            set i 0
            foreach inst $info { set idx([lindex $inst 3]) $i; incr i }
            start_insystem_source_probe -device_name $dev -hardware_name $hw
            emit "REATTACHED"
            set dead 0
        }
    } else {
        set dead 0
    }
}
catch { end_insystem_source_probe }
emit "DONE"
