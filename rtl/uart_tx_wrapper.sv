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
    input [9:0] i_target_lag,
    // Harmony / key telemetry
    input  logic [6:0] i_melody_midi,
    input  logic [6:0] i_held_midi,
    input  logic       i_any_note_pressed,
    input  logic [3:0] i_harm_tonic,
    input  logic       i_harm_mode,
    input  logic [2:0] i_chord_state,
    input  logic       i_in_scale,
    input  logic [6:0] i_harm1_midi,
    input  logic [6:0] i_harm2_midi,
    output reg o_transmission_done,
    output o_tx
);

localparam int NUM_BYTES = 144;
// 144 bytes × 7 data bits per byte (MSB is start/continuation bit)
localparam int PAYLOAD_BITS = NUM_BYTES * 7;  // 1008

// Payload layout (1008 bits, MSB first):
//   [1007:998] 10-bit lag
//   [997]      1-bit  autocorrelation confidence
//   [996:133]  32 × 27-bit fixed_t vocode bands
//   [132:130]  3-bit  mode
//   [129]      vad_active
//   [128]      vad_voiced
//   [127]      dac_full
//   [126]      adc_empty
//   [125]      config_done
//   [124]      config_err
//   [123:114]  10-bit target_lag
//   [113:107]  7-bit melody_midi (note feeding harmony_gen)
//   [106:100]  7-bit held_midi (priority-encoder MIDI)
//   [99]       any_note_pressed
//   [98:92]    7-bit harm1_midi
//   [91:85]    7-bit harm2_midi
//   [84:81]    4-bit harm_tonic
//   [80]       harm_mode (0=major,1=minor)
//   [79:77]    3-bit chord_state
//   [76]       in_scale
//   [75:0]     padding

typedef enum reg [1:0] {IDLE, INIT, SENDING} state_t;
state_t state, next_state;

logic tx_done;
logic tmrt;
logic [7:0] eff_data;
logic [7:0] cnt;

logic [PAYLOAD_BITS-1:0] shift_reg;

// Assemble payload combinationally
logic [PAYLOAD_BITS-1:0] payload;
always_comb begin
    payload = '0;
    payload[1007:998] = ir_pitch_period;
    payload[997]      = ir_pitch_valid;
    for (int j = 0; j < 32; j++)
        payload[996 - j*27 -: 27] = i_vocode_bands_flat[j*27 +: 27];
    payload[132:130]  = i_mode;
    payload[129]      = i_vad_active;
    payload[128]      = i_vad_voiced;
    payload[127]      = i_dac_full;
    payload[126]      = i_adc_empty;
    payload[125]      = i_config_done;
    payload[124]      = i_config_err;
    payload[123:114]  = i_target_lag;
    payload[113:107]  = i_melody_midi;
    payload[106:100]  = i_held_midi;
    payload[99]       = i_any_note_pressed;
    payload[98:92]    = i_harm1_midi;
    payload[91:85]    = i_harm2_midi;
    payload[84:81]    = i_harm_tonic;
    payload[80]       = i_harm_mode;
    payload[79:77]    = i_chord_state;
    payload[76]       = i_in_scale;
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
