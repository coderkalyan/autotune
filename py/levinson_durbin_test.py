import numpy as np

def levinson_durbin(r):
    """
    Solve the Yule-Walker system using Levinson-Durbin recursion.
    
    r: autocorrelation sequence [r0, r1, r2, ..., rp]
       where r0 is lag-0, r1 is lag-1, etc.
    
    Returns: AR coefficients [a1, a2, ..., ap]
    """
    p = len(r) - 1  # AR model order
    
    a = np.zeros(p)          # AR coefficients
    a[0] = -r[1] / r[0]     # Initialize with order-1 solution
    
    error = r[0] + r[1] * a[0]  # Prediction error (starts at r0, decreases)
    
    for i in range(1, p):
        # Compute reflection coefficient
        #   = -(next autocorr + dot of current coeffs with reversed autocorr) / error
        k = -(r[i+1] + np.dot(a[:i], r[1:i+1][::-1])) / error
        
        # Update coefficients using the reflection coefficient
        # New coeffs = old coeffs + k * (old coeffs reversed)
        a[:i+1] = np.append(a[:i], 0) + k * np.append(a[:i][::-1], 1)
        
        # Update prediction error
        error *= (1 - k**2)
    
    return a


# --- Worked Example ---

# Suppose we have a time series with this autocorrelation structure:
r = [1.0, 0.8, 0.5, 0.2]   # [r0, r1, r2, r3] -- lag 0 through lag 3

# This defines the Toeplitz system:
#
# | r0  r1  r2 | | a1 |   | r1 |
# | r1  r0  r1 | | a2 | = -| r2 |
# | r2  r1  r0 | | a3 |   | r3 |
#
# i.e., find AR coefficients such that the model fits this autocorrelation

T = np.array([
    [r[0], r[1], r[2]],
    [r[1], r[0], r[1]],
    [r[2], r[1], r[0]],
])
b = np.array([-r[1], -r[2], -r[3]])

# Solve with Levinson-Durbin
a_ld = levinson_durbin(r)

# Solve with numpy (brute force) for verification
a_np = np.linalg.solve(T, b)

print("Toeplitz matrix T:")
print(T)
print()
print(f"RHS vector b:         {b}")
print(f"Levinson-Durbin:      {a_ld.round(6)}")
print(f"numpy.linalg.solve:   {a_np.round(6)}")
print(f"Results match: {np.allclose(a_ld, a_np)}")