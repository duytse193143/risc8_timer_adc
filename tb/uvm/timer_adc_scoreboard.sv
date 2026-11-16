// =====================================================================
//  FILE : tb/uvm/timer_adc_scoreboard.sv   (included by timer_adc_pkg.sv)
// ---------------------------------------------------------------------
//  Reference model + checker.
//
//  Inputs (analysis exports)
//    write_apb : every bus transfer seen by apb_monitor
//    write_adc : every finished conversion seen by adc_monitor
//
//  What it checks
//    1. Every ADC result == floor(held_mv * 256 / 3300)  (max 255)
//       and the stored channel == the channel that was sampled.
//    2. A model of the 8-entry FIFO (with the "drop when full" rule):
//         - read ADC_DATA  -> must return the oldest model entry (pop)
//         - read ADC_RCH   -> must return {VALID, ch} of the oldest entry
//         - read ADC_STAT  -> LEVEL / EMPTY / FULL must match the model
//    3. A shadow copy of every RW register: read-back == last write.
//    4. ID always reads A8.
//
//  Ordering rule (same clock edge)
//    Both monitors stamp items with the falling edge time of the cycle.
//    A push (EOC) and a bus read in the SAME cycle act on the same
//    rising edge, and the read sees the FIFO BEFORE the push. So pushes
//    are kept "pending" and applied only before a later bus transfer.
// =====================================================================

`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_adc)

class timer_adc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(timer_adc_scoreboard)

    uvm_analysis_imp_apb #(apb_item,      timer_adc_scoreboard) apb_export;
    uvm_analysis_imp_adc #(adc_conv_item, timer_adc_scoreboard) adc_export;

    // ---- model state ----
    bit [9:0]     fifo_q[$];       // {ch, data}, oldest first
    adc_conv_item pend[$];         // results not yet pushed into fifo_q
    bit [7:0]     shadow[16];      // register shadow copy

    // ---- statistics ----
    int n_conv_ok, n_conv_err;
    int n_reads, n_read_err;
    int n_pops, n_drops;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_export = new("apb_export", this);
        adc_export = new("adc_export", this);
        reset_model();
    endfunction

    // reset values from the register map
    function void reset_model();
        foreach (shadow[i]) shadow[i] = 8'h00;
        shadow[TMR_LOAD]   = 8'hFF;
        shadow[TMR_CMP]    = 8'h80;
        shadow[ADC_SMP]    = 8'h04;
        shadow[ADC_THR_HI] = 8'hFF;
        shadow[ID_REG]     = 8'hA8;
        fifo_q.delete();
        pend.delete();
    endfunction

    // ------------------------------------------------------------------
    // ADC result arrived
    // ------------------------------------------------------------------
    function void write_adc(adc_conv_item t);
        bit [7:0] exp;
        if (t.valid_pred) begin
            exp = code_of_mv(t.held_mv);
            if (t.result !== exp || t.ch !== t.sample_ch) begin
                n_conv_err++;
                `uvm_error("SB_ADC", $sformatf("ADC result %02h on ch%0d, expected %02h on ch%0d (held %0d mV)",
                           t.result, t.ch, exp, t.sample_ch, t.held_mv))
            end else begin
                n_conv_ok++;
            end
        end
        pend.push_back(t);
    endfunction

    // move results that happened BEFORE time 'now' into the FIFO model
    function void apply_pending(time now);
        adc_conv_item t;
        while (pend.size() > 0 && pend[0].stamp < now) begin
            t = pend.pop_front();
            if (fifo_q.size() < 8) fifo_q.push_back({t.ch, t.result});
            else                   n_drops++;       // FIFO full: dropped
        end
    endfunction

    function void check_read(string name, bit [7:0] got, bit [7:0] exp, bit [7:0] mask = 8'hFF);
        n_reads++;
        if ((got & mask) !== (exp & mask)) begin
            n_read_err++;
            `uvm_error("SB_REG", $sformatf("read %s = %02h, expected %02h (mask %02h)",
                       name, got, exp, mask))
        end
    endfunction

    // ------------------------------------------------------------------
    // bus transfer arrived
    // ------------------------------------------------------------------
    function void write_apb(apb_item t);
        bit [9:0] front;
        bit [7:0] exp;

        apply_pending(t.stamp);

        if (t.write) begin
            // ---- update the shadow copy of RW registers ----
            case (t.addr)
                TMR_CTRL  : shadow[TMR_CTRL] = t.wdata & 8'h03;
                ADC_CTRL  : shadow[ADC_CTRL] = t.wdata & 8'h3D;   // START reads 0
                IRQ_EN    : shadow[IRQ_EN]   = t.wdata & 8'h3F;
                TMR_PRESC, TMR_LOAD, TMR_CMP, ADC_SMP, ADC_DIV,
                ADC_THR_LO, ADC_THR_HI:
                            shadow[t.addr]   = t.wdata;
                default   : ;                                     // RO / W1C
            endcase
            return;
        end

        // ---- reads ----
        case (t.addr)
            // EN can be cleared by hardware (one-shot): check ONESHOT only
            TMR_CTRL : check_read("TMR_CTRL", t.rdata, shadow[TMR_CTRL], 8'h02);
            TMR_PRESC, TMR_LOAD, TMR_CMP, ADC_CTRL, ADC_SMP, ADC_DIV,
            ADC_THR_LO, ADC_THR_HI, IRQ_EN:
                       check_read($sformatf("reg%0h", t.addr), t.rdata, shadow[t.addr]);
            ID_REG   : check_read("ID", t.rdata, 8'hA8);

            ADC_DATA : begin
                if (fifo_q.size() == 0) begin
                    check_read("ADC_DATA(empty)", t.rdata, 8'h00);
                end else begin
                    front = fifo_q.pop_front();
                    n_pops++;
                    check_read("ADC_DATA", t.rdata, front[7:0]);
                end
            end

            ADC_RCH  : begin
                if (fifo_q.size() == 0) exp = 8'h00;
                else                    exp = {1'b1, 5'b0, fifo_q[0][9:8]};
                check_read("ADC_RCH", t.rdata, exp);
            end

            ADC_STAT : begin
                // BUSY (bit 6) is timing-dependent: not checked here
                exp = {2'b00, (fifo_q.size() == 8), (fifo_q.size() == 0), 4'(fifo_q.size())};
                check_read("ADC_STAT", t.rdata, exp, 8'hBF);
            end

            default  : ;    // TMR_CNT, IRQ_STAT: checked by sequences / SVA
        endcase
    endfunction

    // ------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf({"\n----------------- SCOREBOARD -----------------",
                  "\n conversions checked : %0d   (errors %0d)",
                  "\n register reads      : %0d   (errors %0d)",
                  "\n FIFO pops checked   : %0d",
                  "\n results dropped     : %0d   (FIFO full)",
                  "\n----------------------------------------------"},
                  n_conv_ok + n_conv_err, n_conv_err, n_reads, n_read_err, n_pops, n_drops), UVM_NONE)
    endfunction
endclass
