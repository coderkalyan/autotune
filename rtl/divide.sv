`include "fixed.sv"

// Goldschmidt iterative divider for Q11.16 fixed-point.
//
// Algorithm:
//   1. Normalize |i_den| into [0.5, 1.0) by right-shifting both operands by
//      the same amount s (preserving the ratio N/D).
//   2. Iterate: F = 2 - D;  N = N*F;  D = D*F
//      D converges to 1, so N converges to N_orig / D_orig.
//   3. Apply sign and output.
//
// Each ITER cycle uses two concurrent 27x27 multiplications → 2 DSP blocks.
// Latency: 1 (normalize) + NITERS (iterations) + 1 (output) = 7 cycles.
//
// Constraints: |i_den| >= 2^(-16) (i.e. D >= LSB). Division by zero produces
// undefined output.

module divide (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_num,
    input  fixed_t i_den,
    input  wire    i_valid,
    output fixed_t o_result,
    output logic   o_valid,
    output logic   o_busy
);
    localparam int     NITERS = 5;
    localparam fixed_t TWO    = `FIXED_RTOF(2.0);

    typedef enum logic [1:0] { IDLE, ITER, DONE } state_t;
    state_t state;

    fixed_t     n, d;
    logic       sign_out;
    logic [2:0] iter;

    fixed_t     den_abs, num_abs;
    logic [3:0] shift;

    always_comb begin
        den_abs = i_den[26] ? -i_den : i_den;
        num_abs = i_num[26] ? -i_num : i_num;
        if      (den_abs[25]) shift = 4'd10;
        else if (den_abs[24]) shift = 4'd9;
        else if (den_abs[23]) shift = 4'd8;
        else if (den_abs[22]) shift = 4'd7;
        else if (den_abs[21]) shift = 4'd6;
        else if (den_abs[20]) shift = 4'd5;
        else if (den_abs[19]) shift = 4'd4;
        else if (den_abs[18]) shift = 4'd3;
        else if (den_abs[17]) shift = 4'd2;
        else if (den_abs[16]) shift = 4'd1;
        else                   shift = 4'd0;
    end

    assign o_busy = (state != IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            o_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    o_valid <= 1'b0;
                    if (i_valid) begin
                        n        <= num_abs >>> shift;
                        d        <= den_abs >>> shift;
                        sign_out <= i_num[26] ^ i_den[26];
                        iter     <= 3'd0;
                        state    <= ITER;
                    end
                end
                ITER: begin
                    n    <= fixed_mul(n, TWO - d);
                    d    <= fixed_mul(d, TWO - d);
                    iter <= iter + 3'd1;
                    if (iter == NITERS - 1) state <= DONE;
                end
                DONE: begin
                    o_result <= sign_out ? -n : n;
                    o_valid  <= 1'b1;
                    state    <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
