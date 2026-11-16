# Questa / ModelSim: compile the RTL as VHDL-93 and the testbenches as
# VHDL-2008.  Usage (from the repository root):
#     vsim -c -do scripts/questa_compile.do
#     vsim -c -do "do scripts/questa_compile.do; do scripts/questa_run.do tb_alu"
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

set rtl {cpu_pkg pc pc_mux data_mem instr_mem if_d regfile control alu ccr
         addr_adder sp_unit branch_check forward_unit hazard_unit reset_fsm
         intr_fsm d_x1 x1_x2 x2_m m_w top}
foreach f $rtl { vcom -93 -work work rtl/$f.vhd }

set tbs {tb_pkg tb_pc tb_pc_mux tb_instr_mem tb_if_d tb_regfile tb_control
         tb_hazard_unit tb_d_x1 tb_forward_unit tb_alu tb_ccr tb_x1_x2
         tb_addr_adder tb_sp_unit tb_branch_check tb_x2_m tb_data_mem tb_m_w
         tb_reset_fsm tb_intr_fsm tb_top tb_hazards tb_system}
foreach f $tbs { vcom -2008 -work work tb/$f.vhd }
