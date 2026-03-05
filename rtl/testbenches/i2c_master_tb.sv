`timescale 1ns / 1ps

module i2c_master_tb();

    // Inputs
    reg i_clk_50M;
    reg i_rst;
    reg i_en;
    reg [7:0] i_addr;
    reg [7:0] i_data_in;

    // Outputs
    wire o_scl;
    wire o_busy;
    wire o_error;
    // wire io_sda;

    // Pull-up resistor simulation for I2C
    // In real hardware, these are external resistors.
    // In simulation, 'tri1' pulls the signal to 1 when no one is driving it.
    tri1 io_sda;
    reg  sda_slave_drive;
    assign io_sda = sda_slave_drive ? 1'b0 : 1'bz;

    // Instantiate the Master
    i2c_master #(
        .DEVICE_ADDR(7'h1A)
    ) uut (
        .i_clk(i_clk_50M),
        .i_rst(i_rst),
        .i_en(i_en),
        .i_addr(i_addr),
        .i_data_in(i_data_in),
        .o_scl(o_scl),
        .o_busy(o_busy),
        .o_error(o_error),
        .io_sda(io_sda)
    );

    // Clock generation (50MHz -> 20ns period)
    always #10 i_clk_50M = ~i_clk_50M;

    initial begin
        // Initialize
        i_clk_50M = 0;
        i_rst = 1;
        i_en = 0;
        i_addr = 8'h00;
        i_data_in = 8'h00;
        sda_slave_drive = 0;

        #100;
        i_rst = 0;
        #40;

        // --- Start Transaction ---
        $display("Master: Starting Write to Reg 0x12 with Data 0xEF");
        i_addr = 8'h12;
        i_data_in = 8'hEF;
        i_en = 1;
        @(posedge i_clk_50M);
        @(negedge i_clk_50M);
        i_en = 0;

        // Monitor the SDA/SCL lines to provide Slave ACKs
        // Since your current design only sends one byte in the BYTE state,
        // the slave only needs to ACK once.
        simulate_slave_ack();
        simulate_slave_ack_repeat();
        simulate_slave_ack_repeat();

        // Wait for transaction to complete
        wait(o_busy == 0);
        
        if (o_error) 
            $display("Master: Transaction failed with Error!");
        else 
            $display("Master: Transaction completed successfully.");

        #500;
        $finish;
    end

    // Task to simulate a Slave responding with an ACK
    task simulate_slave_ack();
        begin
            // 1. Wait for START condition (SDA falling while SCL is high)
            wait(io_sda == 0 && o_scl == 1);
            $display("Slave: Detected START");
            @(negedge o_scl);

            // 2. Wait for 8 SCL pulses (the data bits)
            repeat (8) @(negedge o_scl);
            
            // 3. Drive SDA low for the 9th bit (ACK)
            #1; // small delay to mimic real physics
            sda_slave_drive = 1;
            $display("Slave: Sending ACK");

            @(negedge o_scl); // End of ACK bit
            #1 sda_slave_drive = 0;
        end
    endtask

    // Task to simulate a Slave responding with an ACK
    task simulate_slave_ack_repeat();
        begin
            // 2. Wait for 8 SCL pulses (the data bits)
            repeat (8) @(negedge o_scl);
            
            // 3. Drive SDA low for the 9th bit (ACK)
            #1; // small delay to mimic real physics
            sda_slave_drive = 1;
            $display("Slave: Sending ACK");

            @(negedge o_scl); // End of ACK bit
            #1 sda_slave_drive = 0;
        end
    endtask

    // Waveform dump
    initial begin
        $dumpfile("i2c_master.vcd");
        $dumpvars(0, i2c_master_tb);
    end

endmodule
