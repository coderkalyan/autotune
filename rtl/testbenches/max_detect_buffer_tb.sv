module max_detect_buffer_tb;

  // Parameters matching the DUT
  localparam P24_BIT         = 1;
  localparam int DATA_WIDTH  = (P24_BIT ? 24 : 16);
  localparam int SEGMENTS    = 5;
  localparam int SEG_DEPTH   = 256;

  // DUT interface signals
  logic                     clk;
  logic                     rst;
  logic                     wr_en;
  logic [DATA_WIDTH-1:0]    wr_data;
  logic [2:0]               seg;
  logic [DATA_WIDTH-1:0]    max_data;

  // Reference model storage
  logic [DATA_WIDTH-1:0]    ref_max   [0:SEGMENTS-1];

  int unsigned errors;
  int seg_idx;
  logic [DATA_WIDTH-1:0] sample_data;

  // DUT instance
  max_detect_buffer #(
    .P24_BIT(P24_BIT)
  ) dut (
    .i_clk     (clk),
    .i_rst     (rst),
    .i_wr_en   (wr_en),
    .i_wr_data (wr_data),
    .i_seg     (seg),
    .o_max_data(max_data)
  );

  // Clock generation: 100 MHz equivalent (10 ns period)
  initial clk = 0;
  always #5 clk = ~clk;

  // Test sequence
  initial begin
    // Initial values
    rst       = 1'b1;
    wr_en     = 1'b0;
    wr_data   = '0;
    seg       = '0;
    for (int i = 0; i < SEGMENTS; i++) ref_max[i] = '0;
    errors    = 0;

    // Apply reset for a few cycles
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    // Drive SEGMENTS * SEG_DEPTH samples while tracking expected maxima
    for (int n = 0; n < SEGMENTS * SEG_DEPTH; n++) begin
      // Set inputs before clock edge so DUT samples them correctly
      wr_en = 1'b1;

      // Determine which segment this sample belongs to, matching DUT behavior:
      // segment index = floor(sample_index / SEG_DEPTH) mod SEGMENTS
      seg_idx = (n / SEG_DEPTH) % SEGMENTS;

      // Simple pattern: segment s gets values s*256..(s+1)*256-1, max = (s+1)*256-1
      sample_data = seg_idx * SEG_DEPTH + (n % SEG_DEPTH);

      // Drive DUT input
      wr_data = sample_data;

      // Update reference maximum for this segment
      if (sample_data > ref_max[seg_idx]) begin
        ref_max[seg_idx] = sample_data;
      end

      @(posedge clk);  // DUT samples here
    end

    // Stop writes
    @(posedge clk);
    wr_en   = 1'b0;
    wr_data = '0;

    // Give DUT a cycle to settle
    @(posedge clk);

    // Check each segment's maximum
    for (int s = 0; s < SEGMENTS; s++) begin
      seg = s[2:0];
      @(posedge clk);
      #1; // small delay for combinational output

      if (max_data !== ref_max[s]) begin
        $error("Segment %0d: expected max %0h, got %0h", s, ref_max[s], max_data);
        errors++;
      end
      else begin
        $display("Segment %0d: max correct (%0h)", s, max_data);
      end
    end

    if (errors == 0) begin
      $display("max_detect_buffer_tb: TEST PASSED");
    end
    else begin
      $display("max_detect_buffer_tb: TEST FAILED with %0d errors", errors);
    end

    $finish;
  end

endmodule
