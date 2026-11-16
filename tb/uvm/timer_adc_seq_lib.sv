// =====================================================================
//  FILE : tb/uvm/timer_adc_seq_lib.sv   (included by timer_adc_pkg.sv)
// ---------------------------------------------------------------------
//  Stimulus. Every scenario is a "virtual sequence": it does not run on
//  one sequencer, it sends items to BOTH the APB sequencer (register
//  reads/writes) and the ADC sequencer (input voltages).
//
//  tadc_base_vseq      helper tasks: wr, rd, set_vin, wait_clks, ...
//  tadc_reg_vseq       reset values, write/read-back, RO registers
//  tadc_timer_vseq     timer periods, PWM duty, one-shot, flags
//  tadc_adc_sw_vseq    software-started conversions, corner voltages
//  tadc_adc_timer_vseq timer-triggered conversions + TRIG_MISS
//  tadc_adc_cont_vseq  continuous mode, FIFO full / overflow, abort
//  tadc_window_vseq    window comparator at the exact boundary codes
//  tadc_random_vseq    random settings and register traffic
//  tadc_all_vseq       all of the above, one after another
// =====================================================================

// ===================================================================
//  BASE: helper tasks shared by all scenarios
// ===================================================================
class tadc_base_vseq extends uvm_sequence #(uvm_sequence_item);
    `uvm_object_utils(tadc_base_vseq)

    apb_sequencer  apb_sqr;    // set by the test
    adc_sequencer  adc_sqr;    // set by the test
    virtual adc_if vif;        // for clock counting and pin checks

    function new(string name = "tadc_base_vseq");
        super.new(name);
    endfunction

    // copy the handles into a child sequence and run it
    task run_child(tadc_base_vseq s);
        s.apb_sqr = apb_sqr;
        s.adc_sqr = adc_sqr;
        s.vif     = vif;
        s.start(null);
    endtask

    // ---- register write ----
    task wr(bit [3:0] a, bit [7:0] d);
        apb_item it;
        it = apb_item::type_id::create("wr");
        start_item(it, -1, apb_sqr);
        it.write = 1;
        it.addr  = a;
        it.wdata = d;
        finish_item(it);
    endtask

    // ---- register read ----
    task rd(bit [3:0] a, output bit [7:0] d);
        apb_item it;
        it = apb_item::type_id::create("rd");
        start_item(it, -1, apb_sqr);
        it.write = 0;
        it.addr  = a;
        it.wdata = 8'h00;
        finish_item(it);
        d = it.rdata;
    endtask

    // ---- set one analog input (millivolts) ----
    task set_vin(int ch, int mv);
        adc_vin_item it;
        it = adc_vin_item::type_id::create("vin");
        start_item(it, -1, adc_sqr);
        it.ch = ch[1:0];
        it.mv = (mv > 4095) ? 12'd4095 : mv[11:0];
        finish_item(it);
    endtask

    task wait_clks(int n);
        repeat (n) @(posedge vif.clk);
    endtask

    // ---- check helper ----
    function void expect_eq(string what, int got, int exp);
        if (got !== exp)
            `uvm_error("SEQ", $sformatf("%s: got %0h, expected %0h", what, got, exp))
        else
            `uvm_info("SEQ", $sformatf("%s = %0h  OK", what, got), UVM_MEDIUM)
    endfunction

    // ---- poll ADC_STAT until the FIFO is not empty ----
    task wait_not_empty(int max_polls = 2000);
        bit [7:0] s;
        repeat (max_polls) begin
            rd(ADC_STAT, s);
            if (s[4] == 1'b0) return;
        end
        `uvm_error("SEQ", "timeout: no ADC result arrived")
    endtask

    // ---- read everything left in the FIFO ----
    task drain();
        bit [7:0] s, d;
        int       n = 0;
        rd(ADC_STAT, s);
        while (s[4] == 1'b0 && n < 12) begin
            rd(ADC_RCH,  d);
            rd(ADC_DATA, d);
            rd(ADC_STAT, s);
            n++;
        end
    endtask

    // ---- one software conversion: set voltage, START, wait, read ----
    task convert_sw(int ch, int mv, bit [7:0] smp = 8'd2, bit [7:0] div = 8'd0);
        bit [7:0] ctrl, d;
        set_vin(ch, mv);
        wr(ADC_SMP, smp);
        wr(ADC_DIV, div);
        ctrl = 8'h03 | (ch[1:0] << 4);     // EN + START + channel
        wr(ADC_CTRL, ctrl);
        wait_not_empty();
        rd(ADC_RCH,  d);                   // scoreboard checks channel
        rd(ADC_DATA, d);                   // scoreboard checks code
    endtask

    // ---- put the timer and ADC back to a quiet state ----
    task quiet();
        wr(TMR_CTRL, 8'h00);
        wr(ADC_CTRL, 8'h00);
        wait_clks(5);
        drain();
        wr(IRQ_STAT, 8'hFF);
    endtask

    task body();
        // the base sequence does nothing
    endtask
endclass

// ===================================================================
//  1. REGISTER TEST
// ===================================================================
class tadc_reg_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_reg_vseq)
    function new(string name = "tadc_reg_vseq"); super.new(name); endfunction

    task body();
        bit [7:0] d;
        bit [3:0] rw_regs[8] = '{TMR_PRESC, TMR_LOAD, TMR_CMP, ADC_SMP,
                                 ADC_DIV, ADC_THR_LO, ADC_THR_HI, IRQ_EN};
        bit [7:0] pats[5]    = '{8'h00, 8'hFF, 8'h55, 8'hAA, 8'h00};

        `uvm_info("SEQ", "=== register test ===", UVM_LOW)

        // ---- 1) reset values of all 16 registers ----
        for (int a = 0; a < 16; a++) begin
            rd(a[3:0], d);              // scoreboard checks RW / ID / STAT
        end
        rd(TMR_CNT,  d);  expect_eq("TMR_CNT after reset",  d, 8'h00);
        rd(IRQ_STAT, d);  expect_eq("IRQ_STAT after reset", d, 8'h00);
        rd(ADC_STAT, d);  expect_eq("ADC_STAT after reset", d, 8'h10);
        rd(ID_REG,   d);  expect_eq("ID",                   d, 8'hA8);

        // ---- 2) write / read-back with fixed and random patterns ----
        pats[4] = $urandom;
        foreach (rw_regs[i]) begin
            foreach (pats[j]) begin
                wr(rw_regs[i], pats[j]);
                rd(rw_regs[i], d);      // scoreboard compares with shadow
            end
        end

        // ---- 3) control registers (keep EN = 0 so nothing starts) ----
        wr(TMR_CTRL, 8'h02); rd(TMR_CTRL, d); expect_eq("TMR_CTRL oneshot", d, 8'h02);
        wr(TMR_CTRL, 8'h00);
        wr(ADC_CTRL, 8'h3C); rd(ADC_CTRL, d); expect_eq("ADC_CTRL", d, 8'h3C);
        wr(ADC_CTRL, 8'h02); rd(ADC_CTRL, d); expect_eq("ADC_CTRL START reads 0", d, 8'h00);
        wait_clks(30);
        rd(ADC_STAT, d);     expect_eq("no conversion while EN=0", d, 8'h10);

        // ---- 4) read-only registers ignore writes ----
        wr(ID_REG,   8'h00); rd(ID_REG,   d); expect_eq("ID after write",       d, 8'hA8);
        wr(ADC_STAT, 8'hFF); rd(ADC_STAT, d); expect_eq("ADC_STAT after write", d, 8'h10);
        wr(TMR_CNT,  8'h77); rd(TMR_CNT,  d); expect_eq("TMR_CNT after write",  d, 8'h00);
        wr(ADC_DATA, 8'h99); rd(ADC_DATA, d); expect_eq("ADC_DATA empty",       d, 8'h00);

        // ---- 5) back to reset values ----
        wr(TMR_PRESC, 8'h00); wr(TMR_LOAD, 8'hFF); wr(TMR_CMP, 8'h80);
        wr(ADC_SMP,   8'h04); wr(ADC_DIV,  8'h00);
        wr(ADC_THR_LO, 8'h00); wr(ADC_THR_HI, 8'hFF); wr(IRQ_EN, 8'h00);
    endtask
endclass

// ===================================================================
//  2. TIMER TEST
// ===================================================================
class tadc_timer_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_timer_vseq)
    function new(string name = "tadc_timer_vseq"); super.new(name); endfunction

    task timer_case(int presc, int load, int cmp, bit oneshot);
        bit [7:0] d;
        int period, high, exp_high, duty;

        period = (presc + 1) * (load + 1);
        `uvm_info("SEQ", $sformatf("timer: PRESC=%0d LOAD=%0d CMP=%0d oneshot=%0d (period %0d clk)",
                  presc, load, cmp, oneshot, period), UVM_LOW)

        wr(TMR_CTRL,  8'h00);
        wr(TMR_PRESC, presc[7:0]);
        wr(TMR_LOAD,  load[7:0]);
        wr(TMR_CMP,   cmp[7:0]);
        wr(IRQ_STAT,  8'hFF);
        wr(TMR_CTRL,  oneshot ? 8'h03 : 8'h01);

        if (oneshot) begin
            wait_clks(period + 20);
            rd(TMR_CTRL, d);  expect_eq("one-shot cleared EN", d[0], 0);
            rd(TMR_CNT,  d);  expect_eq("one-shot CNT",        d, 0);
            rd(IRQ_STAT, d);  expect_eq("one-shot OVF flag",   d[0], 1);
            // run longer: no second overflow
            wr(IRQ_STAT, 8'hFF);
            wait_clks(period + 20);
            rd(IRQ_STAT, d);  expect_eq("one-shot: no 2nd OVF", d[0], 0);
        end else begin
            wait_clks(period + 5);                // let the first period pass
            // PWM: count high clocks over exactly 2 periods
            high = 0;
            repeat (2 * period) begin
                @(negedge vif.clk);
                if (vif.pwm === 1'b1) high++;
            end
            duty     = (cmp < load + 1) ? cmp : load + 1;
            exp_high = 2 * duty * (presc + 1);
            expect_eq("PWM high clocks in 2 periods", high, exp_high);

            rd(IRQ_STAT, d);
            expect_eq("OVF flag", d[0], 1);
            expect_eq("CMP flag", d[1], (cmp <= load) ? 1 : 0);
            rd(TMR_CNT, d);
            if (d > load) `uvm_error("SEQ", $sformatf("TMR_CNT %0d > LOAD %0d", d, load))
        end

        wr(TMR_CTRL, 8'h00);
        wait_clks(2);
        if (vif.pwm !== 1'b0) `uvm_error("SEQ", "PWM not low after disable")
        wr(IRQ_STAT, 8'hFF);
    endtask

    task body();
        `uvm_info("SEQ", "=== timer test ===", UVM_LOW)
        timer_case(1,  4,  2, 0);     // the example from the guide (10 clk)
        timer_case(0,  9,  3, 0);     // 30 % PWM
        timer_case(3, 24, 12, 0);     // 100-clock period
        timer_case(0,  0,  0, 0);     // LOAD = 0: overflow every clock
        timer_case(2,  9, 10, 0);     // CMP > LOAD: PWM always high, no CMP flag
        timer_case(0,  9,  0, 0);     // CMP = 0: PWM always low
        timer_case(15, 99, 50, 0);    // big prescaler
        timer_case(0,  9,  3, 1);     // one-shot
        timer_case(4, 19,  7, 1);     // one-shot with prescaler
        repeat (3) timer_case($urandom_range(0, 5), $urandom_range(0, 40),
                              $urandom_range(0, 45), 0);
    endtask
endclass

// ===================================================================
//  3. ADC SOFTWARE-START TEST
// ===================================================================
class tadc_adc_sw_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_adc_sw_vseq)
    function new(string name = "tadc_adc_sw_vseq"); super.new(name); endfunction

    task body();
        int volts[12] = '{0, 5, 12, 13, 400, 1111, 1650, 2000, 3000, 3287, 3299, 4095};
        `uvm_info("SEQ", "=== ADC software-start test ===", UVM_LOW)

        // corner voltages on every channel, different SMP / DIV
        for (int ch = 0; ch < 4; ch++)
            foreach (volts[i])
                convert_sw(ch, volts[i], (i % 4), (ch % 3));

        // exact code boundaries: the lowest mV of a code and 1 mV below
        for (int c = 1; c < 256; c += 37) begin
            convert_sw(c % 4, mv_of_code(c),     1, 0);
            convert_sw(c % 4, mv_of_code(c) - 1, 1, 0);
        end

        // random
        repeat (20)
            convert_sw($urandom_range(0, 3), $urandom_range(0, 3400),
                       $urandom_range(0, 6), $urandom_range(0, 3));
        quiet();
    endtask
endclass

// ===================================================================
//  4. ADC TIMER-TRIGGER TEST (+ TRIG_MISS)
// ===================================================================
class tadc_adc_timer_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_adc_timer_vseq)
    function new(string name = "tadc_adc_timer_vseq"); super.new(name); endfunction

    task body();
        bit [7:0] d, ctrl;
        int ch;
        `uvm_info("SEQ", "=== ADC timer-trigger test ===", UVM_LOW)

        wr(ADC_SMP, 8'd2);
        wr(ADC_DIV, 8'd0);
        wr(TMR_PRESC, 8'd1);
        wr(TMR_LOAD,  8'd49);          // period = 2 * 50 = 100 clocks
        wr(TMR_CMP,   8'd25);

        // trigger source 1 = overflow, 2 = compare
        for (int trig = 1; trig <= 2; trig++) begin
            ch   = $urandom_range(0, 3);
            ctrl = 8'h01 | (trig[1:0] << 2) | (ch[1:0] << 4);
            wr(IRQ_STAT, 8'hFF);
            set_vin(ch, 0);
            wr(ADC_CTRL, ctrl);
            wr(TMR_CTRL, 8'h01);
            for (int i = 0; i < 12; i++) begin
                set_vin(ch, (i * 290) % 3500);     // ramp the input
                wait_not_empty();
                rd(ADC_RCH,  d);
                rd(ADC_DATA, d);
            end
            rd(IRQ_STAT, d);
            expect_eq("EOC flag (timer trigger)", d[2], 1);
            quiet();
        end

        // triggers faster than conversions -> TRIG_MISS
        wr(ADC_SMP,   8'd20);
        wr(ADC_DIV,   8'd1);           // conversion = 29 * 2 = 58 clocks
        wr(TMR_PRESC, 8'd0);
        wr(TMR_LOAD,  8'd4);           // overflow every 5 clocks
        wr(IRQ_STAT,  8'hFF);
        wr(ADC_CTRL,  8'h05);          // EN, trigger = overflow, ch0
        wr(TMR_CTRL,  8'h01);
        wait_clks(200);
        wr(TMR_CTRL,  8'h00);
        rd(IRQ_STAT, d);
        expect_eq("TRIG_MISS flag", d[5], 1);
        quiet();
        wr(ADC_SMP, 8'h04); wr(ADC_DIV, 8'h00);
        wr(TMR_PRESC, 8'h00); wr(TMR_LOAD, 8'hFF); wr(TMR_CMP, 8'h80);
    endtask
endclass

// ===================================================================
//  5. ADC CONTINUOUS MODE, FIFO FULL / OVERFLOW, ABORT
// ===================================================================
class tadc_adc_cont_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_adc_cont_vseq)
    function new(string name = "tadc_adc_cont_vseq"); super.new(name); endfunction

    task body();
        bit [7:0] d;
        `uvm_info("SEQ", "=== ADC continuous / FIFO test ===", UVM_LOW)

        // ---- continuous mode fills the FIFO and overflows it ----
        wr(IRQ_STAT, 8'hFF);
        set_vin(2, 1234);
        wr(ADC_SMP, 8'd0);
        wr(ADC_DIV, 8'd0);                 // 9 clocks per conversion
        wr(ADC_CTRL, 8'h2D);               // EN, trigger = continuous, ch2
        wait_clks(150);
        rd(ADC_STAT, d);   expect_eq("FIFO full",     d[5], 1);
        rd(IRQ_STAT, d);   expect_eq("FIFO_OVR flag", d[4], 1);
                           expect_eq("EOC flag",      d[2], 1);
        wr(ADC_CTRL, 8'h00);               // stop
        wait_clks(5);
        drain();                           // scoreboard checks the 8 kept
        rd(ADC_STAT, d);   expect_eq("FIFO empty after drain", d, 8'h10);

        // ---- read and push in the same clocks: continuous + reading ----
        set_vin(1, 2500);
        wr(ADC_CTRL, 8'h1D);               // EN, continuous, ch1
        repeat (20) begin
            rd(ADC_RCH,  d);
            rd(ADC_DATA, d);
        end
        wr(ADC_CTRL, 8'h00);
        wait_clks(5);
        drain();

        // ---- abort: clear EN in the middle of a conversion ----
        wr(ADC_SMP, 8'd50);
        wr(ADC_CTRL, 8'h13);               // EN + START, ch1
        wait_clks(10);
        wr(ADC_CTRL, 8'h00);               // abort
        wait_clks(100);
        rd(ADC_STAT, d);   expect_eq("no result after abort", d, 8'h10);

        // ---- W1C: clear all flags ----
        wr(IRQ_STAT, 8'hFF);
        rd(IRQ_STAT, d);   expect_eq("IRQ_STAT after W1C", d, 8'h00);
        wr(ADC_SMP, 8'h04);
    endtask
endclass

// ===================================================================
//  6. WINDOW COMPARATOR + IRQ PIN
// ===================================================================
class tadc_window_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_window_vseq)
    function new(string name = "tadc_window_vseq"); super.new(name); endfunction

    task body();
        bit [7:0] d, s;
        int codes[10] = '{0, 49, 50, 51, 128, 199, 200, 201, 254, 255};
        int lo = 50, hi = 200;
        bit exp_wd;
        `uvm_info("SEQ", "=== window comparator test ===", UVM_LOW)

        wr(ADC_THR_LO, lo[7:0]);
        wr(ADC_THR_HI, hi[7:0]);
        wr(IRQ_EN,     8'h08);             // irq only for ADC_WD
        wr(ADC_SMP,    8'd1);
        wr(ADC_DIV,    8'd0);

        foreach (codes[i]) begin
            exp_wd = (codes[i] < lo) || (codes[i] > hi);
            wr(IRQ_STAT, 8'hFF);
            set_vin(0, mv_of_code(codes[i]));
            wr(ADC_CTRL, 8'h03);           // EN + START, ch0
            wait_not_empty();
            rd(ADC_DATA, d);
            expect_eq($sformatf("code for %0d", codes[i]), d, codes[i]);
            rd(IRQ_STAT, s);
            expect_eq($sformatf("WD flag for code %0d", codes[i]), s[3], exp_wd);
            expect_eq($sformatf("irq pin for code %0d", codes[i]), vif.irq, exp_wd);
        end

        wr(IRQ_STAT, 8'hFF);
        wait_clks(2);
        expect_eq("irq pin after W1C", vif.irq, 0);

        // restore
        wr(ADC_THR_LO, 8'h00); wr(ADC_THR_HI, 8'hFF); wr(IRQ_EN, 8'h00);
        wr(ADC_SMP, 8'h04);    wr(ADC_CTRL, 8'h00);
    endtask
endclass

// ===================================================================
//  7. RANDOM TEST
// ===================================================================
class tadc_random_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_random_vseq)
    function new(string name = "tadc_random_vseq"); super.new(name); endfunction

    task body();
        bit [7:0] d;
        int op;
        `uvm_info("SEQ", "=== random test ===", UVM_LOW)

        repeat (60) begin
            op = $urandom_range(0, 5);
            case (op)
                0, 1: convert_sw($urandom_range(0, 3), $urandom_range(0, 4095),
                                 $urandom_range(0, 7), $urandom_range(0, 3));
                2:    begin
                          wr(ADC_THR_LO, $urandom_range(0, 127));
                          wr(ADC_THR_HI, $urandom_range(128, 255));
                          wr(IRQ_EN,     $urandom);
                      end
                3:    begin   // a burst of timer-triggered conversions
                          wr(TMR_PRESC, $urandom_range(0, 2));
                          wr(TMR_LOAD,  $urandom_range(20, 60));
                          wr(ADC_SMP,   $urandom_range(0, 3));
                          wr(ADC_DIV,   8'd0);
                          set_vin($urandom_range(0, 3), $urandom_range(0, 3300));
                          wr(ADC_CTRL,  8'h05 | ($urandom_range(0, 3) << 4));
                          wr(TMR_CTRL,  8'h01);
                          wait_clks($urandom_range(100, 400));
                          wr(TMR_CTRL,  8'h00);
                          wr(ADC_CTRL,  8'h00);
                          wait_clks(5);
                          drain();
                      end
                4:    begin   // random status reads
                          rd(ADC_STAT, d);
                          rd(ADC_RCH,  d);
                          rd(IRQ_STAT, d);
                          rd(TMR_CNT,  d);
                      end
                5:    begin   // W1C with a random mask
                          wr(IRQ_STAT, $urandom);
                          rd(IRQ_STAT, d);
                      end
            endcase
        end
        quiet();
        wr(IRQ_EN, 8'h00);
        wr(ADC_THR_LO, 8'h00);
        wr(ADC_THR_HI, 8'hFF);
    endtask
endclass

// ===================================================================
//  8. ALL
// ===================================================================
class tadc_all_vseq extends tadc_base_vseq;
    `uvm_object_utils(tadc_all_vseq)
    function new(string name = "tadc_all_vseq"); super.new(name); endfunction

    task body();
        tadc_reg_vseq       s1 = tadc_reg_vseq      ::type_id::create("s1");
        tadc_timer_vseq     s2 = tadc_timer_vseq    ::type_id::create("s2");
        tadc_adc_sw_vseq    s3 = tadc_adc_sw_vseq   ::type_id::create("s3");
        tadc_adc_timer_vseq s4 = tadc_adc_timer_vseq::type_id::create("s4");
        tadc_adc_cont_vseq  s5 = tadc_adc_cont_vseq ::type_id::create("s5");
        tadc_window_vseq    s6 = tadc_window_vseq   ::type_id::create("s6");
        tadc_random_vseq    s7 = tadc_random_vseq   ::type_id::create("s7");
        run_child(s1);
        run_child(s2);
        run_child(s3);
        run_child(s4);
        run_child(s5);
        run_child(s6);
        run_child(s7);
    endtask
endclass
