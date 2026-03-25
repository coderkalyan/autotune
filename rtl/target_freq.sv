`include "fixed.sv"

module target_freq #(
    parameter WINDOW_SIZE = 1024,
    parameter WBITS = $clog2(WINDOW_SIZE)
)(
    input clk,
    input rst,
    input i_rxd,
    input [WBITS-1:0] i_period,
    output fmac_t o_shift_ratio 
);

// ----------------------------------------------------------------
// Internal Signals
// ----------------------------------------------------------------

wire note_on_trigger;
wire [6:0] note_number;
wire [6:0] velocity;
wire [9:0] target_lag;

// ----------------------------------------------------------------
// MIDI Receiver
// ----------------------------------------------------------------
midi_receiver midi_receiver0(
    .clk(clk),
    .rst(rst),
    .midi_rx(rxd),
    .note_on_trigger(note_on_trigger),
    .note_number(note_number),
    .velocity(velocity)
);

// ----------------------------------------------------------------
// Frequency LUT 
// ----------------------------------------------------------------
midi_freq_lut lut0 (
    .note(note_number),
    .frequency(target_lag)
);

// ----------------------------------------------------------------
// Note Selection / Shift ratio
// ----------------------------------------------------------------
note_selection iNS(
    .actual_lag(i_period),
    .target_lag(target_lag),
    .shift_ratio(o_shift_ratio)
);

endmodule