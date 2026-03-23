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

    // KEYBOARD RX LINE
    input i_rxd,

    // LED STATUS OUTPUTS
    output o_config_err,
    output o_config_done

);

// ----------------------------------------------------------------
// Internal Signals and logic
// ----------------------------------------------------------------
logic [31:0] adc_data;
logic lpf_done;
logic [WBITS-1:0] period;

logic new_sample, adc_empty;
assign new_sample = !adc_empty;

logic signed [15:0] ldata, rdata;
assign ldata = signed'(adc_data[31:16]);
assign rdata = signed'(adc_data[15:0]);

fixed_t lf, rf;
assign lf = `FIXED_ATOF(ldata);
assign rf = `FIXED_ATOF(rdata);

fixed_t lpf_lf;
fixed_t lpf_rf;

// ----------------------------------------------------------------
// Audio Control
// ----------------------------------------------------------------
audio_cntrl #(
    .P24_BIT(0)
) iAUD_CNTRL (
    .i_clk_50M(clk),
    .i_rst(rst),
    .i_data(),
    .i_fifo_wr_en(),
    .i_fifo_rd_en(new_sample),
    .o_read_empty(adc_empty),
    .o_write_full(),
    .o_data(adc_data),
    .o_config_err(o_config_err),
    .o_config_done(o_config_done),
    .i_aud_adcdat(i_aud_adcdat),
    .o_aud_dacdat(o_aud_dacdat),
    .o_bck(o_aud_bclk),
    .o_aud_lrck(o_aud_lrck),
    .o_aud_xck(o_aud_xck),
    .o_i2c_sclk(o_fpga_i2c_sclk),
    .o_i2c_sdat(o_fpga_i2c_sdat)
);

// ----------------------------------------------------------------
// Preprocessing
// ----------------------------------------------------------------
preprocessing #(
    .CHANNELS(0),    // default: 0 lpf left and right data; 1 lpf left channel only 
    .L_FC(10000),
    .R_FC(400)
) iPP (
    .clk(clk),
    .rst(rst),
    .i_lf(lf),
    .i_rf(rf),
    .i_en(new_sample),
    .o_lpf_lf(lpf_lf),
    .o_lpf_rf(lpf_rf),
    .o_lpf_valid(lpf_done)
);

// ----------------------------------------------------------------
// Pitch Detection
// ----------------------------------------------------------------
pitch_detection #(
    .WINDOW_SIZE(WINDOW_SIZE),
    .STAMPS(16)
) iPD (
    .clk(clk),
    .rst(rst),
    .i_wr_en(lpf_done),
    .i_proc_data(lpf_lf),
    .o_period(period),
    .o_valid(),
    .o_done()
);

// ----------------------------------------------------------------
// Target Frequency 
// ----------------------------------------------------------------
target_freq #( 
    .WINDOW_SIZE(WINDOW_SIZE)
) iTF (
    .clk(clk),
    .rst(rst),
    .i_rxd(i_rxd),
    .i_period(period),
    .o_shift_ratio()
);


// ----------------------------------------------------------------
// PSOLA
// ----------------------------------------------------------------
// TODO: fill in once finished

// ----------------------------------------------------------------
// Display Control
// ----------------------------------------------------------------
// TODO: fill in once finished

endmodule