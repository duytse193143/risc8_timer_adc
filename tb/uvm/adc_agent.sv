// =====================================================================
//  FILE : tb/uvm/adc_agent.sv   (included by timer_adc_pkg.sv)
// ---------------------------------------------------------------------
//  adc_vin_item   "set channel ch to mv millivolts"     (stimulus)
//  adc_conv_item  one finished conversion as observed   (to scoreboard)
//  adc_driver     drives the input voltages vin_mv[0..3]
//  adc_monitor    remembers the voltage that was held during SAMPLE and
//                 reports it together with the result at EOC
//  adc_agent      contains the three above
// =====================================================================

// ------------------------------------------------------- stimulus item
class adc_vin_item extends uvm_sequence_item;
    `uvm_object_utils(adc_vin_item)

    rand bit [1:0]  ch;
    rand bit [11:0] mv;

    function new(string name = "adc_vin_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("vin[%0d] = %0d mV", ch, mv);
    endfunction
endclass

// ---------------------------------------------------- observation item
class adc_conv_item extends uvm_object;
    `uvm_object_utils(adc_conv_item)

    bit [1:0]  ch;          // channel stored with the result (res_ch)
    bit [7:0]  result;      // code produced by the DUT
    bit [1:0]  sample_ch;   // channel the analog MUX had while sampling
    bit [11:0] held_mv;     // voltage that was held
    bit        valid_pred;  // 1 = a sample phase was seen for this result
    time       stamp;

    function new(string name = "adc_conv_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("ch=%0d result=%02h (held %0d mV on ch%0d)",
                         ch, result, held_mv, sample_ch);
    endfunction
endclass

typedef uvm_sequencer #(adc_vin_item) adc_sequencer;

// -------------------------------------------------------------- driver
class adc_driver extends uvm_driver #(adc_vin_item);
    `uvm_component_utils(adc_driver)

    virtual adc_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "adc_vif", vif))
            `uvm_fatal("NOVIF", "adc_vif not found in uvm_config_db")
    endfunction

    task run_phase(uvm_phase phase);
        vif.vin_mv <= '0;                     // all inputs 0 V
        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk);
            vif.vin_mv[req.ch] <= req.mv;     // change only on a rising edge
            `uvm_info("ADC_DRV", req.convert2string(), UVM_HIGH)
            seq_item_port.item_done();
        end
    endtask
endclass

// ------------------------------------------------------------- monitor
class adc_monitor extends uvm_monitor;
    `uvm_component_utils(adc_monitor)

    virtual adc_if vif;
    uvm_analysis_port #(adc_conv_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "adc_vif", vif))
            `uvm_fatal("NOVIF", "adc_vif not found in uvm_config_db")
    endfunction

    // Sample at the falling edge (stable values).
    //  - while sample = 1 : remember vin[ch]; the LAST value seen is the
    //                       one the sample & hold keeps
    //  - when eoc = 1     : report result + remembered voltage
    task run_phase(uvm_phase phase);
        adc_conv_item t;
        bit [11:0]    held_mv;
        bit [1:0]     held_ch;
        bit           have = 0;
        forever begin
            @(negedge vif.clk);
            if (vif.rst_n !== 1'b1) begin
                have = 0;
            end else begin
                if (vif.sample === 1'b1) begin
                    held_ch = vif.ch;
                    held_mv = vif.vin_mv[vif.ch];
                    have    = 1;
                end
                if (vif.eoc === 1'b1) begin
                    t = adc_conv_item::type_id::create("t");
                    t.ch         = vif.res_ch;
                    t.result     = vif.result;
                    t.sample_ch  = held_ch;
                    t.held_mv    = held_mv;
                    t.valid_pred = have;
                    t.stamp      = $time;
                    `uvm_info("ADC_MON", t.convert2string(), UVM_HIGH)
                    ap.write(t);
                    have = 0;
                end
            end
        end
    endtask
endclass

// --------------------------------------------------------------- agent
class adc_agent extends uvm_agent;
    `uvm_component_utils(adc_agent)

    adc_sequencer sqr;
    adc_driver    drv;
    adc_monitor   mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = adc_sequencer::type_id::create("sqr", this);
        drv = adc_driver   ::type_id::create("drv", this);
        mon = adc_monitor  ::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
