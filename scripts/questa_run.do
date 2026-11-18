# Run one testbench in Questa with the standard waveform set.
#   vsim -do "do scripts/questa_compile.do; do scripts/questa_run.do tb_top"
if {$argc > 0} { set tb $1 } else { set tb tb_top }
vsim -t ps work.$tb
if {[string match "tb_top" $tb] || [string match "tb_system" $tb]} {
    add wave -radix hex /$tb/clk /$tb/reset /$tb/intr_in /$tb/halted
    add wave -radix hex /$tb/dut/pc_out /$tb/dut/sp_out /$tb/dut/ccr_out /$tb/dut/out_port
    add wave -radix hex /$tb/dut/R_values
    add wave -radix hex -group fetch  /$tb/dut/current_pc /$tb/dut/instruction_word /$tb/dut/if_d_reg.is_valid /$tb/dut/if_d_reg.is_interrupt_vector
    add wave -radix hex -group hazard /$tb/dut/stall /$tb/dut/mispredict /$tb/dut/d_redirect \
                                      /$tb/dut/fetch_hold /$tb/dut/decode_inject_irq /$tb/dut/intr_pending /$tb/dut/in_isr
    add wave -radix hex -group fwd    /$tb/dut/forward_select_a /$tb/dut/forward_select_b /$tb/dut/forwarded_operand_a /$tb/dut/forwarded_operand_b
} else {
    add wave -r /$tb/*
}
run -all
