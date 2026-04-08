`include "fixed.sv"

module top #(
    parameter WINDOW_SIZE = 1024,
    parameter WBITS = $clog2(WINDOW_SIZE)  
) (
    input clk,
    input rst,

    // CODEC FACING IO
    input i_aud_adcdat,
    output o_aud_dacdat,
    output o_aud_bclk,
    output o_aud_xck,
    output o_aud_lrck,
    output o_fpga_i2c_sclk,
    output o_fpga_i2c_sdat,

    // FPGA FACING IO
    input i_rxd,
    output o_txd,
    input i_mech,
    input [9:0] SW,
    output [9:0] LEDR,
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5
);

// ----------------------------------------------------------------
// Internal Signals and logic
// ----------------------------------------------------------------

// Audio control status signals 
logic config_done, config_err;

// Input data normalization
audio_t ldata, rdata;
logic [31:0] adc_data;
assign ldata = signed'(adc_data[31:16]);
assign rdata = signed'(adc_data[15:0]);

// PSOLA outputs (left and right channels)
fixed_t psola_lf;
fixed_t psola_rf; 
logic psola_valid; 

// FIFO read logic
logic adc_en, adc_empty;
assign adc_en = !adc_empty;

// FIFO write logic
logic dac_en, dac_full;
logic [31:0] dac_data;
assign dac_en = psola_valid & SW[0];
assign dac_data = {`FIXED_FTOA(psola_lf), `FIXED_FTOA(psola_rf)};

// pitch period signals
logic [9:0] pitch_period;
logic pitch_valid;
logic pitch_done;

// display output
logic transmission_done;

// ----------------------------------------------------------------
// Audio Control
// ----------------------------------------------------------------
audio_cntrl #(
    .P24_BIT(0)
) iAUD_CNTRL (
    .i_clk_50M(clk),
    .i_rst(rst),
    .i_data(dac_data),
    .i_fifo_wr_en(dac_en),
    .i_fifo_rd_en(adc_en),
    .o_read_empty(adc_empty),
    .o_write_full(dac_full),
    .o_data(adc_data),
    .o_config_err(config_err),
    .o_config_done(config_done),
    .i_aud_adcdat(i_aud_adcdat),
    .o_aud_dacdat(o_aud_dacdat),
    .o_bck(o_aud_bclk),
    .o_aud_lrck(o_aud_lrck),
    .o_aud_xck(o_aud_xck),
    .o_i2c_sclk(o_fpga_i2c_sclk),
    .o_i2c_sdat(o_fpga_i2c_sdat)
);

// ----------------------------------------------------------------
// Main Compute Module
// ----------------------------------------------------------------
compute #(
    .WINDOW_SIZE(WINDOW_SIZE),
    .TESTBENCH(0)   //if 1 bypasses and uses test_pitch_factor as the pf
) iCOMPUTE (
    .clk(clk),
    .rst(rst),
    .adc_en(adc_en),
    .ldata(ldata),
    .rdata(rdata),
    .i_rxd(i_rxd),
    .test_pitch_factor(`FIXED_RTOF(1.0 / 1.33)), 
    .psola_lf(psola_lf),
    .psola_rf(psola_rf),
    .psola_valid(psola_valid),
    .or_pitch_period(pitch_period),
    .or_pitch_valid(pitch_valid),
    .o_pitch_done(pitch_done),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5)
);

// ----------------------------------------------------------------
// Display Control
// ----------------------------------------------------------------
uart_tx_wrapper iTX_WRAP (
    .clk(clk),
    .rst(rst),
    .ir_pitch_period(pitch_period),
    .ir_pitch_valid(pitch_valid),
    .i_pitch_done(pitch_done),
    .o_transmission_done(transmission_done),
    .o_tx(o_txd)
);

// ----------------------------------------------------------------
// FPGA IO Control 
// ----------------------------------------------------------------
assign LEDR[0] = config_done;
assign LEDR[1] = config_err;
assign LEDR[2] = adc_empty;
assign LEDR[3] = dac_full;
assign LEDR[4] = transmission_done;
//assign LEDR[5] = ;
//assign LEDR[6] = ;
//assign LEDR[7] = ;
//assign LEDR[8] = ;
assign LEDR[9] = rst;



endmodule 