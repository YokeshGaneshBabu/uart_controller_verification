`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum bit [1:0] {
    NONE = 2'b00,
    EVEN = 2'b01,
    ODD  = 2'b10
} parity_mode_e;

// ============================================================
// uart_seq_item 
// ============================================================
class uart_seq_item extends uvm_sequence_item;
    rand bit [7:0]     data;
    rand parity_mode_e parity_mode;
    rand int           baud_rate;

    constraint c_baud   { baud_rate inside {9600, 115200}; }
    constraint c_parity { parity_mode inside {NONE, EVEN, ODD}; }

    `uvm_object_utils_begin(uart_seq_item)
        `uvm_field_int(data,                        UVM_ALL_ON)
        `uvm_field_enum(parity_mode_e, parity_mode, UVM_ALL_ON)
        `uvm_field_int(baud_rate,                   UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "uart_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("data=0x%0h parity=%s baud=%0d",
                          data, parity_mode.name(), baud_rate);
    endfunction
endclass

// ============================================================
// uart_config
// ============================================================
class uart_config extends uvm_object;
    int current_baud = 115200;
    `uvm_object_utils(uart_config)
    function new(string name = "uart_config");
        super.new(name);
    endfunction
endclass

// ============================================================
// uart_sequences 
// ============================================================
class uart_rand_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_rand_seq)
    int num_pkts = 20;
    function new(string name = "uart_rand_seq");
        super.new(name);
    endfunction
    task body();
        uart_seq_item req;
        repeat(num_pkts) begin
            req = uart_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize()) `uvm_fatal("SEQ","rand failed")
            finish_item(req);
        end
    endtask
endclass

class uart_directed_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_directed_seq)
    function new(string name = "uart_directed_seq");
        super.new(name);
    endfunction
    task body();
        uart_seq_item req;

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'h00; parity_mode==EVEN; baud_rate==115200;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'hFF; parity_mode==ODD; baud_rate==115200;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'hAA; parity_mode==NONE; baud_rate==115200;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'h55; parity_mode==EVEN; baud_rate==115200;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'h00; parity_mode==NONE; baud_rate==9600;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'hFF; parity_mode==EVEN; baud_rate==9600;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'hAA; parity_mode==ODD; baud_rate==9600;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);

        req = uart_seq_item::type_id::create("req"); start_item(req);
        if (!req.randomize() with {data==8'h55; parity_mode==ODD; baud_rate==9600;}) `uvm_fatal("SEQ","rand failed")
        finish_item(req);
    endtask
endclass

