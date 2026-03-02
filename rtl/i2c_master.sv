// module i2c_master (
//     input  logic       i_clk,
//     input  logic       i_rst,
//     input  logic       i_en,
//     input  logic [6:0] i_addr,
//     input  logic [7:0] i_data_in,
//     input  logic       i_read,

//     output logic [7:0] o_data_out,
//     output logic       o_busy,
//     output logic       o_done,

//     output logic       o_scl,
//     inout  wire        io_sda
// );
//     typedef enum logic [2:0] {
//         IDLE,
//         START,
//         ADDR,
//         RW_BIT,
//         SLV_ACK,
//         STOP
//     } state_t;

//     state_t state, next_state;

//     logic [3:0] bit_cnt;
//     logic [6:0] addr_reg;
//     logic       sda_en;
//     logic       sda_out;

//     assign io_sda = sda_en ? sda_out : 1'bz;
//     assign o_scl  = (state == IDLE || state == STOP) ? 1'b1 : i_clk;

//     always_ff @(posedge i_clk) begin
//         if (i_rst) begin
//             state    <= IDLE;
//             bit_cnt  <= 4'd0;
//             addr_reg <= 7'd0;
//         end else begin
//             state <= next_state;
            
//             // Handle bit counting and internal data latching
//             if (state == IDLE && i_en) begin
//                 addr_reg <= i_addr;
//                 bit_cnt  <= 4'd6;
//             end else if (state == ADDR) begin
//                 if (bit_cnt > 0) bit_cnt <= bit_cnt - 1;
//             end
//         end
//     end

//     always_comb begin
//         next_state = state;
//         sda_en     = 1'b0;
//         sda_out    = 1'b1;
//         o_busy     = 1'b1;
//         o_done     = 1'b0;

//         case (state)
//             IDLE: begin
//                 o_busy = 1'b0;
//                 if (i_en) next_state = START;
//             end

//             START: begin
//                 sda_en  = 1'b1;
//                 sda_out = 1'b0; // Drop SDA while SCL is High
//                 next_state = ADDR;
//             end

//             ADDR: begin
//                 sda_en  = 1'b1;
//                 sda_out = addr_reg[bit_cnt];
//                 if (bit_cnt == 0) next_state = RW_BIT;
//             end

//             RW_BIT: begin
//                 sda_en  = 1'b1;
//                 sda_out = i_read;
//                 next_state = SLV_ACK;
//             end

//             SLV_ACK: begin
//                 sda_en = 1'b0;
//                 next_state = STOP;
//             end

//             STOP: begin
//                 sda_en  = 1'b1;
//                 sda_out = 1'b0;
//                 if (o_scl) begin
//                     sda_out = 1'b1;
//                     o_done  = 1'b1;
//                     next_state = IDLE;
//                 end
//             end

//             default: next_state = IDLE;
//         endcase
//     end
// endmodule


module i2c_master (
    input  logic       i_clk_50M,       // 50Mhz clock from the FPGA 
    input  logic       i_rst,           // Synchronous Active High Reset
    input  logic       i_en,            // Enable signal to start transition 
    input  logic [6:0] i_addr,          // Address of Register we are writing to 
    input  logic [7:0] i_data_in,       // Data to write to the register 
    input  logic       i_scl,           // I2C Clock 

    output logic       o_busy,          // Flag indicating in middle of transaction 
    output logic       o_done,          // Flag indicating done with transaction
    inout  logic       io_sda           // I2C Data Line
);

localparam logic [7:0] DEVICE_ADDR = {7'h1A, 1'b0}; // 7 bit address, 1 bit write

///////////////////////
// Internal Signals  //
///////////////////////



///////////////////////
// IMPLEMENTATION    //
///////////////////////



///////////////////////
// STATE MACHINE     //
///////////////////////

    
endmodule
