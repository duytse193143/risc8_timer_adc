// =====================================================================
//  FILE : tb/uvm/timer_adc_tests.sv   (included by timer_adc_pkg.sv)
// ---------------------------------------------------------------------
//  Runnable tests. Pick one with  +UVM_TESTNAME=<name>
//  (in Vivado: -testplusarg UVM_TESTNAME=<name>)
//
//    tadc_reg_test        registers
//    tadc_timer_test      timer + PWM + one-shot
//    tadc_adc_sw_test     software-started conversions
//    tadc_adc_timer_test  timer-triggered conversions + TRIG_MISS
//    tadc_adc_cont_test   continuous mode, FIFO overflow, abort
//    tadc_window_test     window comparator + irq pin
//    tadc_random_test     random traffic
//    tadc_all_test        everything above
//
//  Each test = base test (builds the env, runs a virtual sequence,
//  prints PASSED / FAILED) + the name of the sequence to run.
// =====================================================================

class tadc_base_test extends uvm_test;
    `uvm_component_utils(tadc_base_test)

    timer_adc_env  env;
    virtual adc_if adc_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = timer_adc_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "adc_vif", adc_vif))
            `uvm_fatal("NOVIF", "adc_vif not found in uvm_config_db")
    endfunction

    // each test overrides this to choose its scenario
    virtual function tadc_base_vseq make_vseq();
        return tadc_base_vseq::type_id::create("vseq");
    endfunction

    task run_phase(uvm_phase phase);
        tadc_base_vseq vseq;
        phase.raise_objection(this);

        // wait for reset to finish
        @(posedge adc_vif.clk iff adc_vif.rst_n === 1'b1);
        repeat (5) @(posedge adc_vif.clk);

        vseq         = make_vseq();
        vseq.apb_sqr = env.apb_agt.sqr;
        vseq.adc_sqr = env.adc_agt.sqr;
        vseq.vif     = adc_vif;
        vseq.start(null);

        repeat (20) @(posedge adc_vif.clk);
        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        uvm_report_server srv;
        int errors;
        srv    = uvm_report_server::get_server();
        errors = srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL);
        if (errors == 0)
            `uvm_info("RESULT", $sformatf("\n\n    ***  TEST %s PASSED  ***\n", get_type_name()), UVM_NONE)
        else
            `uvm_info("RESULT", $sformatf("\n\n    ***  TEST %s FAILED  (%0d errors)  ***\n",
                      get_type_name(), errors), UVM_NONE)
    endfunction
endclass

// ---------------------------------------------------------------------
class tadc_reg_test extends tadc_base_test;
    `uvm_component_utils(tadc_reg_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_reg_vseq s = tadc_reg_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass

class tadc_timer_test extends tadc_base_test;
    `uvm_component_utils(tadc_timer_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_timer_vseq s = tadc_timer_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass

class tadc_adc_sw_test extends tadc_base_test;
    `uvm_component_utils(tadc_adc_sw_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_adc_sw_vseq s = tadc_adc_sw_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass

class tadc_adc_timer_test extends tadc_base_test;
    `uvm_component_utils(tadc_adc_timer_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_adc_timer_vseq s = tadc_adc_timer_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass

class tadc_adc_cont_test extends tadc_base_test;
    `uvm_component_utils(tadc_adc_cont_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_adc_cont_vseq s = tadc_adc_cont_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass

class tadc_window_test extends tadc_base_test;
    `uvm_component_utils(tadc_window_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_window_vseq s = tadc_window_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass

class tadc_random_test extends tadc_base_test;
    `uvm_component_utils(tadc_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_random_vseq s = tadc_random_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass

class tadc_all_test extends tadc_base_test;
    `uvm_component_utils(tadc_all_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function tadc_base_vseq make_vseq();
        tadc_all_vseq s = tadc_all_vseq::type_id::create("vseq");
        return s;
    endfunction
endclass
