module i2s_transmitter #( 
    parameter P24_BIT = 1,  
    parameter int DATA_WIDTH = (P24_BIT ? 24 : 16)
)(
    input logic i_sck,
    input logic i_rst,
    input logic [2*DATA_WIDTH-1:0] i_data,
    output logic o_sd,
    output logic o_ws,
    output logic o_send_over
);

///////////////////////
// INTERNAL SIGNALS  //
///////////////////////

logic [$clog2(DATA_WIDTH):0] cnt;
logic [DATA_WIDTH:0] send_buffer;
logic [DATA_WIDTH-1:0] eff_data;
logic ws_prev;

typedef enum logic [1:0] {
    IDLE,
    LEFT,
    RIGHT
} state_t;

state_t state, next_state;

///////////////////////
// LOGIC             //
///////////////////////
assign o_send_over = (cnt == (DATA_WIDTH) & ~o_ws)? 1'b1 : 1'b0; 
assign o_ws = (state == LEFT)? 1'b0 : 1'b1;
assign o_sd = send_buffer[DATA_WIDTH];

// Bit Counter 
always @(posedge i_sck) begin 
    if (i_rst) 
        cnt <= '0;
    else if (state != IDLE) begin 
        if (cnt != (DATA_WIDTH))
            cnt <= cnt + 1'b1;
        else 
            cnt <= 1'b1;
    end 
end


// Data Shifting Out
always @(posedge i_sck) begin 
    if (i_rst) 
        send_buffer <= '0;
    else if ((state == IDLE) || (cnt == (DATA_WIDTH)))
        send_buffer <= {eff_data, 1'b0};
    else if (cnt != '0)
        send_buffer <= {send_buffer[DATA_WIDTH - 1:0], 1'b0};
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
    eff_data = i_data[2*DATA_WIDTH-1:DATA_WIDTH];

    case (state) 
        IDLE: begin 
            next_state = LEFT;
        end
        LEFT: begin 
            eff_data = i_data[2*DATA_WIDTH-1:DATA_WIDTH];
            if (cnt == (DATA_WIDTH-1))
                next_state = RIGHT;
        end
        RIGHT: begin 
            eff_data = i_data[DATA_WIDTH-1:0];
            if (cnt == (DATA_WIDTH-1))
                next_state = LEFT;
        end
        default: next_state = state;
    endcase
end

endmodule
