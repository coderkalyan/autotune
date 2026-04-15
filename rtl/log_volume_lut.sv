module log_volume_lut (
    input  wire [6:0] i_linear,
    output wire [6:0] o_log
);
  logic [6:0] lut[128];
  initial $readmemh("log_volume.mem", lut);

  assign o_log = lut[i_linear];
endmodule
