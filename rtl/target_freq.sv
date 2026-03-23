`include "fixed.sv"

module target_freq #(
    parameter WINDOW_SIZE = 1024,
    parameter WBITS = $clog2(WINDOW_SIZE)
)(
    input clk,
    input rst,
    input i_rxd,
    input [WBITS-1:0] i_period,
    output o_shift_ratio // TODO fill in type/bitwidth once determined
);

// ----------------------------------------------------------------
// Internal Signals
// ---------------------------------------------------------------

wire note_on_trigger;
wire [6:0] note_number;
wire [6:0] velocity;

fixed_t frequency;

// ----------------------------------------------------------------
// MIDI Receiver
// ---------------------------------------------------------------
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
// ---------------------------------------------------------------
midi_freq_lut lut0 (
    .note(note_number),
    .frequency(frequency)
);

// ----------------------------------------------------------------
// Note Selection / Shift ratio
// ---------------------------------------------------------------

// TODO: this logic needs to be written still



endmodule