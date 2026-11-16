// =====================================================================
//  FILE        : rtl/timer8.v
//  MODULE      : timer8
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    8-bit timer with a prescaler, a compare unit and a PWM output.
//
//      clk --> prescaler (divide by PRESC+1) --> tick
//      tick --> counter 0,1,2 ... LOAD, 0, 1 ...
//
//      ovf_pulse : 1-clock pulse when the counter wraps (cnt == LOAD)
//      cmp_pulse : 1-clock pulse when the counter leaves the value CMP
//      pwm       : 1 while cnt < CMP           (duty = CMP / (LOAD+1))
//
//    Formulas
//      period  = (PRESC + 1) * (LOAD + 1) clocks
//      compare = (CMP + 1) * (PRESC + 1) clocks after start
//
//    Modes
//      en = 0           : counter and prescaler held at 0, pwm low
//      oneshot = 0      : periodic, wraps forever
//      oneshot = 1      : stops after the first overflow and asks the
//                         register block to clear EN (oneshot_done)
//
//  WHO USES THIS FILE : rtl/timer_adc8_top.v  (instance u_timer)
//  THIS FILE CALLS    : nothing (leaf module)
// =====================================================================

`timescale 1ns/1ps

module timer8 (
    input  wire       clk,
    input  wire       rst_n,          // asynchronous reset, active low
    input  wire       en,             // TMR_CTRL.EN
    input  wire       oneshot,        // TMR_CTRL.ONESHOT
    input  wire [7:0] presc,          // TMR_PRESC
    input  wire [7:0] load,           // TMR_LOAD
    input  wire [7:0] cmp,            // TMR_CMP
    output reg  [7:0] cnt,            // TMR_CNT (read only)
    output reg        ovf_pulse,      // counter wrapped
    output reg        cmp_pulse,      // counter left the value CMP
    output reg        oneshot_done,   // one-shot finished -> clear EN
    output wire       pwm             // PWM output pin
);

    reg  [7:0] pcnt;       // prescaler counter
    reg        stopped;    // 1 = one-shot finished, wait until EN is cleared

    // Timer really runs only when enabled and not stopped by one-shot
    wire run  = en && !stopped;

    // One "slow tick" every PRESC+1 clocks.
    // (>= instead of == so that lowering PRESC while running is safe)
    wire tick = run && (pcnt >= presc);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcnt         <= 8'd0;
            cnt          <= 8'd0;
            stopped      <= 1'b0;
            ovf_pulse    <= 1'b0;
            cmp_pulse    <= 1'b0;
            oneshot_done <= 1'b0;
        end else begin
            // pulses are 1 clock long by default
            ovf_pulse    <= 1'b0;
            cmp_pulse    <= 1'b0;
            oneshot_done <= 1'b0;

            if (!en) begin
                // ---- OFF: everything back to 0 ----
                pcnt    <= 8'd0;
                cnt     <= 8'd0;
                stopped <= 1'b0;
            end else if (run) begin
                if (tick) begin
                    pcnt <= 8'd0;

                    // compare event: the counter is leaving CMP
                    if (cnt == cmp)
                        cmp_pulse <= 1'b1;

                    // overflow: wrap to 0
                    if (cnt >= load) begin
                        cnt       <= 8'd0;
                        ovf_pulse <= 1'b1;
                        if (oneshot) begin
                            stopped      <= 1'b1;   // stop right now
                            oneshot_done <= 1'b1;   // tell apb_regs8 to clear EN
                        end
                    end else begin
                        cnt <= cnt + 8'd1;
                    end
                end else begin
                    pcnt <= pcnt + 8'd1;
                end
            end
        end
    end

    // PWM: high while the counter is below CMP
    assign pwm = run && (cnt < cmp);

endmodule
