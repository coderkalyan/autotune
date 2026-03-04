module i2s_receiver #(
 parameter P24_BIT = 1,  
 parameter int DATA_WIDTH = (P24_BIT ? 24 : 16)
)(
    input logic i_sck,
    input logic i_rst,
    input logic i_ws,
    input logic i_sd,
    output logic [DATA_WIDTH-1:0] o_left_data,
    output logic [DATA_WIDTH-1:0] o_right_data,
    output logic o_recv_over
);

///////////////////////
// INTERNAL SIGNALS  //
///////////////////////

logic ws_prev;
logic left_en;
logic [$clog2(DATA_WIDTH):0] cnt;
logic shift;

typedef enum logic [1:0] {
    IDLE,
    GET_LEFT,
    GET_RIGHT
} state_t;

state_t state, next_state;

///////////////////////
// LOGIC             //
///////////////////////

// Transaction Detection
always @(posedge i_sck) begin 
    if (i_rst)
        ws_prev <= 1'b0;
    else 
        ws_prev <= i_ws;
end

assign left_en = ws_prev != i_ws;  // Transaction initiated on left channel when have a falling edge 
assign o_recv_over = shift && (cnt == '0) & ~i_ws; // only assert after received both packets

// Bit Counter 
always @(posedge i_sck) begin 
    if (i_rst) begin 
        cnt <= '0;
        shift <= 0;
    end else if (left_en) begin 
        cnt <= '0;
        shift <= 1'b1;
    end else if (shift) begin
        cnt <= cnt + 1;
    end 
end


// Data Shifting Left
always @(posedge i_sck) begin 
    if (i_rst) 
        o_left_data <= '0;
    else if (~ws_prev & shift)
        o_left_data <= {o_left_data[DATA_WIDTH-2:0], i_sd};
end

// Data Shifting Left
always @(posedge i_sck) begin 
    if (i_rst) 
        o_right_data <= '0;
    else if (ws_prev & shift)
        o_right_data <= {o_right_data[DATA_WIDTH-2:0], i_sd};
end


///////////////////////
// I2S STATE MACHINE //
///////////////////////

always @(posedge i_sck) begin 
    if (i_rst)
        state <= IDLE;
    else 
        state <= next_state;
end

always_comb begin 
    //defaults 
    next_state = state;

    case (state) 
        IDLE: begin 
            if (left_en)
                next_state = GET_LEFT;
        end
        GET_LEFT: begin 
            if (cnt == (DATA_WIDTH))
                next_state = GET_RIGHT;
        end
        GET_RIGHT: begin 
            if (cnt == (DATA_WIDTH))
                next_state = IDLE;
        end
        default: next_state = state;
    endcase
end

endmodule