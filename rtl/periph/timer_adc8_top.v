// =====================================================================
//  FILE        : rtl/timer_adc8_top.v
//  MODULE      : timer_adc8_top
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Wires the four blocks together and selects what starts the ADC:
//
//      TRIG_SEL = 0 : software only (ADC_CTRL.START)
//      TRIG_SEL = 1 : timer overflow
//      TRIG_SEL = 2 : timer compare
//      TRIG_SEL = 3 : continuous (start again as soon as idle)
//
//    A trigger that arrives while the ADC is busy is lost and sets the
//    TRIG_MISS flag. A result that arrives while the FIFO is full is
//    dropped and sets the FIFO_OVR flag.
//
//  MODULES CALLED
//    apb_regs8    (rtl/apb_regs8.v)    -> u_regs
//    timer8       (rtl/timer8.v)       -> u_timer
//    sar_adc_ctrl (rtl/sar_adc_ctrl.v) -> u_adc
//    sync_fifo    (rtl/sync_fifo.v)    -> u_fifo
//
//  WHO USES THIS FILE
//    rtl/timer_adc8_cpu_if.v (CPU wrapper), tb/uvm/tb_top.sv (UVM DUT)
// =====================================================================

`timescale 1ns/1ps

module timer_adc8_top (
    input  wire       clk,
    input  wire       rst_n,
    // ---- APB slave ----
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [3:0] paddr,
    input  wire [7:0] pwdata,
    output wire [7:0] prdata,
    output wire       pready,
    output wire       pslverr,
    // ---- interrupt + PWM ----
    output wire       irq,
    output wire       pwm_out,
    // ---- analog front end ----
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp
);

    // ---------------- internal wires (names also used by the SVA bind) ----
    wire       tmr_en, tmr_oneshot, tmr_oneshot_done;
    wire [7:0] tmr_presc, tmr_load, tmr_cmp, tmr_cnt;
    wire       tmr_ovf, tmr_cmp_ev;

    wire       adc_en, adc_sw_start, adc_busy, adc_eoc;
    wire [1:0] adc_trig_sel, adc_cfg_ch, adc_res_ch;
    wire [7:0] adc_smp, adc_div, adc_result;

    wire [9:0] fifo_rdata;
    wire [3:0] fifo_level;
    wire       fifo_empty, fifo_full, fifo_pop;

    wire [5:0] irq_stat, irq_en_w;

    // ---------------- trigger selection ----------------
    wire trig_ev  = (adc_trig_sel == 2'd1) ? tmr_ovf    :
                    (adc_trig_sel == 2'd2) ? tmr_cmp_ev : 1'b0;
    wire cont_req = (adc_trig_sel == 2'd3) && !adc_busy;

    // start request to the ADC (accepted only when idle and enabled)
    wire adc_start = adc_en && (adc_sw_start || trig_ev || cont_req);

    // a trigger while busy is lost
    wire trig_miss = adc_en && adc_busy && (adc_sw_start || trig_ev);

    // a result while the FIFO is full (and no pop) is dropped
    wire fifo_ovr  = adc_eoc && fifo_full && !fifo_pop;

    // ---------------- CALL: apb_regs8 (rtl/apb_regs8.v) ----------------
    apb_regs8 u_regs (
        .clk              (clk),
        .rst_n            (rst_n),
        .psel             (psel),
        .penable          (penable),
        .pwrite           (pwrite),
        .paddr            (paddr),
        .pwdata           (pwdata),
        .prdata           (prdata),
        .pready           (pready),
        .pslverr          (pslverr),
        .tmr_en           (tmr_en),
        .tmr_oneshot      (tmr_oneshot),
        .tmr_presc        (tmr_presc),
        .tmr_load         (tmr_load),
        .tmr_cmp          (tmr_cmp),
        .tmr_cnt          (tmr_cnt),
        .tmr_oneshot_done (tmr_oneshot_done),
        .ev_tmr_ovf       (tmr_ovf),
        .ev_tmr_cmp       (tmr_cmp_ev),
        .adc_en           (adc_en),
        .adc_sw_start     (adc_sw_start),
        .adc_trig_sel     (adc_trig_sel),
        .adc_ch           (adc_cfg_ch),
        .adc_smp          (adc_smp),
        .adc_div          (adc_div),
        .adc_busy         (adc_busy),
        .ev_adc_eoc       (adc_eoc),
        .adc_result       (adc_result),
        .fifo_rdata       (fifo_rdata),
        .fifo_level       (fifo_level),
        .fifo_empty       (fifo_empty),
        .fifo_full        (fifo_full),
        .fifo_pop         (fifo_pop),
        .ev_fifo_ovr      (fifo_ovr),
        .ev_trig_miss     (trig_miss),
        .irq              (irq),
        .irq_stat_o       (irq_stat),
        .irq_en_o         (irq_en_w)
    );

    // ---------------- CALL: timer8 (rtl/timer8.v) ----------------
    timer8 u_timer (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (tmr_en),
        .oneshot      (tmr_oneshot),
        .presc        (tmr_presc),
        .load         (tmr_load),
        .cmp          (tmr_cmp),
        .cnt          (tmr_cnt),
        .ovf_pulse    (tmr_ovf),
        .cmp_pulse    (tmr_cmp_ev),
        .oneshot_done (tmr_oneshot_done),
        .pwm          (pwm_out)
    );

    // ---------------- CALL: sar_adc_ctrl (rtl/sar_adc_ctrl.v) ----------------
    sar_adc_ctrl u_adc (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (adc_en),
        .start  (adc_start),
        .ch     (adc_cfg_ch),
        .smp    (adc_smp),
        .div    (adc_div),
        .cmp    (adc_cmp),
        .sample (adc_sample),
        .dac    (adc_dac),
        .adc_ch (adc_ch),
        .busy   (adc_busy),
        .eoc    (adc_eoc),
        .result (adc_result),
        .res_ch (adc_res_ch)
    );

    // ---------------- CALL: sync_fifo (rtl/sync_fifo.v) ----------------
    sync_fifo #(.W(10), .DEPTH(8), .AW(3)) u_fifo (
        .clk   (clk),
        .rst_n (rst_n),
        .push  (adc_eoc),
        .wdata ({adc_res_ch, adc_result}),
        .pop   (fifo_pop),
        .rdata (fifo_rdata),
        .level (fifo_level),
        .empty (fifo_empty),
        .full  (fifo_full)
    );

endmodule
