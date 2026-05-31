// ============================================================
// uart_if.sv
// ============================================================
`ifndef UART_IF_SV
`define UART_IF_SV
`timescale 1ns/1ps

interface uart_if (input logic clk);

    logic tx;        // driven by driver, goes into uart_tx DUT
    logic tx_out;    // uart_tx DUT serial output → goes into uart_rx DUT
    logic rx_out;    // uart_rx DUT recovered byte (parallel)
    logic rx;        // monitored by monitor — this is uart_tx's serial output
    logic rst_n;

    // extra signals for DUT control
    logic       tx_valid;    // pulse high to start transmission
    logic [7:0] tx_data;     // byte to transmit
    logic [1:0] parity_sel;  // 00=NONE 01=EVEN 10=ODD
    logic [1:0] baud_sel;    // 00=9600 01=115200
    logic       tx_busy;     // DUT output: high while transmitting
    logic       rx_done;     // DUT output: high for 1 cycle when byte received
    logic [7:0] rx_data;     // DUT output: received byte
    logic       rx_parity_err; // DUT output: parity error flag
    logic       rx_frame_err;  // DUT output: framing error flag

    clocking cb @(posedge clk);
        output tx_valid, tx_data, parity_sel, baud_sel;
        input  tx_busy, tx_out, rx_done, rx_data, rx_parity_err, rx_frame_err;
    endclocking

    modport driver_mp  (clocking cb, input rst_n);
    modport monitor_mp (clocking cb, input rst_n);

endinterface
`endif


// ============================================================
// uart_tx.sv
// Serializes one byte onto tx_out
// Frame: START(0) | D0..D7 | [PARITY] | STOP(1)
// ============================================================
`ifndef UART_TX_SV
`define UART_TX_SV
`timescale 1ns/1ps

module uart_tx (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_valid,   // pulse to start transmission
    input  logic [7:0] tx_data,    // byte to send
    input  logic [1:0] parity_sel, // 00=NONE 01=EVEN 10=ODD
    input  logic [1:0] baud_sel,   // 00=9600 01=115200
    output logic       tx_out,     // serial output
    output logic       tx_busy     // high while transmitting
);

    // baud divisors for 50MHz clock
    // 9600:   50_000_000/9600   = 5208
    // 115200: 50_000_000/115200 = 434
    localparam int BAUD_9600   = 5208;
    localparam int BAUD_115200 = 434;

    typedef enum logic [2:0] {
        IDLE, START, DATA, PARITY_ST, STOP
    } state_t;

    state_t     state;
    int         baud_limit;
    int         baud_cnt;
    int         bit_idx;
    logic [7:0] shift_reg;
    logic       parity_bit;

    always_comb begin
        case (baud_sel)
            2'b00:   baud_limit = BAUD_9600;
            default: baud_limit = BAUD_115200;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx_out   <= 1'b1;
            tx_busy  <= 1'b0;
            baud_cnt <= 0;
            bit_idx  <= 0;
        end else begin
            case (state)

                IDLE: begin
                    tx_out  <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_valid) begin
                        shift_reg  <= tx_data;
                        parity_bit <= (parity_sel == 2'b10) ? ~(^tx_data) : (^tx_data);
                        state      <= START;
                        baud_cnt   <= 0;
                        tx_busy    <= 1'b1;
                    end
                end

                START: begin
                    tx_out <= 1'b0;  // start bit
                    if (baud_cnt == baud_limit - 1) begin
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                DATA: begin
                    tx_out <= shift_reg[bit_idx];  // LSB first
                    if (baud_cnt == baud_limit - 1) begin
                        baud_cnt <= 0;
                        if (bit_idx == 7) begin
                            state <= (parity_sel == 2'b00) ? STOP : PARITY_ST;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                PARITY_ST: begin
                    tx_out <= parity_bit;
                    if (baud_cnt == baud_limit - 1) begin
                        baud_cnt <= 0;
                        state    <= STOP;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                STOP: begin
                    tx_out <= 1'b1;  // stop bit
                    if (baud_cnt == baud_limit - 1) begin
                        baud_cnt <= 0;
                        state    <= IDLE;
                        tx_busy  <= 1'b0;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
`endif


