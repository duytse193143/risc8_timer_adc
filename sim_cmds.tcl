# =====================================================================
#  sim_cmds.tcl  -  helper commands for the Vivado Tcl Console
#
#  Loaded by create_project.tcl. After re-opening Vivado load it again:
#      source C:/.../risc8_timer_adc/sim_cmds.tcl
#
#  uvm_run <test> [seed]   run one UVM test of the Timer + ADC (sim_uvm)
#  sim_run <simset>        run a non-UVM set: sim_1 (system) or sim_cpu
#  run_all                 every test of the project + PASS/FAIL table
#  list_tests              print the test names
# =====================================================================

set ::tadc_tests {tadc_reg_test tadc_timer_test tadc_adc_sw_test tadc_adc_timer_test
                  tadc_adc_cont_test tadc_window_test tadc_random_test tadc_all_test}

proc list_tests {} {
    puts "UVM Timer + ADC  (uvm_run): $::tadc_tests"
    puts "Directed         (sim_run): sim_1  sim_cpu"
}

proc sim_log {fs} {
    set dir  [get_property DIRECTORY [current_project]]
    set name [get_property NAME      [current_project]]
    return "$dir/$name.sim/$fs/behav/xsim/simulate.log"
}

# look for a word in the log of a simulation set
proc log_result {fs pass_word fail_word} {
    set r "UNKNOWN"
    if {[file exists [sim_log $fs]]} {
        set fh [open [sim_log $fs] r]; set txt [read $fh]; close $fh
        if {[string first $pass_word $txt] >= 0} { set r "PASSED" }
        if {[string first $fail_word $txt] >= 0} { set r "FAILED" }
    }
    return $r
}

proc uvm_run {test {seed 1}} {
    set fs sim_uvm
    catch {close_sim -force -quiet}
    set_property -name {xsim.simulate.xsim.more_options} \
        -value "-testplusarg UVM_TESTNAME=$test -testplusarg UVM_VERBOSITY=UVM_LOW -sv_seed $seed" \
        -objects [get_filesets $fs]
    current_fileset -simset [get_filesets $fs]
    puts "\n>>> $test  ($fs, seed $seed)"
    launch_simulation -simset $fs -mode behavioral
    set r [log_result $fs "PASSED" "FAILED"]
    puts ">>> $test : $r"
    return $r
}

proc sim_run {fs} {
    catch {close_sim -force -quiet}
    current_fileset -simset [get_filesets $fs]
    puts "\n>>> $fs"
    launch_simulation -simset $fs -mode behavioral
    if {$fs eq "sim_cpu"} {
        set r [log_result $fs "ALL TESTS PASSED" "FAILED"]
    } else {
        set r [log_result $fs "SOC TEST PASSED" "SOC TEST FAILED"]
    }
    puts ">>> $fs : $r"
    return $r
}

proc run_all {} {
    set table {}
    foreach t $::tadc_tests { lappend table [list "UVM  $t" [uvm_run $t]] }
    lappend table [list "sim_1   system test (22 checks)" [sim_run sim_1]]
    lappend table [list "sim_cpu original CPU test"       [sim_run sim_cpu]]
    catch {close_sim -force -quiet}
    puts "\n==================== PROJECT 3 REGRESSION ===================="
    foreach row $table { puts [format "  %-36s %s" [lindex $row 0] [lindex $row 1]] }
    puts "=============================================================="
}

puts "sim_cmds.tcl loaded: uvm_run <test>, sim_run sim_1|sim_cpu, run_all, list_tests"
