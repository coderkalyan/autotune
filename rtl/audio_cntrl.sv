module audio_cntrl #(
    parameter P24_BIT = 1,
    parameter DATA_WIDTH = P24_BIT ? 24 : 16
)(
    // FPGA facing IO

    input logic i_clk_50M,                      // 50Mhz clk from FPGA
    input logic i_rst,                          // Synchronous Active High Reset
    input logic [DATA_WIDTH-1:0] i_data,        // Data to DAC (note; this input
                                                //  must toggle if want diff data on 
                                                //  left and right channels)
    output logic o_send_over,                   // Flag finished sending data
                                                //  to DAC (note; send left then right)
    output logic o_recv_over,                   // Flag finished receiving data
                                                //  from ADC (receive left then right)
    output logic [DATA_WIDTH-1:0] o_left_data,  // Data from the ADC Left Channel
    output logic [DATA_WIDTH-1:0] o_right_data, // Data from the ADC Right Channel
    output logic o_config_err,                  // Flag indicating there was an error 
                                                //  when configuring the Codec
    output logic o_config_done,                 // Flag indicating done configuring Codec

    // Codec facing IO

    input logic i_aud_adcdat,                   // Data line from the ADC (I2S)
    output logic o_aud_dacdat,                  // Data line from the DAC (I2S)
    output logic o_bck,                         // Bit clock (I2S)
    output logic o_aud_adclrck,                 // Word Select ADC (I2S)
    output logic o_aud_daclrck,                 // Word Select DAC (I2S)
    output logic o_aud_xck,                     // Codec Master Clock
    output logic o_i2c_sclk,                    // Clock line (I2C)
    output logic o_i2c_sdat                     // Data line to Codec (I2C)
);

///////////////////////
// INTERNAL SIGNALS  //
///////////////////////

// TODO: see if there is an issue with clock domain crossing w the 50mhz
//       and the bit clock (left and right data is flopped using bit clock,
//       other modules will read using 50Mhz clk) -> Ask Abhishek since used PLL
logic busy;
logic done;
logic start;
logic addr;
logic data;

///////////////////////
// Clock Generation  //
///////////////////////
audio_clk_gen #(
    .P24_BIT(P24_BIT)
) iCLKGEN(
    .i_clk_50M(i_clk_50M),
    .i_rst(i_rst),
    .o_clk_12_28M(),                // Master Clock to Codec
    .o_clk_bit(),
    .o_clk_100K()
);

///////////////////////
// I2S ADC RECEIVER  //
///////////////////////
i2s_receiver #(
    .P24_BIT(P24_BIT)
) iI2S_REC (
    .i_sck(clk_bit),                // Bit Clock 
    .i_rst(i_rst),                  // Synchronous Active high reset
    .i_ws(),                        // Work Line (from transmitter)
    .i_sd(),                        // Data line
    .o_left_data(),                 // Left Channel Data
    .o_right_data(),                // Right Channel Data
    .o_recv_over()                  // Flag to indicate data word is ready (pulses for each channel)
);


///////////////////////
// I2S DAC TRANSMIT  //
///////////////////////
i2s_transmitter #(
    .P24_BIT(P24_BIT)
) iI2S_TRANS (
    .i_sck(),                       // Bit Clock
    .i_rst(),                       // Synchronous Active high reset
    .i_data(),                      // Input data to send (Left 1st, right second)
    .o_sd(),                        // Data line
    .o_ws(),                        // Word select for Channel 1 vs Channel 2
    .o_send_over()                  // indicates finished sending data on 1 channel
);

///////////////////////
// CODEC CONFIG FSM  //
///////////////////////
codec_fsm #(
    .P24_BIT(P24_BIT)
) iCONFIG (
    .i_clk_50M(i_clk_50M),          // 50Mhz clk from FPGA
    .i_rst(i_rst),                  // Synchronous Active High Reset
    .i_busy(busy),                  // Busy Flag from I2C
    .i_done(done),                  // Done Flag from I2C
    .o_start_transaction(start),    // Start Transaction Flag to I2C
    .o_addr(addr),                  // Register Addr to Configure
    .o_data(data),                  // Data Configure Codec with
    .o_config_done(o_config_done),  // Flag indicating Done configuring Codec
    .o_config_err(o_config_err)     // Flag indicating error during configuration
);


///////////////////////
// I2C MASTER        //
///////////////////////



endmodule