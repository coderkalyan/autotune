module circular_bufffer_tb();

logic clk;
logic rst;

logic i_wr_en, i_rd_en, o_data_vld, i_inc_rd_ptr;
logic [15:0] i_wr_data, o_rd_data;
logic [9:0] i_rd_addr;

circular_buffer #(
  .P24_BIT(0)
) dut(
  .clk(clk),
  .rst(rst),
  .i_wr_en(i_wr_en),
  .i_rd_en(i_rd_en),
  .i_wr_data(i_wr_data),
  .i_inc_rd_ptr(i_inc_rd_ptr),
  .i_rd_addr(i_rd_addr),
  .o_rd_data(o_rd_data),
  .o_data_vld(o_data_vld)
);

always #5 clk = ~clk;

initial begin
  clk = 0;
  rst = 1;
  i_wr_en = 0;
  i_rd_en = 0;
  i_inc_rd_ptr = 0;
  i_rd_addr = 0;
  i_wr_data = 0;

  repeat (10) @(posedge clk);
  rst = 0;

  repeat (5) @(posedge clk);

  // Write 256 samples do the buffer
  for (int i = 0; i < 256; i++) begin
    i_wr_en = 1;
    i_wr_data = i;
    @(posedge clk);
    if (o_data_vld == 1) begin
      $error("Data valid should be 0 when writing");
      $stop();
    end
  end

  // read 256 samples from the buffer
  for (int i = 0; i < 256; i++) begin
    i_rd_en = 1;
    i_rd_addr = i;
    @(posedge clk);
    if (o_data_vld == 0) begin
      $error("Data valid should be 1 when reading");
      $stop();
    end
    if (o_rd_data != i) begin
      $error("Read data mismatch at address %d", i);
      $stop();
    end
  end
  
end

endmodule