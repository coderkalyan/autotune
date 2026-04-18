#!/usr/bin/env python3
"""
Generate a SystemVerilog priority encoder case statement for configurable bit width.
"""

import math


def generate_priority_encoder(width: int, msb_priority: bool = True) -> str:
    """
    Generate a SystemVerilog priority encoder module.
    
    Args:
        width: Number of input bits (must be a power of 2)
        msb_priority: If True, MSB has highest priority; if False, LSB has highest priority
    
    Returns:
        SystemVerilog module as a string
    """
    out_width = math.ceil(math.log2(width))
    lines = []

    # Module header
    lines.append(f"module priority_encoder_{width} (")
    lines.append(f"    input  logic [{width-1}:0] in,")
    lines.append(f"    output logic [{out_width-1}:0]   out,")
    lines.append(f"    output logic         valid")
    lines.append(f");")
    lines.append(f"")
    lines.append(f"    always_comb begin")
    lines.append(f"        valid = 1'b1;")
    lines.append(f"        casez (in)")

    # Generate case arms
    if msb_priority:
        priority_order = range(width - 1, -1, -1)  # MSB first (highest priority)
    else:
        priority_order = range(width)  # LSB first (highest priority)

    for i in priority_order:
        # Build the bit pattern
        pattern = []
        for bit in range(width - 1, -1, -1):
            if bit > i:
                pattern.append('0')  # Must be 0 (higher priority bits)
            elif bit == i:
                pattern.append('1')  # This bit is set
            else:
                pattern.append('?')  # Don't care (lower priority bits)

        pattern_str = ''.join(pattern)
        
        # Format with underscores every 8 bits for readability
        formatted = '_'.join(pattern_str[j:j+8] for j in range(0, len(pattern_str), 8))
        
        out_val = i
        lines.append(f"            {width}'b{formatted}: out = {out_width}'d{out_val};")

    # Default case
    lines.append(f"            default: begin")
    lines.append(f"                out   = {out_width}'d0;")
    lines.append(f"                valid = 1'b0;")
    lines.append(f"            end")
    lines.append(f"        endcase")
    lines.append(f"    end")
    lines.append(f"")
    lines.append(f"endmodule")

    return '\n'.join(lines)


lines = generate_priority_encoder(64, msb_priority=True)
print(lines)
