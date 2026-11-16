# =============================================================================
# compile.do -- QuestaSim/ModelSim compile script for the CMPS 301 processor
# Usage: do compile.do
# Assumes all .vhd files are in the current working directory.
# =============================================================================


# Create and map the working library
vlib work
vmap work work

# Use VHDL-2008 (the RTL also compiles as VHDL-93)
set VCOM_OPTS "-2008 -explicit -check_synthesis"

# -----------------------------------------------------------------------------
# Package first -- every other file depends on cpu_pkg
# -----------------------------------------------------------------------------
echo "Compiling cpu_pkg.vhd ..."
vcom {*}$VCOM_OPTS cpu_pkg.vhd

# -----------------------------------------------------------------------------
# Leaf / low-level entities (no dependency on top)
# -----------------------------------------------------------------------------
echo "Compiling pc.vhd ..."
vcom {*}$VCOM_OPTS pc.vhd

echo "Compiling pc_mux.vhd ..."
vcom {*}$VCOM_OPTS pc_mux.vhd

echo "Compiling instr_mem.vhd ..."
vcom {*}$VCOM_OPTS instr_mem.vhd

echo "Compiling if_d.vhd ..."
vcom {*}$VCOM_OPTS if_d.vhd

echo "Compiling control.vhd ..."
vcom {*}$VCOM_OPTS control.vhd

echo "Compiling regfile.vhd ..."
vcom {*}$VCOM_OPTS regfile.vhd

echo "Compiling alu.vhd ..."
vcom {*}$VCOM_OPTS alu.vhd

echo "Compiling ccr.vhd ..."
vcom {*}$VCOM_OPTS ccr.vhd

echo "Compiling forward_unit.vhd ..."
vcom {*}$VCOM_OPTS forward_unit.vhd

echo "Compiling d_x1.vhd ..."
vcom {*}$VCOM_OPTS d_x1.vhd

echo "Compiling x1_x2.vhd ..."
vcom {*}$VCOM_OPTS x1_x2.vhd

echo "Compiling addr_adder.vhd ..."
vcom {*}$VCOM_OPTS addr_adder.vhd

echo "Compiling sp_unit.vhd ..."
vcom {*}$VCOM_OPTS sp_unit.vhd

echo "Compiling branch_check.vhd ..."
vcom {*}$VCOM_OPTS branch_check.vhd

echo "Compiling data_mem.vhd ..."
vcom {*}$VCOM_OPTS data_mem.vhd

echo "Compiling x2_m.vhd ..."
vcom {*}$VCOM_OPTS x2_m.vhd

echo "Compiling m_w.vhd ..."
vcom {*}$VCOM_OPTS m_w.vhd

echo "Compiling hazard_unit.vhd ..."
vcom {*}$VCOM_OPTS hazard_unit.vhd

echo "Compiling intr_fsm.vhd ..."
vcom {*}$VCOM_OPTS intr_fsm.vhd

echo "Compiling reset_fsm.vhd ..."
vcom {*}$VCOM_OPTS reset_fsm.vhd

# -----------------------------------------------------------------------------
# Top level -- must be last because it instantiates every other entity
# -----------------------------------------------------------------------------
echo "Compiling top.vhd ..."
vcom {*}$VCOM_OPTS top.vhd

# -----------------------------------------------------------------------------
# Optional: load the top-level for simulation (comment out if not wanted)
# -----------------------------------------------------------------------------
# vsim -novopt work.top
# add wave -r /*
# run 1 us

echo "-------------------------------------------------------------"
echo "Compilation finished. Use 'vsim work.top' to start simulation."
echo "-------------------------------------------------------------"