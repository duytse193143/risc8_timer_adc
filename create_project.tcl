# =====================================================================
#  create_project.tcl  -  creates the ONE Vivado project of project 3:
#                         RISC-8 5-stage CPU + 8-bit Timer + 8-bit ADC
#
#  Usage (in Vivado):  Tools > Run Tcl Script... > create_project.tcl
#     or Tcl Console:  source C:/.../risc8_timer_adc/create_project.tcl
#  The project is created in the sub-folder  vivado/
#
#  Simulation sets (pick one with "Make Active", or use sim_cmds.tcl):
#    sim_uvm   tb_top           UVM on the Timer + ADC (8 tests)
#    sim_1     tb_risc8_soc     system test: CPU runs firmware, 22 checks
#    sim_cpu   tb_risc8_5stage  original CPU test (51 cycles, CPI 1.50)
# =====================================================================
set root [file dirname [file normalize [info script]]]

create_project risc8_timer_adc $root/vivado -part xc7a35tcpg236-1 -force

# ---------------------------------------------------------------------
# Design sources: CPU + Timer/ADC peripheral + programs
# ---------------------------------------------------------------------
add_files -fileset sources_1 [glob $root/rtl/*.v]
add_files -fileset sources_1 [glob $root/rtl/periph/*.v]
add_files -fileset sources_1 [list $root/program.hex $root/soc_demo.hex]
set_property file_type {Memory File} [get_files -of_objects [get_filesets sources_1] *.hex]
set_property top risc8_soc [get_filesets sources_1]

# helper: UVM settings for a simulation set
proc uvm_simset {fs top test incdirs} {
    set_property include_dirs $incdirs [get_filesets $fs]
    set_property top     $top           [get_filesets $fs]
    set_property top_lib xil_defaultlib [get_filesets $fs]
    set_property -name {xsim.compile.xvlog.more_options}   -value {-L uvm} -objects [get_filesets $fs]
    set_property -name {xsim.elaborate.xelab.more_options} -value {-L uvm} -objects [get_filesets $fs]
    set_property -name {xsim.simulate.xsim.more_options} \
        -value "-testplusarg UVM_TESTNAME=$test -testplusarg UVM_VERBOSITY=UVM_LOW" -objects [get_filesets $fs]
    set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets $fs]
}
set incdirs [list $root/sv $root/tb/uvm]

# ---------------------------------------------------------------------
# sim_uvm : UVM on the Timer + ADC (the APB register interface)
#   only 4 files; the other UVM files and interfaces are `include-d
# ---------------------------------------------------------------------
create_fileset -simset sim_uvm
add_files -fileset sim_uvm [list \
    $root/tb/afe_model.v \
    $root/sv/timer_adc_sva.sv \
    $root/tb/uvm/timer_adc_pkg.sv \
    $root/tb/uvm/tb_top.sv ]
uvm_simset sim_uvm tb_top tadc_reg_test $incdirs

# ---------------------------------------------------------------------
# sim_1 : directed system test (firmware, 22 checks)
# ---------------------------------------------------------------------
add_files -fileset sim_1 [list $root/tb/tb_risc8_soc.v $root/tb/afe_model.v $root/sv/timer_adc_sva.sv]
set_property top     tb_risc8_soc   [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

# ---------------------------------------------------------------------
# sim_cpu : original project-2 CPU test (regression)
# ---------------------------------------------------------------------
create_fileset -simset sim_cpu
add_files -fileset sim_cpu [list $root/tb/tb_risc8_5stage.v]
set_property top     tb_risc8_5stage [get_filesets sim_cpu]
set_property top_lib xil_defaultlib  [get_filesets sim_cpu]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_cpu]

foreach fs {sources_1 sim_1 sim_cpu sim_uvm} { update_compile_order -fileset $fs }
current_fileset -simset [get_filesets sim_uvm]

source $root/sim_cmds.tcl

puts ""
puts "=================================================================="
puts " Project created: $root/vivado/risc8_timer_adc.xpr"
puts " Try:  uvm_run tadc_reg_test     (UVM, Timer + ADC)"
puts "       sim_run sim_1             (CPU + Timer + ADC system test)"
puts "       run_all                   (every test, PASS/FAIL table)"
puts "=================================================================="
