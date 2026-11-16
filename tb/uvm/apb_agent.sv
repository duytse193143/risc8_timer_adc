// =====================================================================
//  FILE : tb/uvm/apb_agent.sv   (included by timer_adc_pkg.sv)
// ---------------------------------------------------------------------
//  apb_item       one register read or write
//  apb_sequencer  hands items from a sequence to the driver
//  apb_driver     turns an item into APB pin wiggles (SETUP + ACCESS)
//  apb_monitor    watches the pins, reports every finished transfer
//  apb_agent      contains the three above
// =====================================================================

// ---------------------------------------------------------------- item
class apb_item extends uvm_sequence_item;
    `uvm_object_utils(apb_item)

    rand bit       write;     // 1 = write, 0 = read
    rand bit [3:0] addr;      // register number 0..15
    rand bit [7:0] wdata;     // data to write
    bit      [7:0] rdata;     // data read back (filled by driver/monitor)
    time           stamp;     // when the monitor saw it

    function new(string name = "apb_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%s addr=%0h wdata=%02h rdata=%02h",
                         write ? "WR" : "RD", addr, wdata, rdata);
    endfunction
endclass

typedef uvm_sequencer #(apb_item) apb_sequencer;

// -------------------------------------------------------------- driver
class apb_driver extends uvm_driver #(apb_item);
    `uvm_component_utils(apb_driver)

    virtual apb_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
            `uvm_fatal("NOVIF", "apb_vif not found in uvm_config_db")
    endfunction

    task run_phase(uvm_phase phase);
        // idle bus
        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        vif.pwrite  <= 1'b0;
        vif.paddr   <= 4'h0;
        vif.pwdata  <= 8'h00;
        @(posedge vif.clk iff vif.rst_n === 1'b1);

        forever begin
            seq_item_port.get_next_item(req);

            // ---- SETUP phase: psel = 1, penable = 0 ----
            @(posedge vif.clk);
            vif.psel    <= 1'b1;
            vif.penable <= 1'b0;
            vif.pwrite  <= req.write;
            vif.paddr   <= req.addr;
            vif.pwdata  <= req.write ? req.wdata : 8'h00;

            // ---- ACCESS phase: penable = 1 (pready is always 1) ----
            @(posedge vif.clk);
            vif.penable <= 1'b1;

            // read data is stable in the middle of the ACCESS cycle
            @(negedge vif.clk);
            req.rdata = vif.prdata;

            // ---- end of transfer ----
            @(posedge vif.clk);
            vif.psel    <= 1'b0;
            vif.penable <= 1'b0;

            seq_item_port.item_done();
        end
    endtask
endclass

// ------------------------------------------------------------- monitor
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    virtual apb_if vif;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
            `uvm_fatal("NOVIF", "apb_vif not found in uvm_config_db")
    endfunction

    // Sample at the FALLING edge: the DUT only uses rising edges, so
    // every signal is stable here. A transfer = psel & penable.
    task run_phase(uvm_phase phase);
        apb_item t;
        forever begin
            @(negedge vif.clk);
            if (vif.rst_n === 1'b1 && vif.psel === 1'b1 && vif.penable === 1'b1) begin
                t = apb_item::type_id::create("t");
                t.write = vif.pwrite;
                t.addr  = vif.paddr;
                t.wdata = vif.pwdata;
                t.rdata = vif.prdata;
                t.stamp = $time;
                `uvm_info("APB_MON", t.convert2string(), UVM_HIGH)
                ap.write(t);
            end
        end
    endtask
endclass

// --------------------------------------------------------------- agent
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    apb_sequencer sqr;
    apb_driver    drv;
    apb_monitor   mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = apb_sequencer::type_id::create("sqr", this);
        drv = apb_driver   ::type_id::create("drv", this);
        mon = apb_monitor  ::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
