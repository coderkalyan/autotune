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
    input  wire    clk,
    input  wire    rst,
    input  wire    i_valid,
    output fixed_t o_data,
    output audio_t o_raw,
    output logic   o_valid
);
    audio_t rom[N];
    audio_t idx_rom[IDX_N];
    // initial $readmemh("sawtooth440.mem", rom);
    //first note is A0 MIDI 21
    //A4 is MIDI 69
    initial $readmemh("sawtooth_total.mem", rom);
    initial $readmemh("sawtooth_start_idx.mem", idx_rom);

    logic [16:0] idx;
    logic [16:0] idx2;
    logic [16:0] note;

    always_ff @(posedge clk) begin
        if (rst) begin
            o_valid <= 1'b0;
            idx     <= idx_rom[25];
            idx2     <= idx_rom[29];
        end else begin
            o_valid <= i_valid;
            if (i_valid) begin
                idx <= ((idx >= (idx_rom[26] - 1))) ? idx_rom[25] : (idx + 1);
                idx2 <= ((idx2 >= (idx_rom[30] - 1))) ? idx_rom[29] : (idx2 + 1);
            end
        end
    end

    // assign o_data = rom[idx];
    assign o_data = (fixed_atof(rom[idx]) >> 4) + (fixed_atof(rom[idx2] >> 4));
    // assign o_raw = rom[idx];
    assign o_raw  = idx;


    // initial $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/hanning.mem", rom);

endmodule
