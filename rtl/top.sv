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

// normalized audio outputs (left and right channels)
fixed_t lf, rf;
logic psola_valid;

// FIFO read logic
logic adc_en, adc_empty;
assign adc_en = !adc_empty;

// FIFO write logic
logic dac_en, dac_full;
logic [31:0] dac_data;
assign dac_en = psola_valid & SW[0];
assign dac_data = {`FIXED_FTOA(lf), `FIXED_FTOA(rf)};

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
logic vad_active, vad_voiced;
mode_t mode;
logic [32*27-1:0] vocode_bands_flat;
logic [9:0] target_lag;
compute #(
    .WINDOW_SIZE(WINDOW_SIZE),
    .TESTBENCH(0)   //if 1 bypasses and uses test_pitch_factor as the pf
) iCOMPUTE (
    .clk(clk),
    .rst(rst),
    .adc_en(adc_en),
    .i_ldata(ldata),
    .i_rdata(rdata),
    .i_rxd(i_rxd),
    .test_pitch_factor(`FIXED_RTOF(1.0 / 1.33)),
    // .test_pitch_factor(`FIXED_RTOF(1.0 / 1.02)),
    .o_lf(lf),
    .o_rf(rf),
    .o_valid(psola_valid),
    .or_pitch_period(pitch_period),
    .or_pitch_valid(pitch_valid),
    .o_pitch_done(pitch_done),
    .o_vad_active(vad_active),
    .o_vad_voiced(vad_voiced),
    .o_mode(mode),
    .o_target_lag(target_lag),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5),
    .o_vocode_bands_flat(vocode_bands_flat)
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
    .i_vocode_bands_flat(vocode_bands_flat),
    .i_mode(mode),
    .i_vad_active(vad_active),
    .i_vad_voiced(vad_voiced),
    .i_dac_full(dac_full),
    .i_adc_empty(adc_empty),
    .i_config_done(config_done),
    .i_config_err(config_err),
    .i_target_lag(target_lag),
    .o_transmission_done(transmission_done),
    .o_tx(o_txd)
);

// ----------------------------------------------------------------
// FPGA IO Control 
// ----------------------------------------------------------------
assign LEDR[0] = config_done;
assign LEDR[1] = config_err;
assign LEDR[2] = pitch_valid;
assign LEDR[3] = adc_empty;
assign LEDR[4] = dac_full;
assign LEDR[5] = transmission_done;
assign LEDR[7] = vad_active;
assign LEDR[8] = vad_voiced;
// assign LEDR[7] = adc_empty;
// assign LEDR[8] = dac_full;
assign LEDR[9] = rst;
endmodule
