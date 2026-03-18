`include "../fixed.sv"

`define SIM
// Circular buffer for incoming data from the ADC
// 256 data points per segment, 5 segments per buffer
// 16 bit depth per data point
// 11 bits needed to address 1280 data points
module circular_buffer #(
  parameter READ_PORTS = 1
) (
  input logic clk,
  input logic rst,
  input logic i_wr_en,
  input fixed_t i_wr_data,
  input logic i_inc_rd_ptr, // increment rd_ptr by 1
  input logic [9:0] i_rd_addr [0:READ_PORTS-1], // 0-1024, translated to real address in buffer
  output fixed_t o_data [0:READ_PORTS-1],
  output logic o_seg_full
);
  localparam SEGMENT_SIZE = 256;
  localparam NUM_SEGMENTS = 5;
  localparam BUFFER_SIZE = SEGMENT_SIZE * NUM_SEGMENTS;
  localparam SEG4_BASE = 1024;
  
  logic [10:0] wr_ptr, rd_ptr; // 11 bits to address 2048 locations, but we will only use 1280 for the buffer
  logic [10:0] rd_addr[0:READ_PORTS-1];

  `ifdef SIM
  generate
    genvar k;
    for (k = 0; k < READ_PORTS; k++) begin 
      memory #(
        .DATA_WIDTH(27),
        .ADDR_WIDTH(11)
      ) memory_inst (
        .i_clk(clk),
        .i_data(i_wr_data),
        .i_wr_addr(wr_ptr),
        .i_rd_addr(rd_addr[k]),
        .i_wr_en(i_wr_en),
        .o_data(o_data[k])
      );
    end
  endgenerate
  `else
  generate
    genvar i;
    for (i = 0; i < READ_PORTS; i++) begin : PARALLEL_BRAM
      bram_27_2k bram_24_2k_inst (
        .clock(clk),
        .data(i_wr_data),
        .rdaddress(rd_addr[i]),
        .wraddress(wr_ptr),
        .wren(i_wr_en),
        .q(o_data[i])
      );
    end
  endgenerate
  `endif

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_ptr <= '0;
      wr_ptr <= '0;
    end else begin
      if (i_inc_rd_ptr) begin
        rd_ptr <= rd_ptr == SEG4_BASE ? 0 : rd_ptr + SEGMENT_SIZE;
      end
      if (i_wr_en) begin
        wr_ptr <= wr_ptr == BUFFER_SIZE - 1 ? 0 : wr_ptr + 1;
      end
    end
  end

  assign o_seg_full = wr_ptr % SEGMENT_SIZE == SEGMENT_SIZE - 1;

  always_comb begin
    integer j;
    for (int j = 0; j < READ_PORTS; j++) begin
      rd_addr[j] = (i_rd_addr[j] + rd_ptr) >= BUFFER_SIZE ? (i_rd_addr[j] + rd_ptr) - BUFFER_SIZE : (i_rd_addr[j] + rd_ptr);
    end
  end

endmodule