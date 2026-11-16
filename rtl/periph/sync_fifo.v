// =====================================================================
//  FILE        : rtl/sync_fifo.v
//  MODULE      : sync_fifo
//  PROJECT     : Project 3 - RISC-8 CPU + 8-bit Timer / 8-bit ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Small First-In-First-Out queue (8 entries) for ADC results.
//    Each entry = {channel[1:0], data[7:0]} = 10 bits.
//
//    push  : write wdata at the tail. If the FIFO is full the new data
//            is DROPPED (unless a pop happens in the same clock).
//    pop   : remove the oldest entry (ignored when empty).
//    rdata : the oldest entry (visible without popping).
//
//  WHO USES THIS FILE : rtl/timer_adc8_top.v  (instance u_fifo)
//  THIS FILE CALLS    : nothing (leaf module)
// =====================================================================

`timescale 1ns/1ps

module sync_fifo #(
    parameter W     = 10,      // data width
    parameter DEPTH = 8,       // number of entries (power of 2)
    parameter AW    = 3        // log2(DEPTH)
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          push,
    input  wire [W-1:0]  wdata,
    input  wire          pop,
    output wire [W-1:0]  rdata,
    output reg  [AW:0]   level,    // 0 .. DEPTH
    output wire          empty,
    output wire          full
);

    reg [W-1:0]  mem [0:DEPTH-1];
    reg [AW-1:0] wp;               // write pointer (wraps naturally)
    reg [AW-1:0] rp;               // read pointer

    wire do_pop  = pop  && !empty;
    wire do_push = push && (!full || do_pop);

    // storage (no reset needed)
    always @(posedge clk)
        if (do_push) mem[wp] <= wdata;

    // pointers and level
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp    <= {AW{1'b0}};
            rp    <= {AW{1'b0}};
            level <= {(AW+1){1'b0}};
        end else begin
            if (do_push) wp <= wp + 1'b1;
            if (do_pop)  rp <= rp + 1'b1;
            case ({do_push, do_pop})
                2'b10:   level <= level + 1'b1;
                2'b01:   level <= level - 1'b1;
                default: level <= level;        // none, or push+pop
            endcase
        end
    end

    assign rdata = mem[rp];
    assign empty = (level == 0);
    assign full  = (level == DEPTH);

endmodule
