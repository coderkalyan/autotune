module midi_receiver_tb;

  // Parameters
  localparam CLK_PERIOD = 20; // 50 MHz clock -> 20ns period
  localparam BAUD_TICKS = 1600; // Matches CLK_DIV in midi_processor

  // Signals
  logic clk;
  logic rst_n;
  logic midi_rx;
  logic note_on_trigger;
  logic [6:0] note_number;
  logic [6:0] velocity;

  // Instantiate the Device Under Test (DUT)
  midi_receiver dut (
    .clk(clk),
    .rst_n(rst_n),
    .midi_rx(midi_rx),
    .note_on_trigger(note_on_trigger),
    .note_number(note_number),
    .velocity(velocity)
  );

  // Clock Generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Task to send a byte via UART (8N1)
  task send_byte(input [7:0] data);
    integer i;
    begin
      // Start bit (0)
      midi_rx = 0;
      repeat (BAUD_TICKS) @(posedge clk);

      // Data bits (LSB first)
      for (i = 0; i < 8; i++) begin
        midi_rx = data[i];
        repeat (BAUD_TICKS) @(posedge clk);
      end

      // Stop bit (1)
      midi_rx = 1;
      repeat (BAUD_TICKS) @(posedge clk);
    end
  endtask

  // Test Procedure
  initial begin
    // Initialize signals
    rst_n = 0;
    midi_rx = 1; // Idle state for UART is high

    // Apply Reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (10) @(posedge clk);

    $display("Starting MIDI Processor Test...");

    // Test Case 1: Send Note On (Channel 1, Note 60 (C4), Velocity 64)
    // Message: 0x90 0x3C 0x40
    $display("Sending Note On: 0x90 0x3C 0x40");
    send_byte(8'h90); // Status Byte (Note On, Channel 0)
    
    // Wait for processing (state transition)
    repeat (100) @(posedge clk); 
    
    send_byte(8'h3C); // Note Number (60)
    
    repeat (100) @(posedge clk);

    send_byte(8'h40); // Velocity (64)
    
    repeat (100) @(posedge clk);

    // Check outputs
    assert(note_on_trigger == 1) else $error("Test Failed: Expected note_on_trigger=1");
    assert(note_number == 7'h3C) else $error("Test Failed: Expected note_number=0x3C, got 0x%h", note_number);
    assert(velocity == 7'h40) else $error("Test Failed: Expected velocity=0x40, got 0x%h", velocity);

    if (note_on_trigger == 1 && note_number == 7'h3C && velocity == 7'h40)
      $display("Note On Test Passed!");

    repeat (1000) @(posedge clk);

    // Test Case 2: Send Note Off (Channel 1, Note 60, Velocity 0)
    // Message: 0x80 0x3C 0x00
    $display("Sending Note Off: 0x80 0x3C 0x00");
    send_byte(8'h80); // Status Byte (Note Off)
    
    repeat (100) @(posedge clk);

    send_byte(8'h3C); // Note Number
    
    repeat (100) @(posedge clk);

    send_byte(8'h00); // Velocity
    
    repeat (100) @(posedge clk);

    // Check outputs
    assert(note_on_trigger == 0) else $error("Test Failed: Expected note_on_trigger=0");
    // Note number and velocity might hold previous values or update depending on design
    // The design updates them sequentially. Velocity updates last.
    assert(note_number == 7'h3C) else $error("Test Failed: Expected note_number=0x3C");
    assert(velocity == 7'h00) else $error("Test Failed: Expected velocity=0x00");

    if (note_on_trigger == 0 && velocity == 7'h00)
      $display("Note Off Test Passed!");

    repeat (1000) @(posedge clk);

    $display("All tests completed.");
    $finish;
  end

endmodule
