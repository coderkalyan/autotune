module transmitter (
    input  wire       clk,
    input  wire       rst,
    input  wire       i_start,
    input  wire [7:0] i_data,
    input  wire       i_tx_en,
    output wire       o_txd,
    output wire       o_busy
);
    // typedef enum logic {
    //     IDLE,
    //     SEND
    // } state_t;

    typedef enum logic [1:0] {
        IDLE,
        WAIT,
        SEND
    } state_t;

    // Bit counter counts up to 10 bits (start, 8 data, stop).
    logic [3:0] bit_counter;
    always_ff @(posedge clk) begin
        if (i_start)
            bit_counter <= 4'd0;
        else if (i_tx_en)
            bit_counter <= bit_counter + 1;
    end

    state_t state, next_state;
    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Latch input data on start, inserting a start and stop bit.
    logic [9:0] data;
    logic       latch_data;
    always_ff @(posedge clk) begin
        if (latch_data)
            data <= {1'b1, i_data, 1'b0};
        else if (i_tx_en)
            data <= {1'b1, data[9:1]};
    end

    logic txd;
    always_comb begin
        next_state = state;
        latch_data = 1'b0;
        txd = 1'b1;

        case (state)
            IDLE: begin
                if (i_start) begin
                    next_state = WAIT;
                    // next_state = SEND;
                    // latch_data = 1'b1;
                    // txd = 1'b0;
                end
            end
            WAIT: begin 
                if (i_tx_en) begin 
                    next_state = SEND;
                    latch_data = 1'b1;
                    txd = 1'b0;
                end
            end
            SEND: begin
                txd = data[0];

                if (bit_counter == 4'd10)
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    assign o_busy = (state == WAIT) || (state == SEND);
    assign o_txd = txd;
endmodule
