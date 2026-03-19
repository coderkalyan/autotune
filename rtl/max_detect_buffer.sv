module max_detect_buffer #(
  parameter int P24_BIT = 1,
  parameter int DATA_WIDTH = (P24_BIT ? 24 : 16)
) (
  input logic i_clk,
  input logic i_rst,
  input logic i_wr_en,
  input logic [DATA_WIDTH-1:0] i_wr_data,
  input logic [2:0] i_seg, // which segment to get the max from
  output logic [DATA_WIDTH-1:0] o_max_data
);
  logic [DATA_WIDTH-1:0] maximums [0:4];
  logic [2:0] curr_seg;
  logic [7:0] counter;

  always_ff @(posedge i_clk) begin
    if (i_rst) begin
      for (int i = 0; i < 5; i++) maximums[i] = '0;
      curr_seg <= '0;
      counter <= '0;
    end
    else begin
      if (i_wr_en) begin
        if (i_wr_data > maximums[curr_seg]) begin
          maximums[curr_seg] <= i_wr_data;
        end
        if (counter == 255) begin
          curr_seg <= curr_seg === 4 ? 0 : curr_seg + 1;
        end
        counter <= counter + 1;
      end
    end
  end

  assign o_max_data = maximums[i_seg];

endmodule
