module codec_fsm #(
    parameter P24_BIT = 1
)(
    input logic i_clk_50M,              // 50Mhz clk from FPGA 
    input logic i_rst,                  // Synchronous Active High Reset
    input logic i_busy,                 // Busy signal from I2C Master
    input logic i_nack,                // Flag from I2C indicating NACK
    
    output logic o_start_transaction,   // Flag to start transaction on I2C
    output logic [6:0] o_addr,          // Address of register to configure
    output logic [7:0] o_data,          //  
    output logic o_config_done,         // Flag indicating configuration is done
    output logic o_config_err           // Flag indicating error during configuration             
);


///////////////////////
// PARAM DEFINITIONS //
///////////////////////

// MIC-IN CONFIGURATION
localparam logic MICBOOST = 0;          // default
localparam logic MUTEMIC = 0;
localparam logic INSEL= 1;

// ADC SW CONTROL
localparam logic ADCHPD = 0;            // default
localparam logic HPOR = 0;              // default

// DAC SW CONTROL 
localparam logic [1:0] DEEMPH = 2'd0;   // default
localparam logic DACMU = 0;

// OUTPUT SW CONTROL 
localparam logic BYPASS = 0;
localparam logic DACSEL = 1;
localparam logic SIDETONE = 0;          // default

// DIGITAL AUDIO INTERFACE CONTROL
localparam logic FORMAT = 2'd2;         // default - I2C
localparam logic IWL = P24_BIT ? 2'd2 : 2'd0;    
localparam logic LRP = 0;               // default         
localparam logic LRSWAP = 0;            // default
localparam logic MS = 0;                // default
localparam logic BCLKINV = 0;           // default

// SAMPLE RATE CONTROL
localparam logic NORMAL = 1;            // set to give 48khz sampling rate on 
localparam logic BOSR = 0;              // ADC and DAC
localparam logic [3:0] SR = 4'd0; 

// ACTIVATING DIGITAL AUDIO INTERFACE
localparam logic ACTIVE = 1;

// POWER DOWN
localparam logic LINEINPD = 1;          // default
localparam logic MICPD = 0;
localparam logic ADCPD = 0;
localparam logic DACPD = 0;
localparam logic OUTPD = 0;
localparam logic OSCPD = 0;             // default
localparam logic CLKOUTPD = 0;          // default
localparam logic POWEROFF = 0;

// REGISTERS AND DATA

localparam logic [6:0] CODEC_ADDR = 7'h1A;  //CSB pin determines addr, tied to gnd

localparam logic [6:0] ANALOG_PATH_CNTRL_ADDR = 7'h04;
localparam logic [6:0] DIGITAL_PATH_CNTRL_ADDR = 7'h05;
localparam logic [6:0] POWER_DOWN_CNTRL_ADDR = 7'h06;
localparam logic [6:0] DIGITAL_INTERFACE_FORMAT_ADDR = 7'h07; 
localparam logic [6:0] SAMPLE_CNTRL_ADDR = 7'h08;
localparam logic [6:0] ACTIVE_CNTRL_ADDR = 7'h09;


localparam logic [7:0] ANALOG_PATH_CNTRL_DATA = {
    3'd0, 
    SIDETONE,
    DACSEL,
    BYPASS,
    INSEL,
    MUTEMIC,
    MICBOOST
};
localparam logic [7:0] DIGITAL_PATH_CNTRL_DATA= {
    4'd3,
    HPOR,
    DACMU,
    DEEMPH,
    ADCHPD
};
localparam logic [7:0] POWER_DOWN_CNTRL_DATA= {
    1'd0,
    POWEROFF,
    CLKOUTPD,
    OSCPD,
    OUTPD,
    DACPD,
    ADCPD,
    MICPD,
    LINEINPD
};
localparam logic [7:0] DIGITAL_INTERFACE_FORMAT_DATA= {
    1'd0,
    BCLKINV,
    MS,
    LRSWAP,
    LRP,
    IWL,
    FORMAT
};
localparam logic [7:0] SAMPLE_CNTRL_DATA = {
    3'd0,
    SR, 
    BOSR, 
    NORMAL
};
localparam logic [7:0] ACTIVE_CNTRL_DATA= {
    7'd0,
    ACTIVE
};

logic [7:0] REGISTER_DATA [0:5] = '{
    ANALOG_PATH_CNTRL_DATA,
    DIGITAL_PATH_CNTRL_DATA,
    POWER_DOWN_CNTRL_DATA,
    DIGITAL_INTERFACE_FORMAT_DATA,
    SAMPLE_CNTRL_DATA,
    ACTIVE_CNTRL_DATA
};

logic [6:0] REGISTER_ADDR [0:5] = '{
    ANALOG_PATH_CNTRL_ADDR,
    DIGITAL_PATH_CNTRL_ADDR,
    POWER_DOWN_CNTRL_ADDR,
    DIGITAL_INTERFACE_FORMAT_ADDR,

    SAMPLE_CNTRL_ADDR,
    ACTIVE_CNTRL_ADDR
};



///////////////////////
// STATE MACHINE     //
///////////////////////

localparam int unsigned PWRUP_DELAY_CYC = 50_000_000 / 100; // ~10ms
logic [$clog2(PWRUP_DELAY_CYC+1)-1:0] pwr_cnt;
logic [2:0] idx;
logic inc;
logic start;

always @(posedge i_clk_50M) begin 
    if (i_rst) 
        pwr_cnt <= '0;
    else if (inc)
        pwr_cnt <= pwr_cnt + 1'b1;
end

always @(posedge i_clk_50M) begin 
    if (i_rst) 
        idx <= '0;
    else if (inc)
        idx <= idx + 1'b1;
end

always @(posedge i_clk_50M) begin 
     if (i_rst) 
        o_start_transaction <= 1'b0;
    else 
        o_start_transaction <= start;
end

typedef enum logic [2:0] {
    IDLE,
    LOAD,
    WAIT, 
    DONE, 
    ERROR
} state_t;

state_t state, next_state;

always @(posedge i_clk_50M) begin 
    if (i_rst)
        state <= LOAD;
    else if (i_nack)
        state <= ERROR;
    else 
        state <= next_state;
end 

always_comb begin 
    next_state = state;
    start = 1'b0;
    o_config_done = 1'b0;
    o_config_err = 1'b0;
    inc = 1'b0;
    o_addr = 7'h00;
    o_data = 8'h00;

    case(state)
        INIT: begin 
            // Delay for Power Up 
            if (pwr_cnt == PWRUP_DELAY_CYC-1) 
                next_state = LOAD;
        end
        LOAD: begin 
            // Set data and addr
            o_addr = REGISTER_ADDR[idx];
            o_data = REGISTER_DATA[idx];
            // Wait until not busy, then start transaction
            if (!i_busy) begin
                start = 1'b1;
                next_state = WAIT;
            end
        end
        WAIT: begin 
            // Hold Data Stable during configuration
            o_addr = REGISTER_ADDR[idx];
            o_data = REGISTER_DATA[idx];
            // Wait until transaction is done,
            if (!i_busy) begin 
                if (idx == 3'd5) begin 
                    next_state = DONE;
                end else begin 
                    inc = 1'b1;
                    next_state = LOAD;
                end  
            end
        end
        DONE: begin 
            o_config_done = 1'b1;
            next_state = DONE;
        end
        ERROR: begin 
            o_config_err = 1'b1;
            next_state = ERROR;
        end 
        default: next_state = LOAD;
    endcase
end

endmodule