`include "fixed.sv"

import global_enums::mode_t;

module uart_tx_wrapper (
    input clk,
    input rst,
    input [9:0] ir_pitch_period,
    input ir_pitch_valid,
    input logic [32*27-1:0] i_vocode_bands_flat,
    input mode_t i_mode,
    input i_vad_active,
    input i_vad_voiced,
    input i_dac_full,
    input i_adc_empty,
    input i_config_done,
    input i_config_err,
    input i_pitch_done,
    output reg o_transmission_done,
    output o_tx
);

localparam int NUM_BYTES = 128;
// 128 bytes × 7 data bits per byte (MSB is start/continuation bit)
localparam int PAYLOAD_BITS = NUM_BYTES * 7;  // 896

// Payload layout (896 bits, MSB first):
//   [895:886] 10-bit lag
//   [885]     1-bit  autocorrelation confidence
//   [884:21]  32 × 27-bit fixed_t vocode bands
//   [20:19]   2-bit  mode
//   [18]      vad_active
//   [17]      vad_voiced
//   [16]      dac_full
//   [15]      adc_empty
//   [14]      config_done
//   [13]      config_err
//   [12:0]    padding

typedef enum reg [1:0] {IDLE, INIT, SENDING} state_t;
state_t state, next_state;

logic tx_done;
logic tmrt;
logic [7:0] eff_data;
logic [6:0] cnt;

logic [PAYLOAD_BITS-1:0] shift_reg;

// Assemble payload combinationally
logic [PAYLOAD_BITS-1:0] payload;
always_comb begin
    payload[895:886] = ir_pitch_period;
    payload[885]     = ir_pitch_valid;
    for (int j = 0; j < 32; j++)
        payload[884 - j*27 -: 27] = i_vocode_bands_flat[j*27 +: 27];
    payload[20:19]   = i_mode;
    payload[18]      = i_vad_active;
    payload[17]      = i_vad_voiced;
    payload[16]      = i_dac_full;
    payload[15]      = i_adc_empty;
    payload[14]      = i_config_done;
    payload[13]      = i_config_err;
    payload[12:0]    = 13'd0;
end

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
        shift_reg <= payload;
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
