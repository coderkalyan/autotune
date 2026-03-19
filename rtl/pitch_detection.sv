`include "/fixed.sv"

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
logic [9:0] wr_count; 
fixed_t eff_data [0:STAMPS]; 
logic [9:0] eff_addr [0:STAMPS]; 
fmac_t results [0:STAMPS-1];
fixed_t x_data;
logic single_done;
logic all_done;
logic seg_full;
logic enable;
logic ptr_reset;

// ----------------------------------------------------------------
// Internal Signals and Registers
// ----------------------------------------------------------------

assign eff_addr = {x_addr, y_addr}; 
assign x_data = eff_data[0];

// ----------------------------------------------------------------
// Global Pointer Logic
// ----------------------------------------------------------------

always @(posedge i_clk) begin
    if (i_rst) 
        x_addr <= '0;  
    else if (ptr_reset | enable)
        x_addr <= 0; 
    else 
        x_addr <= x_addr + 1; // increment global pointer to sweep through the window
end

// ----------------------------------------------------------------
// Write Counter and State Machine to track when to start autocorrelation
// ----------------------------------------------------------------

// counter for writes to circular buffer
always @(posedge i_clk) begin
    if (i_rst) 
        wr_count <= '0;  
    else if (i_wr_en)
        wr_count <= wr_count + 1; 
end

// State Machine to track when we have filled 1024 initial samples in the circular buffer and are ready to start autocorrelation
typedef enum logic [1:0] {FILL_BUFFER, AUTOCORR} state_t;
state_t state, next_state;

always @(posedge i_clk) begin
    if (i_rst) 
        state <= FILL_BUFFER;
    else
        state <= next_state;
end

always_comb begin
    next_state = state;
    enable = 0;
    case (state)
        FILL_BUFFER: begin
            if (wr_count == 10'd1023) begin
                next_state = AUTOCORR;
                enable = 1'b1;
            end
        end
        AUTOCORR: begin
            next_state = AUTOCORR; // stay in autocorrelation state indefinitely for now
            if (seg_full) begin
                enable = 1'b1; 
            end
        end
        default: next_state = FILL_BUFFER;
    endcase
end

// ----------------------------------------------------------------
// Circular Buffer
// ----------------------------------------------------------------
circular_buffer #(
  .READ_PORTS(STAMPS + 1), // global pointer + 16 local pointers
  .SIM(1)
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
// Parallel Autocorrelation Engine
// ----------------------------------------------------------------
parallel_autocorrelate #(
  .STAMPS(STAMPS),
  .SIM(0)
) iAUTO_CORR (
  .i_clk(i_clk),
  .i_rst(i_rst),
  .i_x_data(x_data),
  .i_y_data(eff_data[1:STAMPS]),
  .o_y_addr(y_addr),                    
  .i_en(enable),                       
  .o_results(results),
  .o_autocorr_en_ptr(ptr_reset),
  .o_single_done(single_done),  
  .o_all_done(all_done) 
);

// ----------------------------------------------------------------
// Autocorrelation Result Serializer
// ----------------------------------------------------------------
// TODO:

// ----------------------------------------------------------------
// Peak Detection
// ----------------------------------------------------------------
// TODO

endmodule