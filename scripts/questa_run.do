# Run one testbench in Questa with the standard waveform set.
#   vsim -do "do scripts/questa_compile.do; do scripts/questa_run.do tb_top"
if {$argc > 0} { set tb $1 } else { set tb tb_top }
vsim -t ps work.$tb
if {[string match "tb_top" $tb] || [string match "tb_system" $tb]} {
    add wave -radix hex /$tb/clk /$tb/reset /$tb/intr_in /$tb/halted
    add wave -radix hex /$tb/dut/pc_out /$tb/dut/sp_out /$tb/dut/ccr_out /$tb/dut/out_port
    add wave -radix hex /$tb/dut/R_values
    add wave -radix hex -group fetch  /$tb/dut/pc_q /$tb/dut/instr /$tb/dut/ifd.valid /$tb/dut/ifd.is_vec
    add wave -radix hex -group hazard /$tb/dut/stall /$tb/dut/mispredict /$tb/dut/d_redirect \
                                      /$tb/dut/fetch_hold /$tb/dut/d_inject /$tb/dut/intr_pending /$tb/dut/in_isr
    add wave -radix hex -group fwd    /$tb/dut/fsel_a /$tb/dut/fsel_b /$tb/dut/fa /$tb/dut/fb
} else {
    add wave -r /$tb/*
}
run -all
