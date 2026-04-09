`include "fixed.sv"

module target_freq #(
    parameter WINDOW_SIZE = 1024,
    parameter WBITS = $clog2(WINDOW_SIZE)
)(
    input clk,
    input rst,
    input i_rxd,
    input [WBITS-1:0] i_period,
    output fixed_t o_shift_ratio,
    output [9:0] o_target_lag,
    output mode_t o_mode
);

// ----------------------------------------------------------------
// Internal Signals
// ----------------------------------------------------------------

wire note_on_trigger;
wire [6:0] note_number;
wire [6:0] velocity;

// ----------------------------------------------------------------
// MIDI Receiver
// ----------------------------------------------------------------
midi_receiver midi_receiver0(
    .clk(clk),
    .rst(rst),
    .midi_rx(i_rxd),
    .note_on_trigger(note_on_trigger),
    .note_number(note_number),
    .velocity(velocity),
    .mode(o_mode)
);

// ----------------------------------------------------------------
// Frequency LUT 
// ----------------------------------------------------------------
midi_lag_lut lut0 ( 
    .i_midi(note_number),
    .o_lag(o_target_lag) 
);

// ----------------------------------------------------------------
// Note Selection / Shift ratio
// ----------------------------------------------------------------
note_selection iNS(
    .actual_lag(i_period),
    .target_lag(o_target_lag),
    .shift_ratio(o_shift_ratio),
    .mode(o_mode)
);

endmodule