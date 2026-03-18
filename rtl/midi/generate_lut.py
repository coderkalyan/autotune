
def frequency(note):
    return 440.0 * (2.0 ** ((note - 69) / 12.0))

# Q11.16 fixed-point: multiply by 2^16 = 65536
# fixed_t is signed [26:0], so max positive value is 2^26 - 1
MAX_Q1116 = 2**26 - 1

print("module midi_freq_lut (")
print("    input [6:0] note,")
print("    output reg [26:0] frequency")
print(");")
print("")
print("    always @(*) begin")
print("        case (note)")
for i in range(128):
    freq = frequency(i)
    scaled = int(round(freq * 65536))
    clamped = min(scaled, MAX_Q1116)
    print(f"            7'd{i}: frequency = 27'd{clamped};")
print("            default: frequency = 27'd0;")
print("        endcase")
print("    end")
print("")
print("endmodule")