class uart_b2b_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_b2b_seq)
    function new(string name = "uart_b2b_seq");
        super.new(name);
    endfunction
    task body();
        uart_seq_item req;
        repeat(10) begin
            req = uart_seq_item::type_id::create("req"); start_item(req);
            if (!req.randomize() with {baud_rate==115200;}) `uvm_fatal("SEQ","rand failed")
            finish_item(req);
        end
    endtask
endclass

// ============================================================
// uart_sequencer
// ============================================================
class uart_sequencer extends uvm_sequencer #(uart_seq_item);
    `uvm_component_utils(uart_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

// ============================================================
// uart_driver
// ============================================================
class uart_driver extends uvm_driver #(uart_seq_item);

    virtual uart_if  vif;
    uart_config      cfg;
    uvm_analysis_port #(uart_seq_item) drv_ap;

    `uvm_component_utils(uart_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv_ap = new("drv_ap", this);
        if (!uvm_config_db#(virtual uart_if)::get(this,"","vif",vif))
            `uvm_fatal("DRV","vif not found")
        if (!uvm_config_db#(uart_config)::get(this,"","cfg",cfg))
            `uvm_fatal("DRV","cfg not found")
    endfunction

    task run_phase(uvm_phase phase);
        uart_seq_item req;

        // initialize DUT inputs to safe values
        vif.cb.tx_valid  <= 1'b0;
        vif.cb.tx_data   <= 8'h00;
        vif.cb.parity_sel <= 2'b00;
        vif.cb.baud_sel   <= 2'b01;

        @(posedge vif.rst_n);
        repeat(5) @(vif.cb);

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("DRV", req.convert2string(), UVM_MEDIUM)

            // update shared config so monitor knows baud rate
            cfg.current_baud = req.baud_rate;

            // broadcast to scoreboard before driving
            drv_ap.write(req);

            // load DUT inputs
            vif.cb.tx_data    <= req.data;
            vif.cb.parity_sel <= req.parity_mode;
            vif.cb.baud_sel   <= (req.baud_rate == 9600) ? 2'b00 : 2'b01;

            // pulse tx_valid for 1 cycle to start transmission
            @(vif.cb);
            vif.cb.tx_valid <= 1'b1;
            @(vif.cb);
            vif.cb.tx_valid <= 1'b0;

            // wait for DUT to finish transmitting
            // tx_busy goes high immediately, returns low when done
            @(posedge vif.cb.tx_busy);  // wait for busy to assert
            @(negedge vif.cb.tx_busy);  // wait for busy to deassert

            // small gap between frames
            repeat(5) @(vif.cb);

            seq_item_port.item_done();
        end
    endtask
endclass

// ============================================================
// uart_monitor
// ============================================================
class uart_monitor extends uvm_monitor;

    virtual uart_if  vif;
    uart_config      cfg;
    uvm_analysis_port #(uart_seq_item) ap;

    `uvm_component_utils(uart_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual uart_if)::get(this,"","vif",vif))
            `uvm_fatal("MON","vif not found")
        if (!uvm_config_db#(uart_config)::get(this,"","cfg",cfg))
            `uvm_fatal("MON","cfg not found")
    endfunction

    task run_phase(uvm_phase phase);
        uart_seq_item captured;
        @(posedge vif.rst_n);
        repeat(5) @(vif.cb);

        forever begin
            // wait for uart_rx DUT to assert rx_done (frame received)
            @(posedge vif.cb.rx_done);

            captured = uart_seq_item::type_id::create("captured");
            captured.data        = vif.cb.rx_data;
            captured.parity_mode = EVEN;  // informational
            captured.baud_rate   = cfg.current_baud;

            // check what the DUT itself flagged
            if (vif.cb.rx_parity_err)
                `uvm_info("MON", $sformatf("DUT flagged PARITY ERROR on data=0x%0h",
                           vif.cb.rx_data), UVM_LOW)

            if (vif.cb.rx_frame_err)
                `uvm_error("MON", $sformatf("DUT flagged FRAMING ERROR on data=0x%0h",
                            vif.cb.rx_data))

            ap.write(captured);
            `uvm_info("MON", captured.convert2string(), UVM_MEDIUM)
        end
    endtask
endclass

// ============================================================
// uart_agent 
// ============================================================
class uart_agent extends uvm_agent;
    uart_driver    drv;
    uart_sequencer seqr;
    uart_monitor   mon;

    `uvm_component_utils(uart_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv  = uart_driver::type_id::create("drv",  this);
        seqr = uart_sequencer::type_id::create("seqr", this);
        mon  = uart_monitor::type_id::create("mon",  this);
    endfunction

    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass

// ============================================================
// uart_scoreboard 
// ============================================================
`uvm_analysis_imp_decl(_drv)
`uvm_analysis_imp_decl(_mon)

class uart_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp_drv #(uart_seq_item, uart_scoreboard) drv_export;
    uvm_analysis_imp_mon #(uart_seq_item, uart_scoreboard) mon_export;

    uart_seq_item expected_q[$];
    int pass_count = 0;
    int fail_count = 0;

    `uvm_component_utils(uart_scoreboard)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv_export = new("drv_export", this);
        mon_export = new("mon_export", this);
    endfunction

    function void write_drv(uart_seq_item item);
        expected_q.push_back(item);
    endfunction

    function void write_mon(uart_seq_item received);
        uart_seq_item expected;
        if (expected_q.size() == 0) begin
            `uvm_error("SB","Received item but expected queue is empty")
            return;
        end
        expected = expected_q.pop_front();
        if (received.data === expected.data) begin
            pass_count++;
            `uvm_info("SB", $sformatf("PASS: sent=0x%0h got=0x%0h baud=%0d parity=%s",
                       expected.data, received.data,
                       expected.baud_rate, expected.parity_mode.name()), UVM_MEDIUM)
        end else begin
            fail_count++;
            `uvm_error("SB", $sformatf("FAIL: sent=0x%0h got=0x%0h",
                        expected.data, received.data))
        end
    endfunction

    function void check_phase(uvm_phase phase);
        if (expected_q.size() != 0)
            `uvm_error("SB", $sformatf("%0d items sent but never received", expected_q.size()))
        `uvm_info("SB", $sformatf("RESULT: %0d PASS  %0d FAIL", pass_count, fail_count), UVM_NONE)
    endfunction
endclass

// ============================================================
// uart_coverage 
// ============================================================
class uart_coverage extends uvm_subscriber #(uart_seq_item);
    `uvm_component_utils(uart_coverage)
    uart_seq_item item;

    covergroup uart_cg;
        cp_baud: coverpoint item.baud_rate {
            bins baud_9600   = {9600};
            bins baud_115200 = {115200};
        }
        cp_parity: coverpoint item.parity_mode {
            bins parity_none = {NONE};
            bins parity_even = {EVEN};
            bins parity_odd  = {ODD};
        }
        cp_data: coverpoint item.data {
            bins all_zeros = {8'h00};
            bins all_ones  = {8'hFF};
            bins alt_AA    = {8'hAA};
            bins alt_55    = {8'h55};
            bins others    = default;
        }
        cx_baud_parity: cross cp_baud, cp_parity;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        uart_cg = new();
    endfunction

    function void write(uart_seq_item t);
        item = t;
        uart_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("Functional Coverage = %.2f%%",
                   uart_cg.get_coverage()), UVM_NONE)
    endfunction
endclass

// ============================================================
// uart_env 
// ============================================================
class uart_env extends uvm_env;
    uart_agent      agent;
    uart_scoreboard sb;
    uart_coverage   cov;

    `uvm_component_utils(uart_env)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = uart_agent::type_id::create("agent", this);
        sb    = uart_scoreboard::type_id::create("sb",  this);
        cov   = uart_coverage::type_id::create("cov",  this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.drv.drv_ap.connect(sb.drv_export);
        agent.mon.ap.connect(sb.mon_export);
        agent.drv.drv_ap.connect(cov.analysis_export);
    endfunction
endclass

// ============================================================
// uart_test
// ============================================================
class uart_rand_test extends uvm_test;
    `uvm_component_utils(uart_rand_test)
    uart_env    env;
    uart_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = uart_config::type_id::create("cfg");
        uvm_config_db#(uart_config)::set(this, "*", "cfg", cfg);
        env = uart_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        uart_rand_seq seq;
        phase.raise_objection(this);
        seq = uart_rand_seq::type_id::create("seq");
        seq.num_pkts = 20;
        seq.start(env.agent.seqr);
        #500;
        phase.drop_objection(this);
    endtask
endclass

class uart_directed_test extends uvm_test;
    `uvm_component_utils(uart_directed_test)
    uart_env    env;
    uart_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = uart_config::type_id::create("cfg");
        uvm_config_db#(uart_config)::set(this, "*", "cfg", cfg);
        env = uart_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        uart_directed_seq dseq;
        uart_rand_seq     rseq;
        phase.raise_objection(this);
        dseq = uart_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.seqr);
        rseq = uart_rand_seq::type_id::create("rseq");
        rseq.num_pkts = 20;
        rseq.start(env.agent.seqr);
        #500;
        phase.drop_objection(this);
    endtask
endclass

class uart_b2b_test extends uvm_test;
    `uvm_component_utils(uart_b2b_test)
    uart_env    env;
    uart_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = uart_config::type_id::create("cfg");
        uvm_config_db#(uart_config)::set(this, "*", "cfg", cfg);
        env = uart_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        uart_b2b_seq seq;
        phase.raise_objection(this);
        seq = uart_b2b_seq::type_id::create("seq");
        seq.start(env.agent.seqr);
        #500;
        phase.drop_objection(this);
    endtask
endclass

// ============================================================
// tb_top
// ============================================================
module tb_top;

    logic clk;
    logic rst_n;

    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
    end

    uart_if u_if (.clk(clk));
    assign u_if.rst_n = rst_n;

    // ---- uart_tx DUT ----
    uart_tx dut_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_valid   (u_if.tx_valid),
        .tx_data    (u_if.tx_data),
        .parity_sel (u_if.parity_sel),
        .baud_sel   (u_if.baud_sel),
        .tx_out     (u_if.tx_out),   // serial output
        .tx_busy    (u_if.tx_busy)
    );

    // ---- uart_rx DUT ----
    // rx_in connected to uart_tx's serial output
    uart_rx dut_rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_in        (u_if.tx_out),     // serial data from uart_tx
        .parity_sel   (u_if.parity_sel), // same config as tx
        .baud_sel     (u_if.baud_sel),
        .rx_data      (u_if.rx_data),
        .rx_done      (u_if.rx_done),
        .rx_parity_err(u_if.rx_parity_err),
        .rx_frame_err (u_if.rx_frame_err)
    );

    // SVA monitors the serial TX line and RX line
    assign u_if.tx = u_if.tx_out;  // for SVA monitoring
    assign u_if.rx = u_if.tx_out;  // for SVA monitoring

    bind tb_top uart_sva sva_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .tx    (u_if.tx_out),
        .rx    (u_if.tx_out)
    );

    initial begin
        uvm_config_db#(virtual uart_if)::set(null, "*", "vif", u_if);
    end

    initial begin
        run_test();
    end

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, tb_top);
    end

endmodule