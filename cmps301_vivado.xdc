# =============================================================================
# cmps301_vivado.xdc -- Vivado Timing & Implementation Constraints for `top`
#
# Notes:
#   1. `top` exposes 392 I/O ports (including 8x32-bit R_values, pc_out, sp_out)
#      for simulation/testbench observation. This XDC provides full timing
#      constraints for Vivado Synthesis, Implementation, Utilization (LUTs/FFs/
#      BRAMs), and Static Timing Analysis on any 7-series/UltraScale part
#      (e.g., Artix-7 xc7a100t / xc7a35t, Zynq xc7z020, or Virtex-7 xc7vx485t).
#   2. If you want to generate a .bit file for a physical board, wrap `top` in a
#      small `fpga_top` that maps switches/buttons/LEDs to `in_port`/`out_port`
#      and uncomment the board pin section below.
# =============================================================================

# --- Primary Clock: 50 MHz (20.0 ns period, matching DE1-SoC CLOCK_50) ---
create_clock -period 20.000 -name sys_clk -waveform {0.000 10.000} [get_ports clk]

# --- Input / Output Delay Constraints (relative to sys_clk) ---
set_input_delay  -clock sys_clk -max 2.000 [get_ports {reset intr_in in_port[*]}]
set_input_delay  -clock sys_clk -min 0.500 [get_ports {reset intr_in in_port[*]}]

set_output_delay -clock sys_clk -max 2.000 [get_ports {out_port[*] pc_out[*] sp_out[*] ccr_out[*] halted R_values[*][*]}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {out_port[*] pc_out[*] sp_out[*] ccr_out[*] halted R_values[*][*]}]

# --- Asynchronous / Pushbutton Inputs ---
set_false_path -from [get_ports {reset intr_in}]
