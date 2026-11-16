// =====================================================================
//  FILE        : tb/tb_risc8_soc.v
//  MODULE      : tb_risc8_soc   (SYSTEM TESTBENCH - simulation only)
//  PROJECT     : Project 3 - RISC-8 CPU + Timer/ADC
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    1. Builds the system: risc8_soc (CPU + peripheral) + afe_model
//       (the pretend analog inputs: 0.400 / 1.111 / 2.000 / 3.000 V)
//    2. Runs the firmware soc_demo.hex until HLT
//    3. Checks the results the firmware wrote to RAM 0x80..0x91 (18),
//       that the irq pin went high in Part D and low again, that RAM
//       0xF0..0xFF was never written, that exactly 8 conversions ran,
//       and that PWM is high 30 of every 100 clocks (Part E).
//
//  MODULES CALLED
//    risc8_soc  (rtl/risc8_soc.v)  -> dut
//    afe_model  (tb/afe_model.v)   -> u_afe
// =====================================================================

`timescale 1ns/1ps

module tb_risc8_soc;

    reg clk = 0;
    reg rst = 1;

    wire       halted, irq, pwm, adc_sample, adc_cmp;
    wire [7:0] pc, adc_dac;
    wire [1:0] adc_ch;

    // ---- CALL: module risc8_soc from rtl/risc8_soc.v ----
    risc8_soc #(.IMEM_FILE("soc_demo.hex")) dut (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc),
        .irq        (irq),
        .pwm_out    (pwm),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

    // ---- CALL: module afe_model from tb/afe_model.v ----
    afe_model u_afe (
        .clk     (clk),
        .sample  (adc_sample),
        .ch      (adc_ch),
        .dac     (adc_dac),
        .vin0_mv (12'd400),     // ch0 = 0.400 V -> code 31  (0x1F)
        .vin1_mv (12'd1111),    // ch1 = 1.111 V -> code 86  (0x56)
        .vin2_mv (12'd2000),    // ch2 = 2.000 V -> code 155 (0x9B)
        .vin3_mv (12'd3000),    // ch3 = 3.000 V -> code 232 (0xE8)
        .cmp     (adc_cmp)
    );

    // 100 MHz clock
    initial forever #5 clk = ~clk;

    // ---- counters ----
    integer cycles  = 0;
    integer io_acc  = 0;
    integer errors  = 0;
    integer checks  = 0;
    integer high    = 0;
    reg     irq_seen = 0;

    always @(posedge clk) if (!rst && !halted) begin
        cycles <= cycles + 1;
        if (dut.io_cs) io_acc <= io_acc + 1;
    end

    always @(posedge clk) if (irq) irq_seen <= 1'b1;

    // number of finished ADC conversions (EOC pulses inside the peripheral)
    integer n_eoc = 0;
    integer i, ram_bad;
    always @(posedge clk) if (!rst && dut.u_tadc.u_periph.adc_eoc) n_eoc <= n_eoc + 1;

    // ---- optional bus trace: uncomment to see every I/O access ----
    // always @(posedge clk) if (dut.io_cs)
    //     $display("t=%0t  %s  F%h  wdata=%02h rdata=%02h", $time,
    //              dut.io_we ? "ST" : "LD", dut.io_addr, dut.io_wdata, dut.io_rdata);

    // ---- check one RAM byte ----
    task check_mem(input [7:0] a, input [7:0] exp);
        begin
            checks = checks + 1;
            if (dut.u_cpu.u_dmem.mem[a] !== exp) begin
                $display("FAIL: MEM[%h] = %h, expected %h", a, dut.u_cpu.u_dmem.mem[a], exp);
                errors = errors + 1;
            end else
                $display("PASS: MEM[%h] = %h", a, exp);
        end
    endtask

    initial begin
        $dumpfile("risc8_soc.vcd");
        $dumpvars(0, tb_risc8_soc);

        #22 rst = 0;
        wait (halted);
        @(posedge clk);

        $display("\nCPU halted after %0d cycles, %0d I/O accesses", cycles, io_acc);
        $display("----------------- results in RAM -----------------");
        check_mem(8'h80, 8'hA8);   // A: ID register
        check_mem(8'h81, 8'h81);   // B: ADC_RCH = valid, ch1
        check_mem(8'h82, 8'h56);   // B: ch1 code (1.111 V)
        check_mem(8'h83, 8'h82);   // C: ADC_RCH = valid, ch2
        check_mem(8'h84, 8'h9B);   // C: ch2 code (2.0 V), timer start
        check_mem(8'h85, 8'h82);
        check_mem(8'h86, 8'h9B);
        check_mem(8'h87, 8'h82);
        check_mem(8'h88, 8'h9B);
        check_mem(8'h89, 8'h82);
        check_mem(8'h8A, 8'h9B);
        check_mem(8'h8B, 8'h07);   // C: IRQ_STAT = OVF | CMP | EOC
        check_mem(8'h8C, 8'h03);   // C: IRQ_STAT after W1C 0x04
        check_mem(8'h8D, 8'h0C);   // D: IRQ_STAT = EOC | WD
        check_mem(8'h8E, 8'hE8);   // D: ch3 code (3.0 V)
        check_mem(8'h8F, 8'h1F);   // F: 1st pop, ch0 code (0.40 V)
        check_mem(8'h90, 8'h56);   // F: 2nd pop, ch1 code (1.111 V)
        check_mem(8'h91, 8'h10);   // F: ADC_STAT = empty after 2 pops

        // ---- irq pin: high during Part D, low at the end ----
        checks = checks + 1;
        if (irq_seen && !irq)
            $display("PASS: irq pin went high during part D and was cleared");
        else begin
            $display("FAIL: irq_seen=%b irq now=%b", irq_seen, irq);
            errors = errors + 1;
        end

        // ---- check 21: stores to the I/O page never reached RAM ----
        //      (the firmware wrote to F0,F1,F2,F3,F5,F6,F7,F9,FD,FE)
        ram_bad = 0;
        for (i = 8'hF0; i <= 8'hFF; i = i + 1)
            if (dut.u_cpu.u_dmem.mem[i] !== 8'h00) ram_bad = ram_bad + 1;
        checks = checks + 1;
        if (ram_bad == 0)
            $display("PASS: RAM 0xF0-0xFF untouched (I/O stores went to the peripheral only)");
        else begin
            $display("FAIL: %0d RAM bytes in 0xF0-0xFF were written", ram_bad);
            errors = errors + 1;
        end

        // ---- check 22: exactly 8 conversions (B:1 + C:4 + D:1 + F:2) ----
        checks = checks + 1;
        if (n_eoc == 8)
            $display("PASS: ADC finished exactly %0d conversions (no extra / lost trigger)", n_eoc);
        else begin
            $display("FAIL: ADC finished %0d conversions, expected 8", n_eoc);
            errors = errors + 1;
        end

        // ---- PWM: count high clocks over 100 clocks (10 periods) ----
        high = 0;
        repeat (100) begin
            @(posedge clk);
            if (pwm) high = high + 1;
        end
        checks = checks + 1;
        if (high == 30)
            $display("PASS: PWM high for %0d of 100 clocks", high);
        else begin
            $display("FAIL: PWM high for %0d of 100 clocks, expected 30", high);
            errors = errors + 1;
        end

        $display("--------------------------------------------------");
        if (errors == 0) $display("*** SOC TEST PASSED *** (%0d checks)", checks);
        else             $display("*** SOC TEST FAILED *** (%0d of %0d checks)", errors, checks);
        $display("--------------------------------------------------");
        $finish;
    end

    // watchdog
    initial begin
        #200000;
        $display("TIMEOUT: CPU did not halt (PC=%h)", pc);
        $finish;
    end

endmodule
