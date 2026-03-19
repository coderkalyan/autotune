`timescale 1ns/1ps
`include "../fixed.sv"

// NOTE THIS IS A SANITY CHECK TESTBENCH, NOT A FULLY THOROUGH TESTBENCH. 
// It just tests basic read/write functionality of the circular buffer and 
// the increment read pointer signal. It does not test the full behavior 
// of the circular buffer (e.g. segment full signal, wrap around behavior, 
//etc.) or all edge cases.
module circular_buffer_tb2();

  localparam int READ_PORTS = 4;

  logic clk;
  logic rst;
  logic i_wr_en;
  fixed_t i_wr_data;
  logic i_inc_rd_ptr;
  logic [9:0] i_rd_addr [0:READ_PORTS-1];
  fixed_t o_data [0:READ_PORTS-1];
  logic o_seg_full;

  // DUT
  circular_buffer #(
    .READ_PORTS(READ_PORTS)
  ) dut (
    .clk(clk),
    .rst(rst),
    .i_wr_en(i_wr_en),
    .i_wr_data(i_wr_data),
    .i_inc_rd_ptr(i_inc_rd_ptr),
    .i_rd_addr(i_rd_addr),
    .o_data(o_data),
    .o_seg_full(o_seg_full)
  );

  // Clock
  initial clk = 0;
  always #5 clk = ~clk;

  // Simple task to write one sample
  task automatic write_sample(input fixed_t sample);
    begin
      @(negedge clk);
      i_wr_en   = 1'b1;
      i_wr_data = sample;
      @(negedge clk);
      i_wr_en   = 1'b0;
    end
  endtask

  // Simple task to increment read pointer
  task automatic inc_rd_ptr();
    begin
      @(negedge clk);
      i_inc_rd_ptr = 1'b1;
      @(negedge clk);
      i_inc_rd_ptr = 1'b0;
    end
  endtask

  integer k;

  initial begin
    // Init
    rst          = 1'b1;
    i_wr_en      = 1'b0;
    i_wr_data    = '0;
    i_inc_rd_ptr = 1'b0;
    for (int i = 0; i < READ_PORTS; i++) begin
      i_rd_addr[i] = '0;
    end

    // Reset
    repeat (3) @(negedge clk);
    rst = 1'b0;

    // Write some samples into buffer
    for (k = 0; k < 256; k++) begin
      write_sample(fixed_t'(k));
    end

    // Read a few addresses from current segment
    @(negedge clk);
    i_rd_addr[0] = 10'd0;
    i_rd_addr[1] = 10'd5;
    i_rd_addr[2] = 10'd10;
    i_rd_addr[3] = 10'd15;

    repeat (3) @(posedge clk);

    // Read a few more addresses
    @(negedge clk);
    i_rd_addr[0] = 10'd0;
    i_rd_addr[1] = 10'd10;
    i_rd_addr[2] = 10'd3;
    i_rd_addr[3] = 10'd15;

    repeat (3) @(posedge clk);

    // Write more samples
    for (k = 1; k < 257; k++) begin
      write_sample(fixed_t'(k));
    end

    // Change read addresses again
    @(negedge clk);
    i_rd_addr[0] = 10'd3;
    i_rd_addr[1] = 10'd15;
    i_rd_addr[2] = 10'd3;
    i_rd_addr[3] = 10'd15;

    repeat (5) @(posedge clk);

    for (k = 0; k < 512; k++) begin
      write_sample(fixed_t'(k));
    end

    // Increment read pointer
    inc_rd_ptr();
    @(negedge clk);
    i_rd_addr[0] = 10'd0;
    i_rd_addr[1] = 10'd1;
    i_rd_addr[2] = 10'd2;
    i_rd_addr[3] = 10'd3;

    repeat (5) @(posedge clk);

    $stop();
  end

endmodule