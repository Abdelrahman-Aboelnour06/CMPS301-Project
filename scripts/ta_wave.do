# =============================================================================
# ta_wave.do -- Clean TA Demo Waveform for CMPS 301
# Signals required by spec: CLK, Reset, Interrupt, IN.port, Out.port, PC, SP,
# Flags (CCR), and R0-R7.
#
# Usage in QuestaSim GUI Transcript (from cmps301 root):
#   do scripts/ta_wave.do
#   do scripts/ta_wave.do programs/ta_test1.mem programs/ta_test1.golden 12345678 -1
# =============================================================================

set mem_file    "programs/test2.mem"
set golden_file "programs/test2.golden"
set in_val      "00000300"
set irq_cyc     "-1"

if {$argc >= 1} { set mem_file    $1 }
if {$argc >= 2} { set golden_file $2 }
if {$argc >= 3} { set in_val      $3 }
if {$argc >= 4} { set irq_cyc     $4 }

vsim -t ps -gMEM_FILE=$mem_file -gGOLDEN_FILE=$golden_file -gIN_VALUE=$in_val -gIRQ_CYCLE=$irq_cyc work.tb_system

set NumericStdNoWarnings 1

add wave -noupdate -label "CLK"       /tb_system/dut/clk
add wave -noupdate -label "Reset"     /tb_system/dut/reset
add wave -noupdate -label "Interrupt" /tb_system/dut/intr_in
add wave -noupdate -radix hex -label "IN.port"  /tb_system/dut/in_port
add wave -noupdate -radix hex -label "Out.port" /tb_system/dut/out_port
add wave -noupdate -radix hex -label "PC"       /tb_system/dut/pc_out
add wave -noupdate -radix hex -label "SP"       /tb_system/dut/sp_out
add wave -noupdate -radix bin -label "Flags(C,N,Z)" /tb_system/dut/ccr_out
add wave -noupdate -radix hex -label "R0-R7"    /tb_system/R_logical

run -all
wave zoom full
