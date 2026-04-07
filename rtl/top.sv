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

fixed_t lf, rf;
assign lf = `FIXED_ATOF(ldata);
assign rf = `FIXED_ATOF(rdata); 

// Autocorrelation output 
logic [WBITS-1:0] pitch_period;
logic pitch_valid;
logic pitch_done;

// LPF outputs (left and right channels)
fixed_t lpf_lf;
fixed_t lpf_rf;
logic lpf_done;

// Reciprocal of the pitch factor
fixed_t pitch_factor_recip;

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
assign dac_en = psola_valid & i_mech & SW[0];
assign dac_data = {`FIXED_FTOA(psola_lf), `FIXED_FTOA(psola_rf)};

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
    .i_en(adc_en),
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
    .o_period(pitch_period),
    .o_valid(pitch_valid),
    .o_done(pitch_done)
);
logic [9:0] r_pitch_period;
logic r_pitch_valid;
always_ff @(posedge clk) begin
    if (rst) begin
        r_pitch_period <= '0;
        r_pitch_valid <= 1'b0;
    end else if (pitch_done) begin
        r_pitch_period <= pitch_period;
        r_pitch_valid <= pitch_valid;
    end
end

// ----------------------------------------------------------------
// Target Frequency 
// ----------------------------------------------------------------
target_freq #( 
    .WINDOW_SIZE(WINDOW_SIZE)
) iTF (
    .clk(clk),
    .rst(rst),
    .i_rxd(i_rxd),
    .i_period(pitch_period),
    .o_shift_ratio(pitch_factor_recip)
);


// ----------------------------------------------------------------
// PSOLA
// ----------------------------------------------------------------
psola iPSOLA_L ( 
    .clk(clk),
    .rst(rst),
    .i_lag(r_pitch_period),
    .i_advance(pitch_factor_recip),
    .i_data(lf),
    .i_valid(adc_en),
    .o_data(psola_lf),
    .o_valid(psola_valid)
);

psola iPSOLA_R ( 
    .clk(clk),
    .rst(rst),
    .i_lag(r_pitch_period),
    .i_advance(pitch_factor_recip),
    .i_data(rf),
    .i_valid(adc_en),
    .o_data(psola_rf),
    .o_valid()
);

// ----------------------------------------------------------------
// Display Control
// ----------------------------------------------------------------
// TODO: fill in once finished
transmitter iPI_UART (
    .clk(clk),
    .rst(rst),
    .i_start(),
    .i_data({8'hAA}),
    .i_tx_en(),
    .o_txd(o_txd),
    .o_busy()
);

// ----------------------------------------------------------------
// FPGA IO Control 
// ----------------------------------------------------------------
assign LEDR[0] = config_done;
assign LEDR[1] = config_err;
assign LEDR[2] = adc_empty;
assign LEDR[3] = dac_full;
assign LEDR[4] = pitch_done;
assign LEDR[5] = r_pitch_valid;
//assign LEDR[6] = ;
//assign LEDR[7] = ;
//assign LEDR[8] = ;
assign LEDR[9] = rst;

// TODO: HEX displays


endmodule 