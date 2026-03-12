// Q11.16 fixed point representation.
typedef logic signed [26:0] fixed_t;

// 16 bit signed integer audio.
typedef logic signed [15:0] audio_t;

function automatic fixed_t fixed_mul(input fixed_t a, input fixed_t b);
    logic signed [53:0] product = a * b;
    return product[16 +: 27];
endfunction

function automatic fixed_t fixed_rtof(input real x);
    return x * real'(1 << 16);
endfunction

function automatic real fixed_ftor(input fixed_t x);
    return real'(x) / real'(1 << 16);
endfunction

`define FIXED_RTOF(x) fixed_t'(x * real'(1 << 16))
`define FIXED_FTOR(x) real'(x) / real'(1 << 16)

function automatic fixed_t fixed_atof(input audio_t x);
    return 27'(x) << 6;
endfunction

function automatic audio_t fixed_ftoa(input fixed_t x);
    return x[6 +: 16];
endfunction
