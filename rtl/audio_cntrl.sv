module audio_cntrl #(
    parameter P24_BIT = 1,
    parameter DATA_WIDTH = P24_BIT ? 24 : 16
)(
    // FPGA facing IO

    input logic i_clk_50M,                      // 50Mhz clk from FPGA
    input logic i_rst,                          // Synchronous Active High Reset
    input logic [2*DATA_WIDTH-1:0] i_data,      // Data to DAC {left, right}
    input logic i_fifo_wr_en,                   // Flag indicating okay to write to DAC FIFO 
    input logic i_fifo_rd_en,                   // Flag indicating okay to read from ADC FIFO
    output logic o_read_empty,                  // Empty Flag from the ADC data FIFO
    output logic [2*DATA_WIDTH-1:0] o_data,     // Data from the ADC Left Channel {left, right}
    output logic o_config_err,                  // Flag indicating there was an error 
                                                //  when configuring the Codec
    output logic o_config_done,                 // Flag indicating done configuring Codec

    // Codec facing IO

    input logic i_aud_adcdat,                   // Data line from the ADC (I2S)
    output logic o_aud_dacdat,                  // Data line from the DAC (I2S)
    output logic o_bck,                         // Bit clock (I2S)
    output logic o_aud_lrck,                    // Word Select ADC & DAC (I2S)
    output logic o_aud_xck,                     // Codec Master Clock
    output logic o_i2c_sclk,                    // Clock line (I2C)
    output logic o_i2c_sdat                     // Data line to Codec (I2C)
);

///////////////////////
// INTERNAL SIGNALS  //
///////////////////////

// Clock Signal

// ADC FIFO SIGNALS
logic recv_over;
logic [DATA_WIDTH-1:0] left_data;
logic [DATA_WIDTH-1:0] right_data;

// DAC FIFO SIGNALS
logic send_over;
logic [2*DATA_WIDTH-1:0] dac_data;

// CONFIG SIGNALS
logic busy;
logic err;
logic start;
logic [7:0] addr;
logic [7:0] reg_data;

///////////////////////
// CDC HANDLING      //
///////////////////////

// FIFO for ADC Data to FPGA
generate 
    if (P24_BIT) begin : ADC_FIFO_24
        // Note: this FIFO has a depth of 8 Words
        fifo_2_24(
            .aclr(i_rst),                       // Reset for FIFO
            .data({left_data,right_data}),      // Data to FIFO (From ADC)
            .rdclk(i_clk_50M),                  // Read clk
            .rdreq(i_fifo_rd_en),               // Read Request
            .wrclk(o_bck),                      // Write clk
            .wrreq(recv_over),                  // Write Request
            .q(o_data),                         // Data from FIFO (To DAC)
            .rdempty(o_read_empty),             // Empty Flag (read side)
            .wrfull()                           // Full Flag (write side)
        );
    end 
    else begin : ADC_FIFO_16
        // Note: this FIFO has a depth of 8 Words;   
        fifo_2_16 (
            .aclr(i_rst),                       // Reset for FIFO
            .data({left_data,right_data}),      // Data to FIFO (From ADC)
            .rdclk(i_clk_50M),                  // Read clk
            .rdreq(i_fifo_rd_en),               // Read Request
            .wrclk(o_bck),                      // Write clk
            .wrreq(recv_over),                  // Write Request
            .q(o_data),                         // Data from FIFO (To DAC)
            .rdempty(o_read_empty),             // Empty Flag (read side)
            .wrfull()                           // Full Flag (write side)
        );
    end
endgenerate

