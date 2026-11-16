// =====================================================================
//  FILE        : sv/adc_if.sv        (SIMULATION ONLY)
//  INTERFACE   : adc_if
// ---------------------------------------------------------------------
//  Bundle of the "analog side" wires:
//    vin_mv[0..3]  input voltages in mV, driven by the UVM adc_driver
//    sample/ch/dac DUT -> analog model
//    cmp           analog model -> DUT
//    eoc/result/res_ch   internal DUT signals, copied in tb_top.sv so
//                        the adc_monitor can see each finished result
//    irq / pwm     DUT output pins (checked by the sequences)
//
//  NOTE: `include-d at the top of tb/uvm/timer_adc_pkg.sv,
//        do NOT add it to the Vivado project separately.
// =====================================================================

`timescale 1ns/1ps

interface adc_if (input logic clk, input logic rst_n);
    logic [3:0][11:0] vin_mv;     // 4 channels, millivolts
    logic             sample;
    logic [1:0]       ch;
    logic [7:0]       dac;
    logic             cmp;
    logic             eoc;
    logic [7:0]       result;
    logic [1:0]       res_ch;
    logic             irq;
    logic             pwm;
endinterface
