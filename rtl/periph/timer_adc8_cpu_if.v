// =====================================================================
//  FILE        : rtl/timer_adc8_cpu_if.v
//  MODULE      : timer_adc8_cpu_if
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Wrapper that makes the APB port look like a simple one-cycle CPU
//    bus:   cs, we, addr[3:0], wdata[7:0]  ->  rdata[7:0] (same clock)
//
//    cs drives BOTH psel and penable, so every clock with cs = 1 is one
//    complete APB access. One LD = one read = (for ADC_DATA) one pop.
//    rdata is 0 when cs = 0, so it can be OR-ed into a CPU read mux.
//
//  MODULES CALLED : timer_adc8_top (rtl/timer_adc8_top.v) -> u_periph
//  WHO USES IT    : risc8_soc.v (CPU system top)
// =====================================================================

`timescale 1ns/1ps

module timer_adc8_cpu_if (
    input  wire       clk,
    input  wire       rst_n,
    // ---- simple CPU bus ----
    input  wire       cs,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata,
    // ---- pins ----
    output wire       irq,
    output wire       pwm_out,
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp
);

    wire [7:0] prdata;
    wire       pready, pslverr;   // always 1 / 0, not needed by the CPU

    // ---- CALL: timer_adc8_top from rtl/timer_adc8_top.v ----
    timer_adc8_top u_periph (
        .clk        (clk),
        .rst_n      (rst_n),
        .psel       (cs),
        .penable    (cs),
        .pwrite     (we),
        .paddr      (addr),
        .pwdata     (wdata),
        .prdata     (prdata),
        .pready     (pready),
        .pslverr    (pslverr),
        .irq        (irq),
        .pwm_out    (pwm_out),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

    assign rdata = cs ? prdata : 8'h00;

endmodule
