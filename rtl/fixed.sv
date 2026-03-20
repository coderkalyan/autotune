`ifndef FIXED
`define FIXED

// Q11.16 fixed point representation.
typedef logic signed [26:0] fixed_t;

// Q32.16 fixed point representation.
typedef logic signed [47:0] fmac_t;

// 16 bit signed integer audio.
typedef logic signed [15:0] audio_t;

function automatic logic signed [53:0] fixed_mul_raw(input fixed_t a, input fixed_t b);
    logic signed [53:0] product = a * b;
    return product;
endfunction

function automatic fixed_t fixed_mul(input fixed_t a, input fixed_t b);
    logic signed [53:0] product = fixed_mul_raw(a, b);
    return fixed_t'(product[16 +: 27]);
endfunction

// Quartus dislikes the existance of functions on real types, even
// if they aren't used in synthesized code.
`ifdef SIMULATION
function automatic fixed_t fixed_rtof(input real x);
    return fixed_t'(x * real'(27'd1 << 16));
endfunction

function automatic real fixed_ftor(input fixed_t x);
    return real'(x) / real'(27'd1 << 16);
endfunction
`endif

`define FIXED_RTOF(x) fixed_t'(x * real'(1 << 16))
`define FIXED_FTOR(x) real'(x) / real'(1 << 16)

function automatic fixed_t fixed_atof(input audio_t x);
    return 27'(x) << 10;
endfunction

function automatic audio_t fixed_ftoa(input fixed_t x);
    return x[10 +: 16];
endfunction

`define FIXED_ATOF(x) (fixed_t'(x) << 10)
`define FIXED_FTOA(x) (x[10 +: 16])

`endif
