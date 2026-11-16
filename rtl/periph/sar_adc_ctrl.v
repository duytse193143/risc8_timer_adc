// =====================================================================
//  FILE        : rtl/sar_adc_ctrl.v
//  MODULE      : sar_adc_ctrl
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    State machine of an 8-bit SAR (Successive Approximation Register)
//    ADC. The analog parts (MUX, sample & hold, DAC, comparator) live
//    OUTSIDE this file (in simulation: sv/afe_model.v).
//
//      IDLE --start--> SAMPLE (SMP+1 ticks) --> CONVERT (8 ticks) --> IDLE
//                                                      (eoc = 1, result saved)
//
//    One "tick" = DIV+1 clocks.
//    conversion time = (SMP + 1 + 8) * (DIV + 1) clocks
//
//    SAR "guessing game" (MSB first):
//      trial = 1000_0000 -> comparator says Vin >= Vdac ?  yes: keep bit
//                                                          no : clear bit
//      then try the next lower bit ... 8 guesses give 8 bits.
//
//    Clearing en at any time aborts the conversion (no result).
//
//  WHO USES THIS FILE : rtl/timer_adc8_top.v  (instance u_adc)
//  THIS FILE CALLS    : nothing (leaf module)
// =====================================================================

`timescale 1ns/1ps

module sar_adc_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,          // ADC_CTRL.EN
    input  wire       start,       // start request (software / timer / continuous)
    input  wire [1:0] ch,          // ADC_CTRL.CH (channel to measure)
    input  wire [7:0] smp,         // ADC_SMP : sample window - 1 (ticks)
    input  wire [7:0] div,         // ADC_DIV : tick = DIV+1 clocks
    input  wire       cmp,         // comparator from the analog front end
    // ---- to the analog front end ----
    output wire       sample,      // 1 = sample & hold is tracking the input
    output wire [7:0] dac,         // current guess for the DAC
    output wire [1:0] adc_ch,      // channel select for the analog MUX
    // ---- status / result ----
    output wire       busy,        // 1 = conversion in progress
    output reg        eoc,         // End Of Conversion: 1-clock pulse
    output reg  [7:0] result,      // last conversion result
    output reg  [1:0] res_ch       // channel of the last result
);

    localparam S_IDLE   = 2'd0,
               S_SAMPLE = 2'd1,
               S_CONV   = 2'd2;

    reg [1:0] state;
    reg [7:0] dcnt;      // clock divider counter (0 .. DIV)
    reg [7:0] scnt;      // sample tick counter   (0 .. SMP)
    reg [7:0] smp_l;     // SMP latched at start
    reg [7:0] div_l;     // DIV latched at start
    reg [1:0] ch_l;      // channel latched at start
    reg [7:0] trial;     // SAR register = DAC value
    reg [2:0] bitn;      // bit being decided (7 .. 0)

    wire       atick   = (dcnt == div_l);          // end of one tick
    wire [7:0] bitmask = 8'h01 << bitn;            // bit under test
    // decision for the current bit: keep it if Vin >= Vdac
    wire [7:0] decided = cmp ? trial : (trial & ~bitmask);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            dcnt   <= 8'd0;
            scnt   <= 8'd0;
            smp_l  <= 8'd0;
            div_l  <= 8'd0;
            ch_l   <= 2'd0;
            trial  <= 8'd0;
            bitn   <= 3'd7;
            eoc    <= 1'b0;
            result <= 8'd0;
            res_ch <= 2'd0;
        end else begin
            eoc <= 1'b0;                       // pulse by default

            if (!en) begin
                // ---- disabled: abort, back to IDLE, no result ----
                state <= S_IDLE;
                dcnt  <= 8'd0;
                scnt  <= 8'd0;
                trial <= 8'd0;
            end else begin
                case (state)
                    // ---------------------------------------------------
                    S_IDLE: if (start) begin
                        state <= S_SAMPLE;
                        dcnt  <= 8'd0;
                        scnt  <= 8'd0;
                        smp_l <= smp;          // settings are frozen for
                        div_l <= div;          // the whole conversion
                        ch_l  <= ch;
                        trial <= 8'd0;
                    end
                    // ---------------------------------------------------
                    S_SAMPLE: if (atick) begin
                        dcnt <= 8'd0;
                        if (scnt == smp_l) begin
                            state <= S_CONV;   // sampling done: hold
                            trial <= 8'h80;    // first guess = half scale
                            bitn  <= 3'd7;
                        end else begin
                            scnt <= scnt + 8'd1;
                        end
                    end else begin
                        dcnt <= dcnt + 8'd1;
                    end
                    // ---------------------------------------------------
                    S_CONV: if (atick) begin
                        dcnt <= 8'd0;
                        if (bitn == 3'd0) begin
                            // last bit decided: conversion finished
                            result <= decided;
                            res_ch <= ch_l;
                            eoc    <= 1'b1;
                            state  <= S_IDLE;
                            trial  <= 8'd0;
                        end else begin
                            // keep/clear this bit, then try the next one
                            trial <= decided | (bitmask >> 1);
                            bitn  <= bitn - 3'd1;
                        end
                    end else begin
                        dcnt <= dcnt + 8'd1;
                    end
                    // ---------------------------------------------------
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

    assign busy   = (state != S_IDLE);
    assign sample = (state == S_SAMPLE);
    assign dac    = trial;
    assign adc_ch = busy ? ch_l : ch;

endmodule
