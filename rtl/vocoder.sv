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
    parameter int release_ms = 100,  //alpha attack
    parameter int BANKS = 32
) (
    input  wire            clk,
    input  wire            rst,
    input  wire            i_valid,
    input  fixed_t         i_data,
    input  wire    [127:0] i_notes,
    output fixed_t         o_data,
    output fnorm_t         o_vocode_bands[BANKS],
    output logic           o_valid
);
  audio_t rom[N];
  audio_t idx_rom[IDX_N];
  // initial $readmemh("sawtooth440.mem", rom);
  //first note is A0 MIDI 21
  //A4 is MIDI 69
  // initial $readmemh("sawtooth_total.mem", rom);
  // initial $readmemh("sawtooth_start_idx.mem", idx_rom);
  initial $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/sawtooth_total.mem", rom);
  initial
    $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/sawtooth_start_idx.mem", idx_rom);

  localparam int NOTE_OFFSET = 21;

  typedef enum logic [2:0] {
    IDLE,
    CARRIER_SYNTH_VOICE_BANDPASS,
    CARRIER_BANDPASS,
    VOCODE,
    OUTPUT
  } state_t;

  logic asym_follow;
  logic bandpass_i_valid, bandpass_o_valid;
  fixed_t bandpass_i_data;
  fnorm_t bandpass_o_data [BANKS * 2];
  logic [5:0] bandpass_bank_start, bandpass_bank_end;
  // 2x state banks (voice 0..31 and carrier 32..63 have independent
  // histories) but share one set of 32 coefficient ROMs — the low 5 bits
  // of bank_cnt select the coef set inside the filterbank.
  bandpass_filterbank #(
      .BANKS(BANKS * 2),
      .COEF_BANKS(BANKS)
  ) bandpass (
      .clk(clk),
      .rst(rst),
      .i_data(bandpass_i_data),
      .i_valid(bandpass_i_valid),
      .i_asym_follow(asym_follow),
      .i_bank_start(bandpass_bank_start),
      .i_bank_end(bandpass_bank_end),
      .o_data(bandpass_o_data),
      .o_valid(bandpass_o_valid)
  );

  assign o_vocode_bands = bandpass_o_data[0:31];

  state_t state;
  logic [6:0] note;
  fixed_t sample;
  int i;
  logic [16:0] indices[IDX_N];
  fixed_t carrier;
  // logic carrier_valid;
  logic bandpass_done;
  logic [5:0] bank;
  // fixed_t voice_banks[BANKS], carrier_banks[BANKS];
  always_ff @(posedge clk) begin
    if (rst) begin
      state            <= IDLE;
      o_valid          <= 1'b0;
      bandpass_i_valid <= 1'b0;
      // carrier_valid <= 1'b0;

      for (i = 0; i < IDX_N; i = i + 1) indices[i] <= idx_rom[i];
    end else begin
      case (state)
        IDLE: begin
          o_valid <= 1'b0;

          if (i_valid) begin
            state               <= CARRIER_SYNTH_VOICE_BANDPASS;
            note                <= 0;
            sample              <= 0;

            bandpass_i_data     <= i_data;
            bandpass_i_valid    <= 1'b1;
            asym_follow         <= 1'b1;
            bandpass_bank_start <= 0;
            bandpass_bank_end   <= (BANKS - 1);
            bandpass_done       <= 1'b0;
          end
        end
        CARRIER_SYNTH_VOICE_BANDPASS: begin
          // Do not re-initiate bandpass filtering on the voice input.
          bandpass_i_valid <= 1'b0;

          // Run carrier synthesis until complete.
          if (note != 7'd127) begin
            if (i_notes[note]) begin
              sample <= sample + (fixed_atof(rom[indices[note-NOTE_OFFSET]]));
              indices[note - NOTE_OFFSET] <= (indices[note - NOTE_OFFSET] == idx_rom[note - NOTE_OFFSET + 1] - 1) ? idx_rom[note - NOTE_OFFSET] : indices[note - NOTE_OFFSET] + 1;
            end

            note <= note + 7'd1;
          end

          // Latch bandpass when done.
          if (bandpass_o_valid) begin
            bandpass_done <= 1'b1;
          end

          // If both bandpass and carrier synthesis are complete, continue.
          if ((note == 7'd127) && (bandpass_done)) begin
            state               <= CARRIER_BANDPASS;

            bandpass_i_data     <= sample;
            bandpass_i_valid    <= 1'b1;
            asym_follow         <= 1'b0;
            bandpass_bank_start <= BANKS;
            bandpass_bank_end   <= (2 * BANKS) - 1;
            bandpass_done       <= 1'b0;
          end
        end
        CARRIER_BANDPASS: begin
          // Do not re-initiate bandpass filtering on the voice input.
          bandpass_i_valid <= 1'b0;

          // Wait until bandpass is done.
          if (bandpass_o_valid) begin
            state  <= VOCODE;
            bank   <= '0;
            sample <= 0;
          end
        end
        VOCODE: begin
          sample <= sample + fnorm_mul((bandpass_o_data[bank] << 16), bandpass_o_data[bank+BANKS]);
          bank <= bank + 1;

          if (bank == (BANKS - 1)) begin
            state   <= OUTPUT;
          end
        end
        OUTPUT: begin
          state   <= IDLE;
          o_data  <= fixed_t'(sample);
          o_valid <= 1'b1;
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
