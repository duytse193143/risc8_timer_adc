// =====================================================================
//  FILE : tb/uvm/timer_adc_coverage.sv   (included by timer_adc_pkg.sv)
// ---------------------------------------------------------------------
//  Functional coverage = a tick-list of situations the tests should
//  reach. Printed at the end of every test.
//
//    cg_reg    every register address x read/write
//    cg_cfg    ADC trigger source x channel (from ADC_CTRL writes with EN=1)
//    cg_adc    channel x result range (zero / low / mid / high / full)
//    cg_irq    each interrupt flag seen set in an IRQ_STAT read
//    cg_fifo   FIFO level values seen in ADC_STAT reads
// =====================================================================

class timer_adc_coverage extends uvm_component;
    `uvm_component_utils(timer_adc_coverage)

    uvm_analysis_imp_apb #(apb_item,      timer_adc_coverage) apb_export;
    uvm_analysis_imp_adc #(adc_conv_item, timer_adc_coverage) adc_export;

    // sampled values
    bit [3:0] m_addr;
    bit       m_write;
    bit [1:0] m_trig, m_ch;
    bit [7:0] m_code;
    bit [5:0] m_irq;
    bit [3:0] m_level;

    covergroup cg_reg;
        cp_addr : coverpoint m_addr;                       // 16 bins
        cp_rw   : coverpoint m_write { bins rd = {0}; bins wr = {1}; }
        x_addr_rw : cross cp_addr, cp_rw;
    endgroup

    covergroup cg_cfg;
        cp_trig : coverpoint m_trig { bins sw = {0}; bins ovf = {1}; bins cmp = {2}; bins cont = {3}; }
        cp_ch   : coverpoint m_ch;
        x_trig_ch : cross cp_trig, cp_ch;
    endgroup

    covergroup cg_adc;
        cp_ch   : coverpoint m_ch;
        cp_code : coverpoint m_code {
            bins zero = {0};
            bins low  = {[1:63]};
            bins mid  = {[64:191]};
            bins high = {[192:254]};
            bins full = {255};
        }
        x_ch_code : cross cp_ch, cp_code;
    endgroup

    covergroup cg_irq;
        cp_ovf  : coverpoint m_irq[0] { bins set = {1}; }
        cp_cmp  : coverpoint m_irq[1] { bins set = {1}; }
        cp_eoc  : coverpoint m_irq[2] { bins set = {1}; }
        cp_wd   : coverpoint m_irq[3] { bins set = {1}; }
        cp_ovr  : coverpoint m_irq[4] { bins set = {1}; }
        cp_miss : coverpoint m_irq[5] { bins set = {1}; }
    endgroup

    covergroup cg_fifo;
        cp_level : coverpoint m_level {
            bins empty = {0};
            bins one   = {1};
            bins some  = {[2:7]};
            bins full  = {8};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_export = new("apb_export", this);
        adc_export = new("adc_export", this);
        cg_reg  = new();
        cg_cfg  = new();
        cg_adc  = new();
        cg_irq  = new();
        cg_fifo = new();
    endfunction

    function void write_apb(apb_item t);
        m_addr  = t.addr;
        m_write = t.write;
        cg_reg.sample();

        if (t.write && t.addr == ADC_CTRL && t.wdata[0]) begin
            m_trig = t.wdata[3:2];
            m_ch   = t.wdata[5:4];
            cg_cfg.sample();
        end
        if (!t.write && t.addr == IRQ_STAT) begin
            m_irq = t.rdata[5:0];
            cg_irq.sample();
        end
        if (!t.write && t.addr == ADC_STAT) begin
            m_level = t.rdata[3:0];
            cg_fifo.sample();
        end
    endfunction

    function void write_adc(adc_conv_item t);
        m_ch   = t.ch;
        m_code = t.result;
        cg_adc.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf({"\n----------------- COVERAGE -------------------",
                  "\n registers  (addr x rd/wr)   : %5.1f %%",
                  "\n ADC config (trigger x ch)   : %5.1f %%",
                  "\n ADC result (ch x range)     : %5.1f %%",
                  "\n interrupt flags seen        : %5.1f %%",
                  "\n FIFO levels seen            : %5.1f %%",
                  "\n----------------------------------------------"},
                  cg_reg.get_coverage(), cg_cfg.get_coverage(), cg_adc.get_coverage(),
                  cg_irq.get_coverage(), cg_fifo.get_coverage()), UVM_NONE)
    endfunction
endclass
