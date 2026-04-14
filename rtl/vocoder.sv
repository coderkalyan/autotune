`timescale 1ns / 1ps

`include "fixed.sv"

// a_att: float = 1.0 - np.exp(-1.0 / (attack_ms  * 1e-3 * fs))
// a_rel: float = 1.0 - np.exp(-1.0 / (release_ms * 1e-3 * fs))
module vocoder #(
    parameter int N = 30946,
    // parameter int B = $clog2(N),
    parameter int IDX_N = 89,
    // parameter int IDX_B = $clog2(IDX_N),
    parameter int attack_ms = 3,  //alpha attack
    parameter int release_ms = 100  //alpha attack
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            i_valid,
    input  wire    [127:0] i_notes,
    output fixed_t         o_data,
    output audio_t         o_raw,
    output logic           o_valid
);
    audio_t rom[N];
    audio_t idx_rom[IDX_N];
    // initial $readmemh("sawtooth440.mem", rom);
    //first note is A0 MIDI 21
    //A4 is MIDI 69
    // initial $readmemh("sawtooth_total.mem", rom);
    // initial $readmemh("sawtooth_start_idx.mem", idx_rom);
  // initial $readmemh("sawtooth440.mem", rom);
  //first note is G#2 MIDI 44
  //A4 is MIDI 69
  // initial $readmemh("sawtooth_total.mem", rom);
  // initial $readmemh("sawtooth_start_idx.mem", idx_rom);
  initial $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/sawtooth_total.mem", rom);
  initial
    $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/sawtooth_start_idx.mem", idx_rom);

  localparam int NOTE_OFFSET = 44;

  typedef enum logic [1:0] {
    IDLE,
    SYNTH,
    OUTPUT
  } state_t;

  state_t state;
  logic [7:0] note;
  fixed_t sample;
  int i;
  logic [16:0] indices[40];
  always_ff @(posedge clk) begin
    if (rst) begin
      state   <= IDLE;
      o_valid <= 1'b0;

      for (i = 0; i < 40; i = i + 1) indices[i] <= idx_rom[i];
    end else begin
      case (state)
        IDLE: begin
          if (i_valid) begin
            state  <= SYNTH;
            note   <= 0;
            sample <= 0;
          end
        end
        SYNTH: begin
          if (note != 7'd127) begin
            if (i_notes[note]) begin
              sample <= sample + (fixed_atof(rom[indices[note-NOTE_OFFSET]]) >> 7);
              indices[note - NOTE_OFFSET] <= (indices[note - NOTE_OFFSET] == idx_rom[note - NOTE_OFFSET + 1] - 1) ? idx_rom[note - NOTE_OFFSET] : indices[note - NOTE_OFFSET] + 1;
            end

            note <= note + 7'd1;
          end else begin
            state   <= OUTPUT;
            o_data  <= sample;
            o_valid <= 1'b1;
          end
        end
        OUTPUT: begin
          state   <= IDLE;
          o_valid <= 1'b0;
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
