module audio_cntrl #(
    parameter P24_BIT = 1
)(


);

///////////////////////
// INTERNAL SIGNALS  //
///////////////////////


///////////////////////
// Clock Generation  //
///////////////////////
audio_clk_gen #(
    .P24_BIT(P24_BIT)
) iCLKGEN(
    .i_clk_50M(),
    .i_rst(),
    .o_clk_12_28M(),
    .o_clk_bit(),
    .o_clk_100K()
);

///////////////////////
// I2S ADC RECEIVER  //
///////////////////////
i2s_receiver #(
    .P24_BIT(P24_BIT)
) iI2S_REC (
    .i_sck(),               // Bit Clock 
    .i_rst(),               // Synchronous Active high reset
    .i_ws(),                // Work Line (from transmitter)
    .i_sd(),                // Data line
    .o_left_data(),         // Left Channel Data
    .o_right_data()         // Right Channel Data
);


///////////////////////
// I2S DAC TRANSMIT  //
///////////////////////
i2s_transmitter #(
    .P24_BIT(P24_BIT)
) iI2S_TRANS (
    .i_sck(),               // Bit Clock
    .i_rst(),               // Synchronous Active high reset
    .i_data(),              // Input data to send (Left 1st, right second)
    .o_sd(),                // Data line
    .o_ws(),                // Word select for Channel 1 vs Channel 2
    .o_send_over()          // indicates finished sending data on 1 channel
);

///////////////////////
// CODEC CONFIG FSM  //
///////////////////////



///////////////////////
// I2C MASTER        //
///////////////////////



endmodule