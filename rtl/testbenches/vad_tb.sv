`timescale 1ns/1ps

module vad_env_tb;

    localparam int CLK_PERIOD = 10;
    localparam int DATA_WIDTH = 16;
    localparam int FS        = 48000;
    localparam real F_TONE   = 440.0;
    localparam int AMP       = 8000;
    localparam int N_SAMPLES = 2000;
    localparam real TWO_PI   = 6.283185307179586;

    logic i_clk;
    logic i_rst;
    logic new_data;
    logic signed [DATA_WIDTH-1:0] i_data;
    logic active;

    vad #(
        .P24_BIT(0),
        .THRESHOLD(2000),
        .K(6)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .new_data(new_data),
        .i_data(i_data),
        .active(active)
    );

    // Clock
    initial begin
        i_clk = 0;
        forever #(CLK_PERIOD/2) i_clk = ~i_clk;
    end

    // Send one sample
    task automatic send_sample(input signed [DATA_WIDTH-1:0] sample);
    begin
        @(negedge i_clk);
        new_data = 1'b1;
        i_data   = sample;
        @(negedge i_clk);
        new_data = 1'b0;
    end
    endtask

    // Alternate +A, -A to mimic audio
    task automatic send_tone(input int amp, input int cycles);
        int i;
    begin
        for (i = 0; i < cycles; i++) begin
            send_sample( amp);
            send_sample(-amp);
        end
    end
    endtask

    // Silence
    task automatic send_silence(input int cycles);
        int i;
    begin
        for (i = 0; i < cycles; i++) begin
            send_sample(0);
        end
    end
    endtask

    integer n;
    real sample_real;
    integer sample_int;
    initial begin
        i_rst    = 1'b1;
        new_data = 1'b0;
        i_data   = '0;

        repeat (4) @(posedge i_clk);
        i_rst = 1'b0;

        // 1. silence
        send_silence(40);

        // 2. low amplitude speech/noise
        send_tone(1000, 40);

        // 3. silence again
        send_silence(40);

        // 4. stronger speech
        send_tone(5000, 60);

        // 5. silence so you can see decay
        send_silence(80);

        // 6. Send sine wave
        // 440 Hz tone
        for (n = 0; n < N_SAMPLES; n++) begin
            sample_real = AMP * $sin(TWO_PI * F_TONE * n / FS);
            sample_int  = $rtoi(sample_real);
            send_sample(sample_int[15:0]);
        end

        // 7. silence again
       send_silence(80);

        $stop();
    end


    // Helpful console print
    always @(posedge i_clk) begin
        if (new_data) begin
            $display("t=%0t i_data=%0d mag=%0d env=%0d active=%0b",
                     $time, i_data, dut.magnitude, dut.y, active);
        end
    end

endmodule