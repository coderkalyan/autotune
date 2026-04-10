module vad #(
    parameter int WINDOW_SIZE = 512,
    parameter int WBITS = $clog2(WINDOW_SIZE),
    parameter int MAX_PERIODS = 10
) (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    output logic   o_active,
    output logic   o_voiced
);
  localparam int ZC_THRESHOLD = MAX_PERIODS * 8;
  localparam int ENERGY_THRESHOLD = 0;  // 200000;

  logic [WBITS - 1:0] count, zero_count;
  logic [27 + WBITS - 1:0] energy;
  fixed_t prev;
  wire min_energy = (energy >> 16) > ENERGY_THRESHOLD;
  always_ff @(posedge clk) begin
    if (rst) begin
      count      <= '0;
      zero_count <= '0;
      prev       <= 0;
      o_active   <= 1'b0;
      o_voiced   <= 1'b0;
      energy     <= 0;
    end else if (i_valid) begin
      // Increment the window counter, and check for zero crossing.
      count  <= count + 1;
      prev   <= i_data;
      energy <= energy + fixed_mul(i_data, i_data);
      if (prev[26] != i_data[26]) begin
        zero_count <= zero_count + 1;
      end

      // At the end of a window, check for voiced.
      if (count == (WINDOW_SIZE - 1)) begin
        o_active   <= min_energy;
        o_voiced   <= 1'b1;  // min_energy && (zero_count < ZC_THRESHOLD);
        zero_count <= 0;
        energy     <= 0;
      end
    end
  end
endmodule

