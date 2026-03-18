`include "../fixed.sv"

module pitch_detection #(
    parameter STAMPS = 16   
)(
    input i_clk,
    input i_rst, 
    input i_wr_en,
    input fixed_t i_proc_data
);

// ----------------------------------------------------------------
// Parameters and typedefs
// ----------------------------------------------------------------
logic [9:0] y_addr [0:STAMPS-1];
logic [9:0] x_addr; 
fixed_t eff_data [0:STAMPS]; 
fixed_t eff_addr [0:STAMPS]; 
fmac_t results [0:STAMPS-1][0:(1024/STAMPS)-1];
logic single_done;
logic all_done;
logic seg_full;

// ----------------------------------------------------------------
// Internal Logic
// ----------------------------------------------------------------

assign eff_addr = {x_addr, y_addr}; 

always @(posedge i_clk) begin
    if (i_rst) 
        x_addr <= '0;  
    else
        x_addr <= x_addr + 1; // increment global pointer to sweep through the window
end


// ----------------------------------------------------------------
// Circular Buffer
// ----------------------------------------------------------------
circular_buffer #(
  .READ_PORTS(STAMPS + 1) // global pointer + 16 local pointers
) iCB (
  .clk(i_clk),
  .rst(i_rst),
  .i_wr_en(i_wr_en),
  .i_wr_data(i_proc_data),
  .i_inc_rd_ptr(all_done),
  .i_rd_addr(eff_addr), // concatenate global pointer and local pointers for circular buffer read addresses
  .o_data(eff_data),  // concatenate global data and local data from circular buffer read ports
  .o_seg_full(seg_full)  
);


// ----------------------------------------------------------------
// Parallel Autocorrelate Engine
// ----------------------------------------------------------------
parallel_autocorrelate #(
  .STAMPS(STAMPS)
) iAUTO_CORR (
  .i_clk(clk),
  .i_rst(rst),
  .i_x_data(eff_data[STAMPS]),
  .i_y_data(eff_data[0:STAMPS-1]),
  .i_y_addr(y_addr),                    
  .i_en(seg_full),                      //enable after we have filled 256 samples in the circular buffer 
  .o_results(results),
  .o_single_done(single_done),  
  .o_all_done(all_done) 
);

// ----------------------------------------------------------------
// Peak Detection
// ----------------------------------------------------------------
// TODO

endmodule