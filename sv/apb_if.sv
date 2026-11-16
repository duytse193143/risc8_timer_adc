// =====================================================================
//  FILE        : sv/apb_if.sv        (SIMULATION ONLY)
//  INTERFACE   : apb_if
// ---------------------------------------------------------------------
//  Bundle of the 8-bit APB bus wires. The UVM driver drives them, the
//  UVM monitor watches them. Passed to the classes as a
//  "virtual apb_if" handle through uvm_config_db (see tb_top.sv).
//
//  NOTE: this file is `include-d at the top of tb/uvm/timer_adc_pkg.sv,
//        so do NOT add it to the Vivado project separately.
// =====================================================================

`timescale 1ns/1ps

interface apb_if (input logic clk, input logic rst_n);
    logic       psel;
    logic       penable;
    logic       pwrite;
    logic [3:0] paddr;
    logic [7:0] pwdata;
    logic [7:0] prdata;
    logic       pready;
    logic       pslverr;
endinterface
