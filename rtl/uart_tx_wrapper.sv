module uart_tx_wrapper (
    input clk,
    input rst,
    input [9:0] ir_pitch_period,
    input ir_pitch_valid,
    input i_pitch_done,
    output reg o_transmission_done,
    output o_tx
);

localparam int NUM_BYTES = 128;
// 128 bytes × 7 data bits per byte (MSB is start/continuation bit)
localparam int PAYLOAD_BITS = NUM_BYTES * 7;  // 896

typedef enum reg [1:0] {IDLE, INIT, SENDING} state_t;
state_t state, next_state;

logic tx_done;
logic tmrt;
logic [7:0] eff_data;
logic [6:0] cnt;

logic [PAYLOAD_BITS-1:0] shift_reg;

UART_tx iTX (
    .clk(clk),
    .rst_n(~rst),
    .tmrt(tmrt),
    .tx_data(eff_data),
    .tx_done(tx_done),
    .TX(o_tx)
);

// Top 7 bits of shift register, with start bit for first byte
assign eff_data = {(cnt == 0) ? 1'b1 : 1'b0, shift_reg[PAYLOAD_BITS-1 -: 7]};

// SHIFT REGISTER AND COUNTER //
always_ff @(posedge clk) begin
    if (rst) begin
        cnt <= '0;
        shift_reg <= '0;
    end else if (state == IDLE && i_pitch_done) begin
        cnt <= '0;
        shift_reg <= {ir_pitch_valid, {(PAYLOAD_BITS - 11){1'b0}}, ir_pitch_period};
    end else if (tx_done) begin
        cnt <= cnt + 1;
        shift_reg <= shift_reg << 7;
    end
end

// FSM STATE FLOP //
always_ff @(posedge clk) begin
    if (rst)
        state <= IDLE;
    else
        state <= next_state;
end

// FSM TRANSITION LOGIC //
always_comb begin
    next_state = state;
    tmrt = 1'b0;
    o_transmission_done = 1'b0;

    case (state)
        IDLE: begin
            if (i_pitch_done)
                next_state = INIT;
        end
        INIT: begin
            tmrt = 1'b1;
            next_state = SENDING;
        end
        SENDING: begin
            if (tx_done) begin
                if (cnt == NUM_BYTES - 1) begin
                    next_state = IDLE;
                    o_transmission_done = 1'b1;
                end else begin
                    next_state = INIT;
                end
            end
        end
        default: next_state = IDLE;
    endcase
end

endmodule
