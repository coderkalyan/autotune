`timescale 1ns / 1ps

`include "fixed.sv"

// a_att: float = 1.0 - np.exp(-1.0 / (attack_ms  * 1e-3 * fs))
// a_rel: float = 1.0 - np.exp(-1.0 / (release_ms * 1e-3 * fs))
module vocoder #(
    parameter int N = 7419,  // 59359,
    // parameter int B = $clog2(N),
    parameter int IDX_N = 41,  // 89,
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
    // When asserted, emit the raw synth sum (sum of active-note ROM
    // samples) on o_data and skip the bandpass + modulation pipeline.
    input  wire            i_synth_bypass,
    output fixed_t         o_data,
    output fnorm_t         o_vocode_bands[BANKS],
    output logic           o_valid
);
  audio_t idx_rom[IDX_N];
  //first note is A0 MIDI 21
  //A4 is MIDI 69

  // BRAM-IP version (disabled — debugging whether pipeline or IP is at
  // fault). Kept for easy restore.
  // logic [14:0] audio_addr_ip;
  // audio_t rom_ip;
  // rom_16_32768 audio_rom (
  //     .address(audio_addr_ip),
  //     .clock  (clk),
  //     .q      (rom_ip)
  // );

  // Inferred synchronous ROM. 1-cycle registered read matches the IP's
  // latency, so the surrounding pipeline doesn't need to change.
  logic [14:0] audio_addr;
  audio_t rom_mem[N];
  audio_t rom;
  initial $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/carriers.mem", rom_mem);
  always_ff @(posedge clk) begin
    rom <= rom_mem[audio_addr];
  end

  initial
    $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/carrier_indices.mem", idx_rom);

  // First MIDI note represented in carrier_indices.mem. Must match the
  // lower bound used by py/carrier_romgen.py.
  localparam int NOTE_OFFSET = 44;
  // Last MIDI note represented in carrier_indices.mem (inclusive).
  // IDX_N-1 notes starting at NOTE_OFFSET.
  localparam int NOTE_LAST = NOTE_OFFSET + IDX_N - 2;

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

  logic [26:0] radical;
  logic [13:0] sqrt_out;
  sqrt sqrt (
      .radical(radical),
      .q(sqrt_out),
      .remainder()
  );

  assign radical = bandpass_o_data[bank] << 3;

  state_t state;
  // 8-bit so `note` can sit at 128 for one extra "drain" cycle after all
  // addresses have been issued but the last ROM read is still in flight.
  logic [7:0] note;
  fixed_t sample;
  int i;
  logic [16:0] indices[IDX_N];
  fixed_t carrier;
  // logic carrier_valid;
  logic bandpass_done;
  logic [5:0] bank;
  // Latched synth-bypass flag captured at sample start.
  logic bypass_r;

  // Combinational address to the ROM IP. Registered `rom` lags by 1 cycle,
  // so the read we consume on cycle k corresponds to the address issued on
  // cycle k-1 (i.e. for note-1).
  // Guard the indices read so out-of-range `note` values don't index past
  // the end of the (now smaller) indices array.
  assign audio_addr = ((note >= 8'(NOTE_OFFSET)) && (note <= 8'(NOTE_LAST)))
                      ? indices[note - NOTE_OFFSET][14:0]
                      : 15'd0;
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
            note                <= 8'd0;
            sample              <= 0;
            bypass_r            <= i_synth_bypass;

            // Only kick off the voice bandpass in full vocoder mode. In
            // synth-bypass mode the bandpass is skipped entirely.
            bandpass_i_data     <= i_data;
            bandpass_i_valid    <= ~i_synth_bypass;
            asym_follow         <= 1'b1;
            bandpass_bank_start <= 0;
            bandpass_bank_end   <= (BANKS - 1);
            bandpass_done       <= 1'b0;
          end
        end
        CARRIER_SYNTH_VOICE_BANDPASS: begin
          // Do not re-initiate bandpass filtering on the voice input.
          bandpass_i_valid <= 1'b0;

          // Accumulate rom from the address issued last cycle (for note-1).
          // Only consume when the previous MIDI note is in the synthesized
          // range [NOTE_OFFSET, NOTE_LAST].
          if ((note > 8'(NOTE_OFFSET)) && (note <= 8'(NOTE_LAST + 1)) && i_notes[note[6:0]-7'd1]) begin
            sample <= sample + (27'(rom));
          end

          // Issue the next note's address via comb `audio_addr` and advance
          // its per-note indices pointer — only for MIDI notes in
          // [NOTE_OFFSET, NOTE_LAST], which is all we have ROM entries for.
          // Notes outside the range are silently skipped.
          if ((note >= 8'(NOTE_OFFSET)) && (note <= 8'(NOTE_LAST))) begin
            if (i_notes[note[6:0]]) begin
              indices[note - NOTE_OFFSET] <= (indices[note - NOTE_OFFSET] == idx_rom[note - NOTE_OFFSET + 1] - 1) ? idx_rom[note - NOTE_OFFSET] : indices[note - NOTE_OFFSET] + 1;
            end
          end

          if (note < 8'd128) note <= note + 8'd1;

          // Latch bandpass when done.
          if (bandpass_o_valid) begin
            bandpass_done <= 1'b1;
          end

          // Transition once the last ROM read has been drained (note==128).
          // In bypass mode we skip straight to OUTPUT with the raw synth
          // sum. In full vocoder mode, wait for the voice bandpass to
          // finish and then feed the synth sum into the carrier bandpass.
          if ((note == 8'd128) && (bypass_r || bandpass_done)) begin
            if (bypass_r) begin
              sample <= (sample << 8);
              state  <= OUTPUT;
            end else begin
              state               <= CARRIER_BANDPASS;
              bandpass_i_data     <= (sample << 8);
              bandpass_i_valid    <= 1'b1;
              asym_follow         <= 1'b0;
              bandpass_bank_start <= BANKS;
              bandpass_bank_end   <= (2 * BANKS) - 1;
              bandpass_done       <= 1'b0;
            end
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
          sample <= sample + fnorm_mul(fnorm_t'(sqrt_out << 12), bandpass_o_data[bank+BANKS]);
          bank   <= bank + 1;

          if (bank == (BANKS - 1)) begin
            state <= OUTPUT;
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
