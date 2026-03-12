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
  $dumpfile("circular_buffer_tb.vcd");   // name of VCD file
  $dumpvars(0, circular_bufffer_tb);     // dump everything under the tb
end

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

  // Write 1280 zeros to initialize the memory
  for (int i = 0; i < 1280; i++) begin
    i_wr_en = 1;
    i_wr_data = 0;
    @(posedge clk);
    @(negedge clk);
  end
  i_wr_en = 0;

  // Write 256 samples do the buffer
  for (int i = 0; i < 256; i++) begin
    i_wr_en = 1;
    i_wr_data = i;
    @(posedge clk);
    @(negedge clk);
  end
  i_wr_en = 0;

  // read 256 samples from the buffer
  for (int i = 0; i < 256; i++) begin
    i_rd_en = 1;
    i_rd_addr = i;
    @(posedge clk);
    @(negedge clk);
    if (o_data_vld == 0) begin
      $error("Data valid should be 1 when reading");
      $finish();
    end
    if (o_rd_data != i) begin
      $error("Read data mismatch at address %d", i);
      $finish();
    end
  end

  i_inc_rd_ptr = 1;
  @(posedge clk);
  @(negedge clk);
  i_inc_rd_ptr = 0;

  // read 256 samples from the buffer. Should all be 0.
  for (int i = 0; i < 256; i++) begin
    i_rd_en = 1;
    i_rd_addr = i;
    @(posedge clk);
    @(negedge clk);
    if (o_data_vld == 0) begin
      $error("Data valid should be 1 when reading");
      $finish();
    end
    if (o_rd_data != 0) begin
      $error("Read data should be 0 at address %d", i);
      $finish();
    end
  end
  i_rd_en = 0;

  // ---------------------------------------------------------------------------
  // Scenario 2: Address translation across all 5 segments and wrap-around
  // ---------------------------------------------------------------------------
  // Re-assert reset to start from a clean state
  rst = 1;
  i_wr_en = 0;
  i_rd_en = 0;
  i_inc_rd_ptr = 0;
  i_rd_addr = 0;
  i_wr_data = 0;
  repeat (5) @(posedge clk);
  rst = 0;
  repeat (2) @(posedge clk);

  // Fill each of the 5 segments with a unique pattern:
  // segment s, address i -> {s[7:0], i[7:0]}
  for (int seg = 0; seg < 5; seg++) begin
    for (int i = 0; i < 256; i++) begin
      i_wr_en = 1;
      i_wr_data = {8'(seg), 8'(i)};
      @(posedge clk);
      @(negedge clk);
    end
  end
  i_wr_en = 0;

  // For each segment, verify reads through the "virtual" address space
  // and move the read base pointer with i_inc_rd_ptr
  for (int seg = 0; seg < 5; seg++) begin
    for (int i = 0; i < 256; i++) begin
      i_rd_en = 1;
      i_rd_addr = i;
      @(posedge clk);
      @(negedge clk);
      if (o_data_vld == 0) begin
        $error("Data valid should be 1 when reading seg %0d addr %0d", seg, i);
        $finish();
      end
      if (o_rd_data !== {8'(seg), 8'(i)}) begin
        $error("Read data mismatch seg=%0d addr=%0d exp=%0h got=%0h", seg, i, {8'(seg), 8'(i)}, o_rd_data);
        $finish();
      end
    end
    i_rd_en = 0;
    // Move to next physical segment (wraps after segment 4)
    if (seg < 4) begin
      i_inc_rd_ptr = 1;
      @(posedge clk);
      @(negedge clk);
      i_inc_rd_ptr = 0;
    end
  end

  // One more increment should wrap the read pointer back to segment 0
  i_inc_rd_ptr = 1;
  @(posedge clk);
  @(negedge clk);
  i_inc_rd_ptr = 0;

  // Spot-check a few addresses after wrap-around
  for (int i = 0; i < 4; i++) begin
    i_rd_en = 1;
    i_rd_addr = i;
    @(posedge clk);
    @(negedge clk);
    if (o_data_vld == 0 || o_rd_data !== {8'(0), 8'(i)}) begin
      $error("Wrap-around translation failed at addr %0d", i);
      $finish();
    end
  end
  i_rd_en = 0;

  // ---------------------------------------------------------------------------
  // Scenario 3: Simultaneous reads and writes with disjoint addresses
  // ---------------------------------------------------------------------------
  // Fresh reset again
  rst = 1;
  i_wr_en = 0;
  i_rd_en = 0;
  i_inc_rd_ptr = 0;
  i_rd_addr = 0;
  i_wr_data = 0;
  repeat (5) @(posedge clk);
  rst = 0;
  repeat (2) @(posedge clk);

  // Step 1: write a known pattern into addresses 0..255
  for (int j = 0; j < 256; j++) begin
    i_wr_en = 1;
    i_wr_data = 16'h9000 + j[15:0];
    @(posedge clk);
    @(negedge clk);
  end
  i_wr_en = 0;

  // Step 2: advance the write pointer by writing another pattern into 256..511
  for (int j = 0; j < 256; j++) begin
    i_wr_en = 1;
    i_wr_data = 16'hA000 + j[15:0];
    @(posedge clk);
    @(negedge clk);
  end
  i_wr_en = 0;

  // At this point:
  //   buffer[0..255]   = 16'h9000 + index
  //   buffer[256..511] = 16'hA000 + (index-256)
  //   wr_ptr           = 512
  // Now perform simultaneous reads from 0..255 while writing into 512..767
  for (int k = 0; k < 256; k++) begin
    i_wr_en   = 1;
    i_rd_en   = 1;
    i_rd_addr = k[9:0];
    i_wr_data = 16'hB000 + k[15:0];
    @(posedge clk);
    @(negedge clk);
    if (o_data_vld == 0) begin
      $error("Data valid should be 1 during simultaneous read/write at k=%0d", k);
      $finish();
    end
    if (o_rd_data !== (16'h9000 + k[15:0])) begin
      $error("Simultaneous R/W read mismatch at k=%0d exp=%0h got=%0h",
             k, 16'h9000 + k[15:0], o_rd_data);
      $finish();
    end
  end
  i_wr_en = 0;
  i_rd_en = 0;

  // Verify that the writes performed during the simultaneous phase landed correctly
  // in addresses 512..767.
  for (int addr = 512; addr < 768; addr++) begin
    i_rd_en   = 1;
    i_rd_addr = addr[9:0];
    @(posedge clk);
    @(negedge clk);
    if (o_data_vld == 0) begin
      $error("Data valid should be 1 when verifying writes at addr=%0d", addr);
      $finish();
    end
    if (o_rd_data !== (16'hB000 + (addr - 512))) begin
      $error("Write verification mismatch at addr=%0d exp=%0h got=%0h",
             addr, 16'hB000 + (addr - 512), o_rd_data);
      $finish();
    end
  end
  i_rd_en = 0;

  $display("Yahoo! All Tests Passed");
  $finish();
  
end

endmodule