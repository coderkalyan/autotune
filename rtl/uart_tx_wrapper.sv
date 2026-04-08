module uart_tx_wrapper ( 
    input clk,
    input rst,
    input [9:0] ir_pitch_period,
    input ir_pitch_valid,
    input i_pitch_done,
    output reg o_transmission_done,
    output o_tx
);

typedef enum reg [1:0] {IDLE, INIT, SENDING} state_t;
state_t state, next_state;

logic tx_done;
logic tmrt;
logic [7:0] eff_data;
logic [2:0] cnt;

UART_tx iTX  (
    .clk(clk),              // MHZ CLOCK
    .rst_n(~rst),           // ACTIVE LOW RESET 
    .tmrt(tmrt),            // SIGNAL TO INITIATE TRANSMISSION 
    .tx_data(eff_data),     // DATA TO TRANSMIT 
    .tx_done(tx_done),      // FLAG ASSERTED WHEN TRANSMISSION DONE
    .TX(o_tx)               // BIT CURRENTLY BEING TRANSMITTING
);

// PACKET LOGIC //
always_comb begin 
    case (cnt) 
        3'd0: eff_data = {1'b1, ir_pitch_valid, 6'd0};
        3'd1: eff_data = {1'b0, 7'd0};
        3'd2: eff_data = {1'b0, 4'd0, ir_pitch_period[9:7]};
        3'd3: eff_data = {1'b0, ir_pitch_period[6:0]};
        default: eff_data = '0;
    endcase 
end


// COUNTER LOGIC //
always_ff @(posedge clk) begin 
    if (rst)
        cnt <= '0;
    else if (tx_done)  
        cnt <= cnt + 1'b1;
end 

// FSM STATE FLOP //
always_ff @(posedge clk) begin 
    if (rst)
        state <= IDLE;
    else 
        state <= next_state;
end

// FSM STATE MACHINE TRANSITION LOGIC //
always_comb begin 
    // defaults 
    next_state = state;
    tmrt = 1'b0;
    o_transmission_done = 1'b0;

    case (state)
        IDLE: begin 
            if (i_pitch_done) begin 
                next_state = INIT;
            end 
        end
        INIT: begin
            // pipeline to allow r_pitch_period to update 
            // and eff_data
            tmrt = 1'b1;
            next_state = SENDING;
        end
        SENDING: begin 
            if (cnt == 3'd4) begin 
                next_state = IDLE;
                o_transmission_done = 1'b1;
            end
            if (tx_done) begin 
                next_state = INIT;
            end 
        end
        default: next_state = IDLE;
    endcase 
end


endmodule