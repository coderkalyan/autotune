`include "../fixed.sv"

module autocorrelation_sim_mod #(
    parameter int WBITS = 10
) (
    input  logic             clk,
    input  logic             rst,
    input  logic [WBITS-1:0] i_lag,
    input  logic             i_en,
    input  fixed_t           i_xdata,
    input  fixed_t           i_ydata,
    output logic [WBITS-1:0] o_yaddr,
    output fmac_t            o_result,
    output logic             o_done
);

    localparam int WINDOW_SIZE = 1024;

    logic active;
    fmac_t count;
    fmac_t result_r;
    logic done_r;

    assign o_yaddr  = count;
    assign o_result = result_r;
    assign o_done   = done_r;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            active    <= 1'b0;
            count     <= '0;
            result_r  <= '0;
            done_r    <= 1'b0;
        end else begin
            // default: done is a 1-cycle pulse
            done_r <= 1'b0;

            if (!active) begin
                if (i_en) begin
                    active   <= 1'b1;
                    count    <= '0;
                    result_r <= '0;
                end
            end else begin
                if (count == WINDOW_SIZE-1) begin
                    done_r   <= 1'b1;
                    result_r <= fmac_t'(i_lag); // dummy result
                    active   <= 1'b0;
                    count    <= '0;
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end

endmodule