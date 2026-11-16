// =====================================================================
//  FILE        : sv/timer_adc_sva.sv   (SIMULATION ONLY)
//  MODULE      : timer_adc_sva  + bind statement
// ---------------------------------------------------------------------
//  Assertions (rules checked on every clock) for the peripheral.
//  They are attached to timer_adc8_top with "bind", so the RTL files
//  are NOT edited. Every instance of timer_adc8_top in the simulation
//  gets its own copy (also the one inside the CPU system).
//
//  Rules
//    a_cnt_le_load    timer counter never goes above LOAD
//    a_pwm_off        PWM is low when the timer is disabled
//    a_period         time between two overflows = (PRESC+1)*(LOAD+1)
//    a_fifo_max       FIFO level is never above 8
//    a_fifo_flags     EMPTY / FULL agree with LEVEL
//    a_overflow_drop  push into a full FIFO (no pop) is dropped
//    a_pop_empty      pop from an empty FIFO changes nothing
//    a_eoc_pulse      EOC is exactly one clock long
//    a_eoc_idle       EOC only comes when the ADC goes back to idle
//    a_conv_time      start -> EOC takes (SMP+9)*(DIV+1) clocks
//    a_irq            irq == OR(IRQ_STAT & IRQ_EN)
//    a_id             reading ID always gives A8
//    a_start_rd0      ADC_CTRL.START always reads back as 0
// =====================================================================

