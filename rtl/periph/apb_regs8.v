// =====================================================================
//  FILE        : rtl/apb_regs8.v
//  MODULE      : apb_regs8
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    The 16 registers, the read multiplexer and the interrupt logic.
//    Bus = 8-bit APB: a transfer happens in the cycle where
//    psel = 1 AND penable = 1 (no wait states, pready = 1).
//
//    Addr Name        Type  Reset  Bits
//    0x0  TMR_CTRL    RW    00     [0] EN  [1] ONESHOT
//    0x1  TMR_PRESC   RW    00     tick every PRESC+1 clocks
//    0x2  TMR_LOAD    RW    FF     counter wraps at LOAD
//    0x3  TMR_CMP     RW    80     compare value / PWM duty
//    0x4  TMR_CNT     RO    00     current count
//    0x5  ADC_CTRL    RW    00     [0] EN [1] START(reads 0) [3:2] TRIG_SEL [5:4] CH
//    0x6  ADC_SMP     RW    04     sample window - 1 (ticks)
//    0x7  ADC_DIV     RW    00     ADC tick = DIV+1 clocks
//    0x8  ADC_THR_LO  RW    00     window low limit
//    0x9  ADC_THR_HI  RW    FF     window high limit
//    0xA  ADC_DATA    RO    --     oldest result, a READ POPS the FIFO
//    0xB  ADC_RCH     RO    00     [7] VALID [1:0] CH of oldest result (no pop)
//    0xC  ADC_STAT    RO    10     [3:0] LEVEL [4] EMPTY [5] FULL [6] BUSY
//    0xD  IRQ_EN      RW    00     interrupt enables (6 bits)
//    0xE  IRQ_STAT    W1C   00     [0] TMR_OVF [1] TMR_CMP [2] ADC_EOC
//                                  [3] ADC_WD  [4] FIFO_OVR [5] TRIG_MISS
//    0xF  ID          RO    A8
//
//    IRQ_STAT flags are sticky: an event sets the bit, writing 1 clears
//    it. If an event and a clear happen in the same clock, the event
//    wins (no event is ever lost).  irq = OR(IRQ_STAT & IRQ_EN)
//
//  WHO USES THIS FILE : rtl/timer_adc8_top.v  (instance u_regs)
//  THIS FILE CALLS    : nothing (leaf module)
// =====================================================================

