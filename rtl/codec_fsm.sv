
module codec_fsm #(
    parameter P24_BIT = 1
) (
    input logic i_clk_50M,              // 50Mhz clk from FPGA 
    input logic i_rst,                  // Synchronous Active High Reset
    input logic i_busy,                 // Busy signal from I2C Master
    input logic i_nack,                // Flag from I2C indicating NACK
    
    output logic [2:0] o_state,
    output logic o_start_transaction,   // Flag to start transaction on I2C
    output logic [7:0] o_addr,          // Address of register to configure
    output logic [7:0] o_data,          //  
    output logic o_config_done,         // Flag indicating configuration is done
    output logic o_config_err           // Flag indicating error during configuration             
);


///////////////////////
// PARAM DEFINITIONS //
///////////////////////

// LINE CONFIG 
localparam logic LINMUTE = 0;
localparam logic RINMUTE = 0;
localparam logic [4:0] LINVOL  = 5'b11111; // default
localparam logic [4:0] RINVOL  = 5'b11111; // default

// MIC-IN CONFIGURATION
localparam logic MICBOOST = 0;          // default
localparam logic MUTEMIC = 0;
localparam logic INSEL= 0;

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
localparam logic [1:0] FORMAT = 2'd2;         // default - I2C
localparam logic [1:0] IWL = P24_BIT ? 2'd2 : 2'd0;    
localparam logic LRP = 0;               // default         
localparam logic LRSWAP = 0;            // default
localparam logic MS = 0;                // default
localparam logic BCLKINV = 0;           // default

// SAMPLE RATE CONTROL
localparam logic NORMAL = 0;            // set to give 48khz sampling rate on NORMAL MODE
localparam logic BOSR = 0;              // ADC and DAC
localparam logic [3:0] SR = 4'd0; 

// ACTIVATING DIGITAL AUDIO INTERFACE
localparam logic ACTIVE = 1;

// POWER DOWN
localparam logic LINEINPD = 0;          
localparam logic MICPD = 0;             // default
localparam logic ADCPD = 0;
localparam logic DACPD = 0;
localparam logic OUTPD = 0;
localparam logic OSCPD = 0;             // default
localparam logic CLKOUTPD = 0;          // default
localparam logic POWEROFF = 0;

// REGISTERS AND DATA
localparam logic [7:0] LEFT_LINE_IN_ADDR = {7'h00,1'b0};
localparam logic [7:0] RIGHT_LINE_IN_ADDR = {7'h01,1'b0};
localparam logic [7:0] ANALOG_PATH_CNTRL_ADDR = {7'h04,1'b0};
localparam logic [7:0] DIGITAL_PATH_CNTRL_ADDR = {7'h05,1'b0};
localparam logic [7:0] POWER_DOWN_CNTRL_ADDR = {7'h06,1'b0};
localparam logic [7:0] DIGITAL_INTERFACE_FORMAT_ADDR = {7'h07,1'b0}; 
localparam logic [7:0] SAMPLE_CNTRL_ADDR = {7'h08,1'b0};
localparam logic [7:0] ACTIVE_CNTRL_ADDR = {7'h09,1'b0};

localparam logic [7:0] LEFT_LINE_IN_DATA = {
    LINMUTE,
    2'd0,
    LINVOL
};
localparam logic [7:0] RIGHT_LINE_IN_DATA = {
    RINMUTE,
    2'd0,
    RINVOL
};
localparam logic [7:0] ANALOG_PATH_CNTRL_DATA = {
    2'd0,
    SIDETONE,
    DACSEL,
    BYPASS,
    INSEL,
    MUTEMIC,
    MICBOOST
};
localparam logic [7:0] DIGITAL_PATH_CNTRL_DATA= {
    3'd0,
    HPOR,
    DACMU,
    DEEMPH,
    ADCHPD
};
localparam logic [7:0] POWER_DOWN_CNTRL_DATA= {
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
    BCLKINV,
    MS,
    LRSWAP,
    LRP,
    IWL,
    FORMAT
};
localparam logic [7:0] SAMPLE_CNTRL_DATA = {
    2'd0,
    SR, 
    BOSR, 
    NORMAL
};
localparam logic [7:0] ACTIVE_CNTRL_DATA= {
    7'd0,
    ACTIVE
};

localparam logic [7:0] POWER_DOWN_STARTUP_DATA = {
    1'b0,
    1'b0,
    1'b0,
    1'b1,      // default output to 1
    1'b0,
    1'b0,
    1'b0,
    1'b0
};

// STARTUP SEQUENCE //
logic [7:0] REGISTER_DATA [0:9] = '{
    8'h0,
    POWER_DOWN_STARTUP_DATA,            // Enable all (other than output) 
    LEFT_LINE_IN_DATA,                  // Set rest of registers
    RIGHT_LINE_IN_DATA,
    ANALOG_PATH_CNTRL_DATA,             
    DIGITAL_PATH_CNTRL_DATA,
    DIGITAL_INTERFACE_FORMAT_DATA,
    SAMPLE_CNTRL_DATA,
    POWER_DOWN_CNTRL_DATA,               // Enable outptu
    ACTIVE_CNTRL_DATA                  
};

logic [7:0] REGISTER_ADDR [0:9] = '{
    {7'b0001111, 1'b0},
    POWER_DOWN_CNTRL_ADDR,
    LEFT_LINE_IN_ADDR,
    RIGHT_LINE_IN_ADDR,
    ANALOG_PATH_CNTRL_ADDR,
    DIGITAL_PATH_CNTRL_ADDR,
    DIGITAL_INTERFACE_FORMAT_ADDR,
    SAMPLE_CNTRL_ADDR,
    POWER_DOWN_CNTRL_ADDR,
    ACTIVE_CNTRL_ADDR
};



///////////////////////
// STATE MACHINE     //
///////////////////////

localparam int unsigned PWRUP_DELAY_CYC = 50_000_000 / 100; // ~10ms
logic [$clog2(PWRUP_DELAY_CYC+1)-1:0] pwr_cnt;
logic [3:0] idx;
logic inc_power_up;
logic inc_idx;
logic start;

always @(posedge i_clk_50M) begin 
    if (i_rst) 
        pwr_cnt <= '0;
    else if (inc_power_up)
        pwr_cnt <= pwr_cnt + 1'b1;
end

always @(posedge i_clk_50M) begin 
    if (i_rst) 
        idx <= '0;
    else if (inc_idx)
        idx <= idx + 1'b1;
end

always @(posedge i_clk_50M) begin 
     if (i_rst) 
        o_start_transaction <= 1'b0;
    else 
        o_start_transaction <= start;
end

typedef enum logic [2:0] {
    INIT,
    LOAD,
    WAIT, 
    DONE, 
    ERROR
} state_t;

state_t state, next_state;

always @(posedge i_clk_50M) begin 
    if (i_rst)
        state <= INIT;
    else if (i_busy && i_nack)
        state <= ERROR;
    else 
        state <= next_state;
end 

always_comb begin 
    next_state = state;
    start = 1'b0;
    o_config_done = 1'b0;
    o_config_err = 1'b0;
    inc_power_up = 1'b0;
    inc_idx = 1'b0;
    o_addr = 8'h00;
    o_data = 8'h00;

    case(state)
        INIT: begin 
            inc_power_up = 1'b1;
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
                if (idx == 4'd9) begin 
                    next_state = DONE;
                end else begin 
                    inc_idx = 1'b1;
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
            o_config_done = 1'b1;
            next_state = ERROR;
        end 
        default: next_state = LOAD;
    endcase
end

assign o_state = state;
endmodule
