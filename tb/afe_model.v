// =====================================================================
//  FILE        : tb/afe_model.v      (SIMULATION ONLY - not hardware)
//  MODULE      : afe_model
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Pretends to be the analog front end of the SAR ADC:
//
//      vin0..3 --> MUX(ch) --> sample & hold --> (+) comparator --> cmp
//                                     dac[7:0] --> DAC  --> (-)
//
//    Voltages are given in MILLIVOLTS (integers), reference = 3300 mV.
//    The comparator says "held input >= DAC voltage":
//        Vhold >= dac * 3300/256   <=>   vhold_mv * 256 >= dac * 3300
//    Integer math only, so it works in plain Verilog-2001 and the
//    expected ADC code is exactly floor(mv * 256 / 3300), max 255.
//
//      1 LSB = 3300 mV / 256 = 12.9 mV
//      Example: 1111 mV -> 86 (0x56), 2000 mV -> 155 (0x9B)
//
//  WHO USES THIS FILE
//    tb/uvm/tb_top.sv (UVM)  and  tb/tb_risc8_soc.v
// =====================================================================

`timescale 1ns/1ps

module afe_model (
    input  wire        clk,
    input  wire        sample,     // 1 = track the input, 0 = hold
    input  wire [1:0]  ch,         // analog MUX select
    input  wire [7:0]  dac,        // DAC code from the SAR controller
    input  wire [11:0] vin0_mv,    // input voltages in mV (0..4095)
    input  wire [11:0] vin1_mv,
    input  wire [11:0] vin2_mv,
    input  wire [11:0] vin3_mv,
    output wire        cmp         // comparator output
);

    // ---- analog MUX ----
    wire [11:0] vsel = (ch == 2'd0) ? vin0_mv :
                       (ch == 2'd1) ? vin1_mv :
                       (ch == 2'd2) ? vin2_mv : vin3_mv;

    // ---- sample & hold: follows the input while sample = 1 ----
    reg [11:0] vhold_mv;
    initial vhold_mv = 12'd0;
    always @(posedge clk)
        if (sample) vhold_mv <= vsel;

    // ---- comparator (integer form of Vhold >= Vdac) ----
    wire [21:0] lhs = vhold_mv * 22'd256;
    wire [21:0] rhs = dac      * 22'd3300;
    assign cmp = (lhs >= rhs);

endmodule