// ============================================================
// uart_rx.sv
// Deserializes serial input back into a byte
// Samples at mid-bit for reliability
// ============================================================
`ifndef UART_RX_SV
`define UART_RX_SV
`timescale 1ns/1ps

module uart_rx (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx_in,      // serial input (from uart_tx's tx_out)
    input  logic [1:0] parity_sel, // must match transmitter
    input  logic [1:0] baud_sel,   // must match transmitter
    output logic [7:0] rx_data,    // received byte
    output logic       rx_done,    // pulses high for 1 cycle when done
    output logic       rx_parity_err, // high if parity mismatch
    output logic       rx_frame_err   // high if stop bit not 1
);

    localparam int BAUD_9600   = 5208;
    localparam int BAUD_115200 = 434;

    typedef enum logic [2:0] {
        IDLE, START, DATA, PARITY_ST, STOP
    } state_t;

    state_t     state;
    int         baud_limit;
    int         baud_cnt;
    int         bit_idx;
    logic [7:0] shift_reg;
    logic       parity_captured;
    logic       rx_in_sync;  // synchronized input

    always_comb begin
        case (baud_sel)
            2'b00:   baud_limit = BAUD_9600;
            default: baud_limit = BAUD_115200;
        endcase
    end

    // synchronize rx_in to clk to avoid metastability
    logic rx_sync1, rx_sync2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx_in;
            rx_sync2 <= rx_sync1;
        end
    end
    assign rx_in_sync = rx_sync2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            baud_cnt       <= 0;
            bit_idx        <= 0;
            rx_data        <= 8'h00;
            rx_done        <= 1'b0;
            rx_parity_err  <= 1'b0;
            rx_frame_err   <= 1'b0;
        end else begin
            rx_done       <= 1'b0;
            rx_parity_err <= 1'b0;
            rx_frame_err  <= 1'b0;

            case (state)

                IDLE: begin
                    if (!rx_in_sync) begin
                        // falling edge = start bit detected
                        // wait half baud period to land at mid-start
                        baud_cnt <= 0;
                        state    <= START;
                    end
                end

                START: begin
                    // wait to middle of start bit to confirm it's valid
                    if (baud_cnt == (baud_limit / 2) - 1) begin
                        if (!rx_in_sync) begin
                            // valid start bit confirmed
                            baud_cnt <= 0;
                            bit_idx  <= 0;
                            state    <= DATA;
                        end else begin
                            // glitch, go back to idle
                            state <= IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                DATA: begin
                    // sample at full baud period intervals from mid-start
                    if (baud_cnt == baud_limit - 1) begin
                        shift_reg[bit_idx] <= rx_in_sync;
                        baud_cnt <= 0;
                        if (bit_idx == 7) begin
                            state <= (parity_sel == 2'b00) ? STOP : PARITY_ST;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                PARITY_ST: begin
                    if (baud_cnt == baud_limit - 1) begin
                        parity_captured <= rx_in_sync;
                        baud_cnt <= 0;
                        state    <= STOP;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                STOP: begin
                    if (baud_cnt == baud_limit - 1) begin
                        baud_cnt <= 0;
                        state    <= IDLE;
                        rx_data  <= shift_reg;
                        rx_done  <= 1'b1;

                        // check stop bit
                        if (!rx_in_sync)
                            rx_frame_err <= 1'b1;

                        // check parity if enabled
                        if (parity_sel != 2'b00) begin
                            logic exp_par;
                            exp_par = ^shift_reg;
                            if (parity_sel == 2'b10) exp_par = ~exp_par;
                            if (parity_captured !== exp_par)
                                rx_parity_err <= 1'b1;
                        end

                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
`endif


// ============================================================
// uart_sva.sv 
// ============================================================
`ifndef UART_SVA_SV
`define UART_SVA_SV
`timescale 1ns/1ps

module uart_sva (
    input logic clk,
    input logic rst_n,
    input logic tx,
    input logic rx
);
    property p_tx_no_x;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(tx);
    endproperty
    a_tx_no_x: assert property (p_tx_no_x)
        else $error("SVA FAIL: TX is unknown (X/Z) at time %0t", $time);

    property p_tx_idle_after_reset;
        @(posedge clk)
        $rose(rst_n) |-> ##[1:10] (tx === 1'b1);
    endproperty
    a_tx_idle: assert property (p_tx_idle_after_reset)
        else $error("SVA FAIL: TX did not go idle after reset at time %0t", $time);

    property p_rx_no_x;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(rx);
    endproperty
    a_rx_no_x: assert property (p_rx_no_x)
        else $error("SVA FAIL: RX is unknown (X/Z) at time %0t", $time);

    property p_frame_started;
        @(posedge clk) disable iff (!rst_n)
        $fell(tx);
    endproperty
    c_frame_started: cover property (p_frame_started);
endmodule
`endif