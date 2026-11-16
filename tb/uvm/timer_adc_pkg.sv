// =====================================================================
//  FILE        : tb/uvm/timer_adc_pkg.sv
//  PACKAGE     : timer_adc_pkg
// ---------------------------------------------------------------------
//  The UVM package. It `include-s every UVM class file, in this order
//  (a later file uses classes from an earlier one, so ORDER MATTERS):
//
//    1 apb_agent.sv            bus item, driver, monitor, agent
//    2 adc_agent.sv            voltage driver, result monitor, agent
//    3 timer_adc_scoreboard.sv reference model + checks
//    4 timer_adc_coverage.sv   functional coverage
//    5 timer_adc_env.sv        environment (builds + connects all above)
//    6 timer_adc_seq_lib.sv    stimulus (virtual sequences)
//    7 timer_adc_tests.sv      the runnable tests
//
//  The two interfaces are also included here (before the package) so
//  that they are always compiled first.
//
//  In Vivado ONLY this file and tb_top.sv are added as simulation
//  sources; the include directories make the `include lines work.
// =====================================================================

`timescale 1ns/1ps

`include "apb_if.sv"
`include "adc_if.sv"

package timer_adc_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ---------------- register addresses (same as rtl/apb_regs8.v) ----
    localparam bit [3:0] TMR_CTRL   = 4'h0;
    localparam bit [3:0] TMR_PRESC  = 4'h1;
    localparam bit [3:0] TMR_LOAD   = 4'h2;
    localparam bit [3:0] TMR_CMP    = 4'h3;
    localparam bit [3:0] TMR_CNT    = 4'h4;
    localparam bit [3:0] ADC_CTRL   = 4'h5;
    localparam bit [3:0] ADC_SMP    = 4'h6;
    localparam bit [3:0] ADC_DIV    = 4'h7;
    localparam bit [3:0] ADC_THR_LO = 4'h8;
    localparam bit [3:0] ADC_THR_HI = 4'h9;
    localparam bit [3:0] ADC_DATA   = 4'hA;
    localparam bit [3:0] ADC_RCH    = 4'hB;
    localparam bit [3:0] ADC_STAT   = 4'hC;
    localparam bit [3:0] IRQ_EN     = 4'hD;
    localparam bit [3:0] IRQ_STAT   = 4'hE;
    localparam bit [3:0] ID_REG     = 4'hF;

    // ---------------- ADC math (must match sv/afe_model.v) -------------
    // expected code for a voltage in mV:  floor(mv * 256 / 3300), max 255
    function automatic bit [7:0] code_of_mv(int mv);
        int c;
        c = (mv * 256) / 3300;
        if (c > 255) c = 255;
        if (c < 0)   c = 0;
        return c[7:0];
    endfunction

    // smallest voltage (mV) that gives exactly code c
    function automatic int mv_of_code(int c);
        return (c * 3300 + 255) / 256;
    endfunction

    `include "apb_agent.sv"
    `include "adc_agent.sv"
    `include "timer_adc_scoreboard.sv"
    `include "timer_adc_coverage.sv"
    `include "timer_adc_env.sv"
    `include "timer_adc_seq_lib.sv"
    `include "timer_adc_tests.sv"

endpackage
