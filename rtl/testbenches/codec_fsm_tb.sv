module codec_fsm_tb();

// SIGNALS
logic i_clk_50M;              // 50Mhz clk from FPGA 
logic i_rst;                  // Synchronous Active High Reset
logic i_busy;                 // Busy signal from I2C Master
logic i_nack;
    
logic o_start_transaction;    // Flag to start transaction on I2C
logic [6:0] o_addr;           // Address of register to configure
logic [7:0] o_data;           //  
logic o_config_done;          // Flag indicating configuration is done
logic o_config_err;           // Flag indicating error during configuration

// DUT 
codec_fsm #(
    .P24_BIT(1)
) iFSM (
    .i_clk_50M(i_clk_50M),              
    .i_rst(i_rst),                 
    .i_busy(i_busy),    
    .i_nack(i_nack),             
    .o_start_transaction(o_start_transaction),   
    .o_addr(o_addr),          
    .o_data(o_data),           
    .o_config_done(o_config_done),         
    .o_config_err(o_config_err)                        
);

task automatic set_busy();
    i_busy = 1'b1;
endtask

task automatic release_busy();
    i_busy = 1'b0;
endtask

initial begin 
    i_clk_50M = 0;
    i_rst = 1;
    i_nack = 0;
    i_busy = 0;

    repeat (10) @(posedge i_clk_50M);
    i_rst = 0;

    // CASE 1: NO ERROR DURING CONFIGURATION

    fork
        begin 
            forever begin 
                @(posedge o_start_transaction);
                @(posedge i_clk_50M);
                set_busy();
                repeat (10) @(posedge i_clk_50M);
                release_busy();
                @(posedge i_clk_50M);
            end
        end 
        begin 
            @(posedge o_config_done);
        end
    join_any
 
    
    // CASE 2: ERROR DURING CONFIGURATION
    @(negedge i_clk_50M) i_rst = 1;

    repeat (10) @(posedge i_clk_50M);
    i_rst = 0;

    fork
        begin 
            forever begin 
                @(posedge o_start_transaction);
                set_busy();
                repeat (10) @(posedge i_clk_50M);
                release_busy();
            end
        end 
        begin 
            #50 i_nack = 1'b1;
            @(posedge o_config_err);
            $display("Config Error finished first");
        end
        begin 
            @(posedge o_config_done);
            $display("Config done finished first");
        end
    join_any

    $display("FINISHED CASES: EXAMINE WAVEFORMS FOR CORRECTNESS");
    $stop();
end

always begin
    #10 i_clk_50M = ~i_clk_50M;
end

endmodule