// FIFO for Data from FPGA to DAC
generate 
    if (P24_BIT) begin : DAC_FIFO_24
        // Note: this FIFO has a depth of 8 Words
        fifo_2_24(
            .aclr(i_rst),           // Reset for FIFO
            .data(i_data),          // Data to FIFO (From FPGA)
            .rdclk(o_bck),          // Read clk
            .rdreq(send_over),      // Read Request
            .wrclk(i_clk_50M),      // Write clk
            .wrreq(i_fifo_wr_en),   // Write Request
            .q(dac_data),           // Data from FIFO (To DAC)
            .rdempty(),             // Empty Flag (read side)
            .wrfull()               // Full Flag (write side)
        );
    end 
    else begin : DAC_FIFO_16
        // Note: this FIFO has a depth of 8 Words;   
        fifo_2_16 (
            .aclr(i_rst),           // Reset for FIFO
            .data(i_data),          // Data to FIFO (From FPGA)
            .rdclk(o_bck),          // I2S Bit Clock 
            .rdreq(send_over),      // Read Request
            .wrclk(i_clk_50M),      // Write clk
            .wrreq(i_fifo_wr_en),   // Write Request
            .q(dac_data),           // Data from FIFO (To DAC)
            .rdempty(),             // Empty Flag (read side)
            .wrfull()               // Full Flag (write side)
        );
    end
endgenerate

///////////////////////
// Clock Generation  //
///////////////////////
audio_clk_gen #(
    .P24_BIT(P24_BIT)
) iCLKGEN(
    .i_clk_50M(i_clk_50M),          // 50Mhz clk from FPGA
    .i_rst(i_rst),                  // Synchronous Active High reset
    .o_clk_12_28M(o_aud_xck),       // Master Clock to Codec
    .o_clk_bit(o_bck)               // 1.536Mhz clk (16 bit) vs 2.304Mhz clk (24 bit) 
);

///////////////////////
// I2S ADC RECEIVER  //
///////////////////////

// NOTE: We are using MIC (mono) INPUT, usually data only on left line 
i2s_receiver #(
    .P24_BIT(P24_BIT)
) iI2S_REC (
    .i_sck(o_bck),                  // Bit Clock 
    .i_rst(i_rst),                  // Synchronous Active high reset
    .i_ws(o_aud_lrck),              // Work Line (from transmitter)
    .i_sd(i_aud_adcdat),            // Data line
    .o_left_data(left_data),        // Left Channel Data
    .o_right_data(right_data),      // Right Channel Data 
    .o_recv_over(recv_over)         // Flag to indicate data word is ready 
                                    // (pulses 1 time once both channels are received)
);


///////////////////////
// I2S DAC TRANSMIT  //
///////////////////////
i2s_transmitter #(
    .P24_BIT(P24_BIT)
) iI2S_TRANS (
    .i_sck(o_bck),                  // Bit Clock
    .i_rst(i_rst),                  // Synchronous Active high reset
    .i_data(dac_data),              // Input data to send (Left 1st, right second)
    .o_sd(o_aud_dacdat),            // Data line
    .o_ws(o_aud_lrck),              // Word select for Channel 1 vs Channel 2
    .o_send_over(send_over)         // indicates finished sending data on 1 channel
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
    .i_nack(err),                   // Error Flag from I2C
    .o_start_transaction(start),    // Start Transaction Flag to I2C
    .o_addr(addr),                  // Register Addr to Configure
    .o_data(reg_data),              // Data Configure Codec with
    .o_config_done(o_config_done),  // Flag indicating Done configuring Codec
    .o_config_err(o_config_err)     // Flag indicating error during configuration
);


///////////////////////
// I2C MASTER        //
///////////////////////
i2c_master #(
    .DEVICE_ADDR(7'h1A)
) iI2C (
    .i_clk(i_clk_50M),              // 50Mhz clk from FPGA
    .i_rst(i_rst),                  // Synchronous Active high reset
    .i_en(start),                   // Start signal to initiate transaction
    .i_addr(addr),                  // Address of the register writing to 
    .i_data_in(reg_data),           // Data to write to register
    .o_busy(busy),                  // Flag indicating I2C bus is busy
    .o_error(err),                  // Flag indicating error during transaction
    .o_scl(o_i2c_sclk),             // I2C Clock
    .io_sda(o_i2c_sdat)             // I2C Data Line
);

endmodule