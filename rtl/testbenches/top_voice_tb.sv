`timescale 1ns / 1ps
`include "../fixed.sv"

module top_voice_tb ();

// Testbench will take in voice audio and apply
// it to the top module, so we can test the autotune 
// functionality with real audio data in simulation.

// ----------------------------------------------------------------
// Signals
// ----------------------------------------------------------------

// Dut inputs
logic clk;
logic rst;
logic adc_en;
audio_t ldata;
audio_t rdata;

// Dut outputs 
fixed_t psola_lf;
fixed_t psola_rf;
logic psola_valid;

// Audio Sample: 
// fixed_t sample;

// ----------------------------------------------------------------
// Clock Generation
// ----------------------------------------------------------------
initial begin 
    clk = 0;
    forever #10 clk = ~clk; // 50MHz clock
end

// ----------------------------------------------------------------
// DUT
// ----------------------------------------------------------------

// TODO: may need to compute to add manual pf control 
compute #(
    .WINDOW_SIZE(1024),
    .TESTBENCH(1)
) iCompute (
    .clk(clk),
    .rst(rst),
    .adc_en(adc_en),
    .ldata(ldata),
    .rdata(rdata),
    .test_pitch_factor(`FIXED_RTOF(1.0/1.33)),
    .i_rxd(),
    .psola_lf(psola_lf),
    .psola_rf(psola_rf),
    .psola_valid(psola_valid),
    .or_pitch_period(),
    .or_pitch_valid(),
    .o_vad_active(),
    .o_vad_voiced(),
    .HEX0(),
    .HEX1(),
    .HEX2(),
    .HEX3(),
    .HEX4(),
    .HEX5()
);

// ----------------------------------------------------------------
// Helper logic 
// ----------------------------------------------------------------
task automatic wait_clks(input int n);
    repeat (n) @(posedge clk);
endtask

// ----------------------------------------------------------------
// Stimulus Generation 
// ----------------------------------------------------------------
integer fd;
integer status;
initial begin 
    clk = 0;
    rst = 1;

    // TODO: use python script to convert .pcm file to .hex file, 
    // then read in the .hex file here to apply as stimulus to the DUT
    fd = $fopen("/home/kalyan/Documents/school/ece554/autotune/py/nights.mem", "rb");
    if (fd == 0) begin
        $display("ERROR: could not open hex file");
        $stop();
    end
    $display("Successfully opened hex file, applying stimulus...");

    repeat (4) @(posedge clk);
    @(negedge clk) rst = 1'b0;

    fork 
        begin
            while (!$feof(fd)) begin
                // read in hex sample and convert to signed 16-bit
                // $fread(sample, fd, 0, 2);
                // status = $fscanf(fd, "%h\n", sample);
                status = $fscanf(fd, "%h", ldata);
                status = $fscanf(fd, "%h\n", rdata);
                if (status != 1) begin
                    $display("ERROR: could not read sample from hex file, moving to next line");
                    continue;
                end
                // ldata   = signed'(sample);
                // rdata   = signed'(sample);
                adc_en = 1'b1;
                @(posedge clk);
                adc_en = 1'b0;

                // wait until next sample time
                repeat (64) @(posedge clk);
            end
        end
        begin 
            // TODO: if you would like to manually control the 
            // pitch factor, you can do so here by driving 
            forever @(posedge clk); // temporarily keep process alive indefinitely

        end
    join_any 

    $fclose(fd);
    $display("End of stimulus application");
    $stop();
end

endmodule
