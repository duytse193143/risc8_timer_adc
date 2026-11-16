// =====================================================================
//  FILE        : rtl/risc8_soc.v
//  MODULE      : risc8_soc   (SYSTEM TOP: CPU + Timer/ADC peripheral)
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Places the CPU and the peripheral side by side and connects them:
//
//      risc8_5stage_core (IO_ENABLE=1, IO_PAGE=F)      timer_adc8_cpu_if
//          io_cs    ------------------------------>  cs
//          io_we    ------------------------------>  we
//          io_addr  ------------------------------>  addr[3:0]
//          io_wdata ------------------------------>  wdata[7:0]
//          io_rdata <------------------------------  rdata[7:0]
//
//      clk is shared.
//      The CPU reset is active HIGH (rst), the peripheral reset is
//      active LOW (rst_n)  ->  rst_n = ~rst.
//
//    Data address map seen by the CPU
//      0x00 - 0xEF : data RAM (dmem)
//      0xF0 - 0xFF : the 16 peripheral registers
//
//  MODULES CALLED
//    risc8_5stage_core  (rtl/risc8_5stage_core.v)        -> u_cpu
//    timer_adc8_cpu_if  (rtl/periph/timer_adc8_cpu_if.v) -> u_tadc
//
//  WHO USES THIS FILE : tb/tb_risc8_soc.v
// =====================================================================

`timescale 1ns/1ps

module risc8_soc #(
    parameter IMEM_FILE = "soc_demo.hex"
) (
    input  wire       clk,
    input  wire       rst,          // active high (same as the CPU)
    // ---- debug ----
    output wire       halted,
    output wire [7:0] pc_out,
    // ---- peripheral pins ----
    output wire       irq,
    output wire       pwm_out,
    // ---- analog front end ----
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp
);

    // ---- the five bus wires between CPU and peripheral ----
    wire       io_cs, io_we;
    wire [3:0] io_addr;
    wire [7:0] io_wdata, io_rdata;

    wire [1:0] flags_unused;
    wire       done_unused;

    // ---- CALL: module risc8_5stage_core from rtl/risc8_5stage_core.v ----
    risc8_5stage_core #(
        .IMEM_FILE (IMEM_FILE),
        .IO_ENABLE (1),
        .IO_PAGE   (4'hF)
    ) u_cpu (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc_out),
        .flags_out  (flags_unused),
        .instr_done (done_unused),
        .io_cs      (io_cs),
        .io_we      (io_we),
        .io_addr    (io_addr),
        .io_wdata   (io_wdata),
        .io_rdata   (io_rdata)
    );

    // ---- CALL: module timer_adc8_cpu_if from rtl/periph/timer_adc8_cpu_if.v ----
    timer_adc8_cpu_if u_tadc (
        .clk        (clk),
        .rst_n      (~rst),          // polarity conversion: active high -> active low
        .cs         (io_cs),
        .we         (io_we),
        .addr       (io_addr),
        .wdata      (io_wdata),
        .rdata      (io_rdata),
        .irq        (irq),
        .pwm_out    (pwm_out),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

endmodule