`timescale 1ns/1ps

module timer_adc_sva (
    input logic       clk,
    input logic       rst_n,
    // timer
    input logic       tmr_en,
    input logic [7:0] tmr_presc,
    input logic [7:0] tmr_load,
    input logic [7:0] tmr_cnt,
    input logic       tmr_ovf,
    input logic       pwm_out,
    // ADC
    input logic       adc_en,
    input logic       adc_start,
    input logic       adc_busy,
    input logic       adc_eoc,
    input logic [7:0] adc_smp,
    input logic [7:0] adc_div,
    // FIFO
    input logic [3:0] fifo_level,
    input logic       fifo_empty,
    input logic       fifo_full,
    input logic       fifo_push,
    input logic       fifo_pop,
    // interrupts
    input logic [5:0] irq_stat,
    input logic [5:0] irq_en,
    input logic       irq,
    // bus
    input logic       psel,
    input logic       penable,
    input logic       pwrite,
    input logic [3:0] paddr,
    input logic [7:0] prdata
);

    wire rd_access = psel && penable && !pwrite;

    // ------------------------------------------------------------ timer
    a_cnt_le_load: assert property ( @(posedge clk) disable iff (!rst_n)
        (tmr_en && $past(tmr_en) && $stable(tmr_load) && ($past(tmr_cnt) <= tmr_load))
        |-> (tmr_cnt <= tmr_load))
        else $error("SVA a_cnt_le_load: cnt=%0d > load=%0d", tmr_cnt, tmr_load);

    a_pwm_off: assert property ( @(posedge clk) disable iff (!rst_n) !tmr_en |-> !pwm_out )
        else $error("SVA a_pwm_off: PWM high while timer disabled");

    // ------------------------------------------------------------ FIFO
    a_fifo_max: assert property ( @(posedge clk) disable iff (!rst_n) fifo_level <= 4'd8 )
        else $error("SVA a_fifo_max: level=%0d", fifo_level);

    a_fifo_flags: assert property ( @(posedge clk) disable iff (!rst_n)
        (fifo_empty == (fifo_level == 4'd0)) && (fifo_full == (fifo_level == 4'd8)) )
        else $error("SVA a_fifo_flags: level=%0d empty=%b full=%b", fifo_level, fifo_empty, fifo_full);

    a_overflow_drop: assert property ( @(posedge clk) disable iff (!rst_n) (fifo_full && fifo_push && !fifo_pop) |=> (fifo_level == 4'd8) )
        else $error("SVA a_overflow_drop");

    a_pop_empty: assert property ( @(posedge clk) disable iff (!rst_n) (fifo_empty && fifo_pop && !fifo_push) |=> fifo_empty )
        else $error("SVA a_pop_empty");

    // ------------------------------------------------------------ ADC
    a_eoc_pulse: assert property ( @(posedge clk) disable iff (!rst_n) adc_eoc |=> !adc_eoc )
        else $error("SVA a_eoc_pulse: EOC longer than 1 clock");

    a_eoc_idle: assert property ( @(posedge clk) disable iff (!rst_n) adc_eoc |-> !adc_busy )
        else $error("SVA a_eoc_idle");

    // ------------------------------------------------------------ IRQ / bus
    a_irq: assert property ( @(posedge clk) disable iff (!rst_n) irq == |(irq_stat & irq_en) )
        else $error("SVA a_irq: irq=%b stat=%h en=%h", irq, irq_stat, irq_en);

    a_id: assert property ( @(posedge clk) disable iff (!rst_n) (rd_access && paddr == 4'hF) |-> (prdata == 8'hA8) )
        else $error("SVA a_id: ID read %h", prdata);

    a_start_rd0: assert property ( @(posedge clk) disable iff (!rst_n) (rd_access && paddr == 4'h5) |-> (prdata[1] == 1'b0) )
        else $error("SVA a_start_rd0");

    // ------------------------------------------------------------
    // a_period : count clocks between two overflow pulses while the
    // timer settings do not change.
    // ------------------------------------------------------------
    int        pcount;
    bit        ptrack;
    logic [7:0] pp, pl;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcount <= 0; ptrack <= 0; pp <= 0; pl <= 0;
        end else if (!tmr_en || tmr_presc != pp || tmr_load != pl) begin
            pcount <= 0; ptrack <= 0; pp <= tmr_presc; pl <= tmr_load;
        end else begin
            pcount <= pcount + 1;
            if (tmr_ovf) begin
                if (ptrack) begin
                    a_period: assert (pcount + 1 == (int'(pp) + 1) * (int'(pl) + 1))
                        else $error("SVA a_period: %0d clocks, expected %0d",
                                    pcount + 1, (int'(pp) + 1) * (int'(pl) + 1));
                end
                ptrack <= 1;
                pcount <= 0;
            end
        end
    end

    // ------------------------------------------------------------
    // a_conv_time : from the clock edge where a start is accepted to
    // the EOC pulse = (SMP + 9) * (DIV + 1) clocks.
    // ------------------------------------------------------------
    int  k, exp_n;
    bit  active;
    wire start_acc = adc_en && adc_start && !adc_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k <= 0; exp_n <= 0; active <= 0;
        end else begin
            if (active && adc_eoc) begin
                a_conv_time: assert (k == exp_n + 1)
                    else $error("SVA a_conv_time: %0d clocks, expected %0d", k - 1, exp_n);
                active <= 0;
            end else if (active) begin
                k <= k + 1;
            end
            if (start_acc) begin
                active <= 1;
                k      <= 1;
                exp_n  <= (int'(adc_smp) + 9) * (int'(adc_div) + 1);
            end
            if (!adc_en) active <= 0;
        end
    end

endmodule

// =====================================================================
//  BIND: attach one timer_adc_sva to every timer_adc8_top.
//  The names on the right are wires inside timer_adc8_top.v.
// =====================================================================
bind timer_adc8_top timer_adc_sva u_sva (
    .clk        (clk),
    .rst_n      (rst_n),
    .tmr_en     (tmr_en),
    .tmr_presc  (tmr_presc),
    .tmr_load   (tmr_load),
    .tmr_cnt    (tmr_cnt),
    .tmr_ovf    (tmr_ovf),
    .pwm_out    (pwm_out),
    .adc_en     (adc_en),
    .adc_start  (adc_start),
    .adc_busy   (adc_busy),
    .adc_eoc    (adc_eoc),
    .adc_smp    (adc_smp),
    .adc_div    (adc_div),
    .fifo_level (fifo_level),
    .fifo_empty (fifo_empty),
    .fifo_full  (fifo_full),
    .fifo_push  (adc_eoc),
    .fifo_pop   (fifo_pop),
    .irq_stat   (irq_stat),
    .irq_en     (irq_en_w),
    .irq        (irq),
    .psel       (psel),
    .penable    (penable),
    .pwrite     (pwrite),
    .paddr      (paddr),
    .prdata     (prdata)
);
