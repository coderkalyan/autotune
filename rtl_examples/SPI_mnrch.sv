`default_nettype none
module SPI_mnrch (
    input wire              clk,       // 50 MHz system clock
    input wire              rst_n,     // active-low reset
    // Control/Data
    input wire              wrt,       // 1-cycle pulse to start SPI transaction
    input wire       [15:0] wrt_data,  // command/data to send
    output reg          done,      // asserts when transaction completes; holds until next wrt
    output reg [15:0] rd_data,   // data received (sensor uses [7:0])
    // SPI pins
    output reg        SS_n,      // chip select (active-low)
    output reg        SCLK,      // SPI clock
    output reg        MOSI,      // master-out slave-in
    input wire            MISO       // master-in slave-out
);

    typedef enum reg [1:0] {
        IDLE,
        FRONT,
        BODY,
        BACK
    } state_t;

    reg [3:0] SCLK_div;
    logic ld_SCLK;

    logic smpl, shft, shft_imm;
    reg MISO_smpl;

    reg [15:0] shft_reg;
    reg [3:0] bit_cntr;
    logic done15;

    state_t state, nxt_state;
    logic set_done, init;

    //sclk div 
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) SCLK_div <= 4'b1000;
        else if (ld_SCLK) SCLK_div <= 4'b1011;
        else SCLK_div <= SCLK_div + 1;
    end

    assign SCLK = SCLK_div[3];
    assign smpl = (SCLK_div == 4'b0111);
    assign shft_imm = (SCLK_div == 4'b1111);

    //sample MISO
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) MISO_smpl <= 1'b0;
        else if (smpl) MISO_smpl <= MISO;
    end

    //shift_reg with msb being MOSI
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) shft_reg <= 4'd0;
        else if (init) shft_reg <= wrt_data;
        else if (shft) shft_reg <= {shft_reg[14:0], MISO_smpl};
    end

    assign MOSI = shft_reg[15];

    //bit_cntr (used to count how many bits shifted) 
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) bit_cntr <= 4'd0;
        else if (init) bit_cntr <= 4'd0;
        else if (shft) bit_cntr <= bit_cntr + 1;
    end

    assign done15 = &bit_cntr;

    //state flop (obv) with default being IDLE
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= nxt_state;
    end

    //state machine
    always_comb begin
        nxt_state = state;
        init = 0;
        shft = 0;
        ld_SCLK = 0;
        set_done = 0;
        rd_data = shft_reg;
        case (state)
            IDLE: begin
                ld_SCLK = 1;
                if (wrt) begin
                    init = 1;
                    nxt_state = FRONT;
                end
            end
            FRONT: begin
                if (shft_imm) nxt_state = BODY;
            end
            BODY: begin
                //FIXME:, might need to make if else type logic
                if (done15) nxt_state = BACK;
                else if (shft_imm) shft = 1;
            end
            BACK: begin
                if (shft_imm) begin
                    ld_SCLK = 1;
                    shft = 1;
                    set_done = 1;
                    nxt_state = IDLE;
                end
            end
        endcase
    end

    //flop for done
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) done <= 1'b0;
        else if (init) done <= 1'b0;
        else if (set_done) done <= 1'b1;
    end

    //flop for SS_n
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) SS_n <= 1'b1;
        else if (init) SS_n <= 1'b0;
        else if (set_done) SS_n <= 1'b1;
    end

endmodule
