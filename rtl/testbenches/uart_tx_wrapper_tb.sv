module uart_tx_wrapper_tb();

// Internal signals 
logic clk;
logic rst;
logic [9:0] r_pitch_period;
logic r_pitch_valid;
logic pitch_done;
logic o_transmission_done;
logic TX;

// DUT 
uart_tx_wrapper iWRAP (
    .clk(clk),
    .rst(rst),
    .ir_pitch_period(r_pitch_period),
    .ir_pitch_valid(r_pitch_valid),
    .i_pitch_done(pitch_done),
    .o_transmission_done(o_transmission_done),
    .o_tx(TX)
);

// clock generation 
initial begin 
    clk = 0;
    forever #10 clk = ~clk; // 50MHz clock
end

// helper functions
task automatic pulse(ref logic sig);
begin
    @(posedge clk);
    sig = 1;
    @(posedge clk);
    sig = 0;
end
endtask

// stimulus 
initial begin 
    rst = 1;
    pitch_done = 0;
    r_pitch_period = 0;
    r_pitch_valid = 0;

    repeat (4) @(posedge clk);
    @(negedge clk) rst = 1'b0;

    $display("TESTING ");

    // pulse pitch_done
    pulse(pitch_done);
    r_pitch_period = 10'd109;
    r_pitch_valid = 1'b1;

    // wait till done sending entire packet
    @(posedge o_transmission_done)
    $display("SENT ALL FOUR PACKETS, INSPECT RESULTS");
    $stop();


end

endmodule 