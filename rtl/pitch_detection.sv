`include "fixed.sv"

module pitch_detection #(
    parameter WINDOW_SIZE = 1024,
    parameter STAMPS = 16,
    parameter WBITS = $clog2(WINDOW_SIZE)
)(
    input clk,
    input rst, 
    input i_wr_en,
    input fixed_t i_proc_data,
    output logic [WBITS-1:0] o_period, 
    output logic o_valid,
    output logic o_done
);

// Second order low pass filter on input data before any autocorrelation
// logic.
logic   valid [2];
fixed_t data  [2];

lpf #(
    .FC_HZ(1000)
) (
    .clk(clk),
    .rst(rst),
    .i_valid(i_wr_en),
    .i_data(i_proc_data),
    .o_valid(valid[0]),
    .o_data(data[0])
);

lpf #(
    .FC_HZ(1000)
) (
    .clk(clk),
    .rst(rst),
    .i_valid(valid[0]),
    .i_data(data[0]),
    .o_valid(valid[1]),
    .o_data(data[1])
);

// NOTE: Autocorrelation uses data[1] and valid[1] as inputs.

// ----------------------------------------------------------------
// Internal signals and registers
// ----------------------------------------------------------------

// Circular buffer read/write addresses and data
logic [9:0] y_addr [0:STAMPS-1];
logic [9:0] x_addr; 
fixed_t eff_data [0:STAMPS]; 
logic [9:0] eff_addr [0:STAMPS]; 

// write counter to track cb writes
logic [9:0] wr_count;

// results from parallel autocorrelation engine
fmac_t results [0:STAMPS-1];

// control signals for parallel autocorrelation engine
logic single_done;
logic all_done;
logic seg_full;
logic enable;
logic ptr_reset;

// serialization buffer flags
logic buf_busy;
logic buf_valid;
fmac_t buf_sample;


// ----------------------------------------------------------------
// Simple Combinational
// ----------------------------------------------------------------

// assign eff_addr = {x_addr, y_addr};
assign eff_addr[0] = x_addr;
assign eff_addr[1:STAMPS] = y_addr;

// ----------------------------------------------------------------
// Global Pointer Logic
// ----------------------------------------------------------------

always @(posedge clk) begin
    if (rst) 
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
always @(posedge clk) begin
    if (rst) 
        wr_count <= '0;  
    else if (valid[1])
        wr_count <= wr_count + 1; 
end

// State Machine to track when we have filled 1024 initial samples in the circular buffer and are ready to start autocorrelation
typedef enum logic [1:0] {FILL_BUFFER, AUTOCORR} state_t;
state_t state, next_state;

always @(posedge clk) begin
    if (rst) 
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
  .SIM(1)   // Set SIM=0 for ip BRAM
) iCB (
  .clk(clk),
  .rst(rst),
  .i_wr_en(valid[1]),
  .i_wr_data(data[1]),
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
  .clk(clk),
  .rst(rst),
  .i_x_data(eff_data[0]),
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
autocorrelate_buffer #(
    .STAMPS(STAMPS)
) iBUF (
    .clk(clk),
    .rst(rst),
    .i_valid(single_done), // pulse when the first instance is done, which indicates the global pointer has completed a full sweep and is back at the start
    .i_results(results),
    .o_busy(buf_busy),
    .o_valid(buf_valid),
    .o_sample(buf_sample)
);

// ----------------------------------------------------------------
// Peak Detection
// ----------------------------------------------------------------
f0_detect #(
  .LAG_MIN(48),
  .LAG_MAX(480)
) iF0 (
  .clk(clk),
  .rst(rst),
  .i_start(enable),
  .i_valid(buf_valid),
  .i_sample(buf_sample),
  .o_period(o_period),
  .o_valid(o_valid),
  .o_done(o_done)
);

endmodule
