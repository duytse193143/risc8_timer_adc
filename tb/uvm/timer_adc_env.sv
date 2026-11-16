// =====================================================================
//  FILE : tb/uvm/timer_adc_env.sv   (included by timer_adc_pkg.sv)
// ---------------------------------------------------------------------
//  The environment builds the two agents, the scoreboard and the
//  coverage collector, then connects the monitors to them:
//
//    apb_agent.mon.ap --+--> scoreboard.apb_export
//                       +--> coverage.apb_export
//    adc_agent.mon.ap --+--> scoreboard.adc_export
//                       +--> coverage.adc_export
// =====================================================================

class timer_adc_env extends uvm_env;
    `uvm_component_utils(timer_adc_env)

    apb_agent            apb_agt;
    adc_agent            adc_agt;
    timer_adc_scoreboard sb;
    timer_adc_coverage   cov;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_agt = apb_agent           ::type_id::create("apb_agt", this);
        adc_agt = adc_agent           ::type_id::create("adc_agt", this);
        sb      = timer_adc_scoreboard::type_id::create("sb",      this);
        cov     = timer_adc_coverage  ::type_id::create("cov",     this);
    endfunction

    function void connect_phase(uvm_phase phase);
        apb_agt.mon.ap.connect(sb.apb_export);
        apb_agt.mon.ap.connect(cov.apb_export);
        adc_agt.mon.ap.connect(sb.adc_export);
        adc_agt.mon.ap.connect(cov.adc_export);
    endfunction
endclass
