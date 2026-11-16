// =====================================================================
//  FILE        : tb/uvm/tb_top.sv
//  MODULE      : tb_top   (top of the UVM simulation)
// ---------------------------------------------------------------------
//  1. makes the clock (100 MHz) and the reset
//  2. places the DUT (timer_adc8_top), the two interfaces and the
//     analog front-end model (afe_model)
//  3. stores the interface handles in uvm_config_db
//  4. calls run_test()  -> UVM creates the test named by +UVM_TESTNAME
//
//  The assertions (sv/timer_adc_sva.sv) are attached to the DUT by a
//  "bind" statement, so nothing about them appears here.
// =====================================================================

`timescale 1ns/1ps

module tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import timer_adc_pkg::*;

    // ---------------- clock and reset ----------------
    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    always #5 clk = ~clk;                       // 10 ns period

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    // ---------------- interfaces ----------------
    apb_if apb (.clk(clk), .rst_n(rst_n));
    adc_if adc (.clk(clk), .rst_n(rst_n));

    // ---------------- DUT: timer_adc8_top (rtl/timer_adc8_top.v) -------
    timer_adc8_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .psel       (apb.psel),
        .penable    (apb.penable),
        .pwrite     (apb.pwrite),
        .paddr      (apb.paddr),
        .pwdata     (apb.pwdata),
        .prdata     (apb.prdata),
        .pready     (apb.pready),
        .pslverr    (apb.pslverr),
        .irq        (adc.irq),
        .pwm_out    (adc.pwm),
        .adc_sample (adc.sample),
        .adc_ch     (adc.ch),
        .adc_dac    (adc.dac),
        .adc_cmp    (adc.cmp)
    );

    // ---------------- analog front end (sv/afe_model.v) ----------------
    afe_model u_afe (
        .clk     (clk),
        .sample  (adc.sample),
        .ch      (adc.ch),
        .dac     (adc.dac),
        .vin0_mv (adc.vin_mv[0]),
        .vin1_mv (adc.vin_mv[1]),
        .vin2_mv (adc.vin_mv[2]),
        .vin3_mv (adc.vin_mv[3]),
        .cmp     (adc.cmp)
    );

    // internal DUT signals the adc_monitor needs to see each result
    assign adc.eoc    = dut.adc_eoc;
    assign adc.result = dut.adc_result;
    assign adc.res_ch = dut.adc_res_ch;

    // ---------------- start UVM ----------------
    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb);
        uvm_config_db#(virtual adc_if)::set(null, "*", "adc_vif", adc);
        run_test("tadc_all_test");     // +UVM_TESTNAME overrides this
    end

    // safety net: stop if a test hangs (20 ms of simulated time)
    initial begin
        #20_000_000;
        $display("*** TIMEOUT: test did not finish ***");
        $finish;
    end

    // optional waveform file:  -testplusarg DUMP
    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_top.vcd");
            $dumpvars(0, tb_top);
        end
    end

endmodule
