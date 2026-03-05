`timescale 1ns / 1ps

module i2c_master #(
    parameter logic [6:0] DEVICE_ADDR = 7'h1A
) (
    input logic       i_clk,  // 50Mhz clock from the FPGA
    input logic       i_rst,      // Synchronous Active High Reset
    input logic       i_en,       // Enable signal to start transition
    input logic [7:0] i_addr,     // Address of Register we are writing to
    input logic [7:0] i_data_in,  // Data to write to the register

    output logic [1:0] o_count,
    output logic o_busy,   // Flag indicating active transaction
    output logic o_error,  // Flag indicating error during transaction
    output logic o_scl,    // I2C Clock
    inout  wire  io_sda    // I2C Data Line
);
    localparam logic READ = 1'b1;
    localparam logic WRITE = 1'b0;

    typedef enum logic [2:0] {
        IDLE,
        START,
        SEND,
        WAIT,
        STOP
    } state_t;

    // Assemble a 24 bit write transaction including device address, register
    // address, register write data.
    // wire [23:0] bitstream = {DEVICE_ADDR, WRITE, i_addr, i_data_in};

    localparam logic [8:0] COUNT = 9'd8; // 9'd500;
    localparam logic [8:0] QUARTER = COUNT / 4;
    logic [8:0] phase_count;
    wire        phase_lo = (phase_count == (QUARTER - 1));     // drive scl low
    wire        phase_hi = (phase_count == (3 * QUARTER - 1)); // drive scl high
    wire        phase_wa = (phase_count == (COUNT - 1));       // wrap around to 0
    logic       phase_reset;
    always_ff @(posedge i_clk) begin
        if (i_rst)
            phase_count <= 9'd0;
        else if (phase_reset || phase_wa)
            phase_count <= 9'd0;
        else
            phase_count <= phase_count + 1;
    end

    state_t     state;
    logic [7:0] addr, data;
    logic [7:0] wdata;
    logic [1:0] byte_count;
    logic       byte_start, sda, scl, en, error;
    wire        byte_busy, byte_scl, byte_error;
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state      <= IDLE;
            addr       <= 8'hx;
            data       <= 8'hx;
            byte_count <= 2'dx;
            byte_start <= 1'b0;
            sda        <= 1'bx;
            scl        <= 1'b1;
            en         <= 1'b0;
            error      <= 1'b0;
            phase_reset <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    if (i_en) begin
                        state       <= START;
                        addr        <= i_addr;
                        data        <= i_data_in;
                        phase_reset <= 1'b0;
                        scl         <= 1'b1;
                        sda         <= 1'b1;
                        en          <= 1'b1;
                        error       <= 1'b0;
                    end
                end
                START: begin
                    if (phase_lo) begin
                        sda <= 1'b0;
                    end else if (phase_wa) begin
                        state       <= SEND;
                        byte_count  <= 2'd0;
                        byte_start  <= 1'b1;
                        phase_reset <= 1'b1;
                    end
                end
                SEND: begin
                    state <= WAIT;
                    en    <= 1'b0;
                end
                WAIT: begin
                    byte_start  <= 1'b0;

                    if (!byte_busy) begin
                        if (byte_error) begin
                            state <= IDLE;
                            error <= 1'b1;
                        end else begin
                            if (byte_count == 2'd2) begin
                                state       <= STOP;
                                en          <= 1'b1;
                                scl         <= 1'b1;
                                sda         <= 1'b0;
                                phase_reset <= 1'b0;
                            end else begin
                                state      <= SEND;
                                byte_count <= byte_count + 1;
                                byte_start <= 1'b1;
                            end
                        end
                    end
                end
                STOP: begin
                    if (phase_hi) begin
                        sda <= 1'b1;
                    end else if (phase_wa) begin
                        state       <= IDLE;
                        phase_reset <= 1'b1;
                    end
                end
                default: begin
                    state       <= IDLE;
                    phase_reset <= 1'b1;
                end
            endcase
        end
    end

    always_comb begin
        case (byte_count)
            2'd0:    wdata = {DEVICE_ADDR, WRITE};
            2'd1:    wdata = addr;
            2'd2:    wdata = data;
            default: wdata = 8'hx;
        endcase
    end

    byte_writer #(.COUNT(COUNT)) writer (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(byte_start),
        .i_data(wdata),
        .o_busy(byte_busy),
        .io_sda(io_sda),
        .o_scl(byte_scl),
        .o_error(byte_error)
    );

    assign o_busy  = state != IDLE;
    assign o_error = error;
    assign o_scl   = en ? scl : byte_scl;
    assign io_sda  = en ? sda : 1'bz;
    assign o_count = byte_count;
endmodule

module byte_writer #(
    parameter logic [8:0] COUNT = 9'd8
) (
    input  wire       i_clk,
    input  wire       i_rst,
    input  wire       i_start,
    input  wire [7:0] i_data,
    output wire       o_busy,
    inout  wire       io_sda,
    output wire       o_scl,
    output wire       o_error
);
    localparam logic [8:0] QUARTER = COUNT / 4;
    logic [8:0] phase_count;
    wire        phase_hi = (phase_count == (QUARTER - 1));     // drive scl high
    wire        phase_lo = (phase_count == (3 * QUARTER - 1)); // drive scl low
    wire        phase_sa = (phase_count == (2 * QUARTER - 1)); // sample ack
    wire        phase_wa = (phase_count == (COUNT - 1));       // wrap around to 0
    logic       phase_reset;
    always_ff @(posedge i_clk) begin
        if (i_rst)
            phase_count <= 9'd0;
        else if (phase_reset || phase_wa)
            phase_count <= 9'd0;
        else
            phase_count <= phase_count + 1;
    end

    typedef enum logic [1:0] {
        IDLE,
        XMIT,
        SACK
    } state_t;

    state_t state;
    logic [7:0] data;
    logic [2:0] bit_count;
    logic       scl, sda, sda_en, error;
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state     <= IDLE;
            data      <= 8'hxx;
            bit_count <= 3'dx;
            scl       <= 1'bx;
            sda       <= 1'bx;
            sda_en    <= 1'b0;
            error     <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    phase_reset <= 1'b1;

                    if (i_start) begin
                        state       <= XMIT;
                        data        <= i_data;
                        bit_count   <= 3'd0;
                        phase_reset <= 1'b0;
                        scl         <= 1'b0;
                        sda         <= i_data[7];
                        sda_en      <= 1'b1;
                        error       <= 1'b1;
                    end
                end
                XMIT: begin
                    if (phase_hi) begin
                        scl <= 1'b1;
                    end else if (phase_lo) begin
                        scl <= 1'b0;

                        // if (bit_count == 3'd7)
                        //     sda_en <= 1'b0;
                    end else if (phase_wa) begin
                        data      <= {data[6:0], 1'b0};
                        sda       <= data[6];

                        if (bit_count == 3'd7) begin
                            state  <= SACK;
                            sda_en <= 1'b0;
                        end else begin
                            bit_count <= bit_count + 1;
                        end
                    end
                end
                SACK: begin
                    if (phase_hi) begin
                        scl    <= 1'b1;
                        sda    <= 1'b0;
                    end else if (phase_lo) begin
                        scl    <= 1'b0;
                        sda    <= 1'b0;
                    end else if (phase_sa) begin
                        if (!io_sda)
                            error <= 1'b0;
                    end else if (phase_wa) begin
                        state  <= IDLE;
                        sda_en <= 1'b1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    assign o_busy  = (state == XMIT) || (state == SACK);
    assign io_sda  = sda_en ? sda : 1'bz;
    assign o_scl   = scl;
    assign o_error = error;
endmodule
