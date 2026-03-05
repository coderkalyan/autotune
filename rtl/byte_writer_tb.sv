`timescale 1ns / 1ps

module byte_writer_tb();

    // Inputs
    reg         i_clk;
    reg         i_rst;
    reg         i_start;
    reg  [7:0]  i_data;

    // Outputs
    wire        o_busy;
    wire        o_scl;
    wire        o_error;
    
    // Bidirectional SDA simulation
    wire        sda_net;
    reg         force_sda_low; // TB control to simulate Slave ACK

    // Instantiate UUT
    // Note: I'm mapping your io_sda to the bidirectional sda_net
    byte_writer uut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_data(i_data),
        .o_busy(o_busy),
        .io_sda(sda_net), 
        .o_scl(o_scl),
        .o_error(o_error)
    );

    // --- I2C Physical Layer Simulation ---
    // If master isn't driving (Z) and TB isn't forcing low, pull-up makes it 1.
    assign  sda_net = force_sda_low ? 1'b0 : 1'bz;

    // Clock Generation
    always #5 i_clk = ~i_clk;

    initial begin
        // Initialize
        i_clk = 0;
        i_rst = 1;
        i_start = 0;
        i_data = 8'h00;
        force_sda_low = 0;

        #100;
        i_rst = 0;
        #20;

        // --- TEST CASE 1: Successful ACK ---
        $display("Starting Test Case 1: Expecting ACK (Error = 0)");
        send_byte(8'hA5, 1); // Send 0xA5 and simulate slave ACK
        
        if (o_error === 0) $display("Result: Success! ACK received.");
        else               $display("Result: Fail! Unexpected NACK.");

        #100;

        // --- TEST CASE 2: NACK (Device missing) ---
        $display("Starting Test Case 2: Expecting NACK (Error = 1)");
        send_byte(8'h3C, 0); // Send 0x3C and simulate slave NACK (do nothing)

        if (o_error === 1) $display("Result: Success! NACK detected.");
        else               $display("Result: Fail! Unexpected ACK.");

        #100;
        $display("Simulation Finished");
        $finish;
    end

    // Task to handle the timing of a byte transfer
    task send_byte(input [7:0] data, input simulate_ack);
        begin
            @(posedge i_clk);
            i_data = data;
            i_start = 1;
            @(posedge i_clk);
            i_start = 0;

            // Wait until we reach the SACK state logic
            // We look for when the master releases the SDA line (o_busy is high)
            wait(o_busy == 1);
            
            // In your design, bit_count 7 and phase_wa triggers SACK.
            // We will wait until SCL goes high for the 9th bit, then drive ACK
            repeat (8) @(negedge o_scl); // Wait for 8 data bits to pass
            
            $display("simulating ack %d %d", simulate_ack, force_sda_low);
            if (simulate_ack) begin
                force_sda_low = 1; // Slave pulls SDA low for ACK
                $display("%d", force_sda_low);
            end

            @(negedge o_scl);    // End of ACK bit
            #1 force_sda_low = 0; // Release
            
            wait(o_busy == 0);
        end
    endtask

endmodule