`timescale 1ns/1ps

module apb_regs8 (
    input  wire       clk,
    input  wire       rst_n,
    // ---- APB slave port ----
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [3:0] paddr,
    input  wire [7:0] pwdata,
    output reg  [7:0] prdata,
    output wire       pready,
    output wire       pslverr,
    // ---- timer ----
    output wire       tmr_en,
    output wire       tmr_oneshot,
    output wire [7:0] tmr_presc,
    output wire [7:0] tmr_load,
    output wire [7:0] tmr_cmp,
    input  wire [7:0] tmr_cnt,
    input  wire       tmr_oneshot_done,
    input  wire       ev_tmr_ovf,
    input  wire       ev_tmr_cmp,
    // ---- ADC configuration ----
    output wire       adc_en,
    output reg        adc_sw_start,     // 1-clock pulse after START is written
    output wire [1:0] adc_trig_sel,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_smp,
    output wire [7:0] adc_div,
    input  wire       adc_busy,
    input  wire       ev_adc_eoc,
    input  wire [7:0] adc_result,
    // ---- FIFO ----
    input  wire [9:0] fifo_rdata,       // {ch, data} of the oldest entry
    input  wire [3:0] fifo_level,
    input  wire       fifo_empty,
    input  wire       fifo_full,
    output wire       fifo_pop,
    input  wire       ev_fifo_ovr,
    input  wire       ev_trig_miss,
    // ---- interrupts ----
    output wire       irq,
    output wire [5:0] irq_stat_o,
    output wire [5:0] irq_en_o
);

    // ---------------- register addresses ----------------
    localparam A_TMR_CTRL  = 4'h0, A_TMR_PRESC = 4'h1, A_TMR_LOAD  = 4'h2,
               A_TMR_CMP   = 4'h3, A_TMR_CNT   = 4'h4, A_ADC_CTRL  = 4'h5,
               A_ADC_SMP   = 4'h6, A_ADC_DIV   = 4'h7, A_THR_LO    = 4'h8,
               A_THR_HI    = 4'h9, A_ADC_DATA  = 4'hA, A_ADC_RCH   = 4'hB,
               A_ADC_STAT  = 4'hC, A_IRQ_EN    = 4'hD, A_IRQ_STAT  = 4'hE,
               A_ID        = 4'hF;

    // ---------------- bus decode ----------------
    wire access = psel && penable;          // the one cycle that counts
    wire wr     = access &&  pwrite;
    wire rd     = access && !pwrite;

    assign pready  = 1'b1;                  // never wait
    assign pslverr = 1'b0;                  // never error

    // ---------------- storage ----------------
    reg [1:0] r_tmr_ctrl;
    reg [7:0] r_presc, r_load, r_cmp;
    reg       r_adc_en;
    reg [1:0] r_trig, r_ch;
    reg [7:0] r_smp, r_div, r_thr_lo, r_thr_hi;
    reg [5:0] r_irq_en, r_irq_stat;

    // ---------------- events -> IRQ_STAT ----------------
    // window check: every new result outside [THR_LO, THR_HI]
    wire ev_wd = ev_adc_eoc && ((adc_result < r_thr_lo) || (adc_result > r_thr_hi));

    wire [5:0] events = {ev_trig_miss, ev_fifo_ovr, ev_wd,
                         ev_adc_eoc, ev_tmr_cmp, ev_tmr_ovf};

    wire [5:0] w1c = (wr && paddr == A_IRQ_STAT) ? pwdata[5:0] : 6'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_tmr_ctrl   <= 2'b00;
            r_presc      <= 8'h00;
            r_load       <= 8'hFF;
            r_cmp        <= 8'h80;
            r_adc_en     <= 1'b0;
            r_trig       <= 2'd0;
            r_ch         <= 2'd0;
            r_smp        <= 8'h04;
            r_div        <= 8'h00;
            r_thr_lo     <= 8'h00;
            r_thr_hi     <= 8'hFF;
            r_irq_en     <= 6'h00;
            r_irq_stat   <= 6'h00;
            adc_sw_start <= 1'b0;
        end else begin
            // START is registered so the ADC sees EN already updated
            adc_sw_start <= wr && (paddr == A_ADC_CTRL) && pwdata[1];

            // one-shot finished: hardware clears TMR_CTRL.EN
            if (tmr_oneshot_done)
                r_tmr_ctrl[0] <= 1'b0;

            // CPU writes (a CPU write in the same clock wins over the clear)
            if (wr) begin
                case (paddr)
                    A_TMR_CTRL : r_tmr_ctrl <= pwdata[1:0];
                    A_TMR_PRESC: r_presc    <= pwdata;
                    A_TMR_LOAD : r_load     <= pwdata;
                    A_TMR_CMP  : r_cmp      <= pwdata;
                    A_ADC_CTRL : begin
                                     r_adc_en <= pwdata[0];
                                     r_trig   <= pwdata[3:2];
                                     r_ch     <= pwdata[5:4];
                                 end
                    A_ADC_SMP  : r_smp      <= pwdata;
                    A_ADC_DIV  : r_div      <= pwdata;
                    A_THR_LO   : r_thr_lo   <= pwdata;
                    A_THR_HI   : r_thr_hi   <= pwdata;
                    A_IRQ_EN   : r_irq_en   <= pwdata[5:0];
                    default    : ;                    // RO / W1C: nothing
                endcase
            end

            // sticky flags: clear with W1C, but a new event always wins
            r_irq_stat <= (r_irq_stat & ~w1c) | events;
        end
    end

    // ---------------- read multiplexer (combinational) ----------------
    always @(*) begin
        case (paddr)
            A_TMR_CTRL : prdata = {6'b0, r_tmr_ctrl};
            A_TMR_PRESC: prdata = r_presc;
            A_TMR_LOAD : prdata = r_load;
            A_TMR_CMP  : prdata = r_cmp;
            A_TMR_CNT  : prdata = tmr_cnt;
            A_ADC_CTRL : prdata = {2'b0, r_ch, r_trig, 1'b0, r_adc_en};
            A_ADC_SMP  : prdata = r_smp;
            A_ADC_DIV  : prdata = r_div;
            A_THR_LO   : prdata = r_thr_lo;
            A_THR_HI   : prdata = r_thr_hi;
            A_ADC_DATA : prdata = fifo_empty ? 8'h00 : fifo_rdata[7:0];
            A_ADC_RCH  : prdata = fifo_empty ? 8'h00 : {1'b1, 5'b0, fifo_rdata[9:8]};
            A_ADC_STAT : prdata = {1'b0, adc_busy, fifo_full, fifo_empty, fifo_level};
            A_IRQ_EN   : prdata = {2'b0, r_irq_en};
            A_IRQ_STAT : prdata = {2'b0, r_irq_stat};
            A_ID       : prdata = 8'hA8;
            default    : prdata = 8'h00;
        endcase
    end

    // reading ADC_DATA removes the oldest result
    assign fifo_pop = rd && (paddr == A_ADC_DATA);

    // ---------------- outputs ----------------
    assign tmr_en       = r_tmr_ctrl[0];
    assign tmr_oneshot  = r_tmr_ctrl[1];
    assign tmr_presc    = r_presc;
    assign tmr_load     = r_load;
    assign tmr_cmp      = r_cmp;
    assign adc_en       = r_adc_en;
    assign adc_trig_sel = r_trig;
    assign adc_ch       = r_ch;
    assign adc_smp      = r_smp;
    assign adc_div      = r_div;
    assign irq_stat_o   = r_irq_stat;
    assign irq_en_o     = r_irq_en;
    assign irq          = |(r_irq_stat & r_irq_en);

endmodule
