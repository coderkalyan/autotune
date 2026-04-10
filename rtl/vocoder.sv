`timescale 1ns / 1ps

`include "fixed.sv"

// a_att: float = 1.0 - np.exp(-1.0 / (attack_ms  * 1e-3 * fs))
// a_rel: float = 1.0 - np.exp(-1.0 / (release_ms * 1e-3 * fs))
module vocoder #(
    parameter int N = 1091,
    parameter int B = $clog2(N),
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
    initial $readmemh("sawtooth.mem", rom);

    logic [15:0] idx;

    always_ff @(posedge clk) begin
        if (rst) begin
            o_valid <= 1'b0;
            idx     <= '0;
        end else begin
            o_valid <= i_valid;
            if (i_valid) begin
                idx <= ((idx >= (N - 1))) ? '0 : (idx + 1);
            end
        end
    end

    // assign o_data = rom[idx];
    assign o_data = fixed_atof(rom[idx]) >> 3;
    // assign o_raw = rom[idx];
    assign o_raw  = idx;


    // initial $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/hanning.mem", rom);

endmodule
