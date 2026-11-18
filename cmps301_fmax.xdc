# Minimal XDC for Fmax testing (Out-of-Context / internal critical path)
# Target: 200 MHz (5.0 ns) so Vivado pushes timing optimization on the critical path.
# Calculate Fmax from WNS:  Fmax (MHz) = 1000 / (5.0 - WNS)

create_clock -period 10.000 -name sys_clk [get_ports clk]
