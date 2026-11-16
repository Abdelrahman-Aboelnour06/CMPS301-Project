# =============================================================================
# CMPS 301 six-stage pipelined processor -- GHDL build
#
#   make all              analyse everything, run every testbench, exit 0 only
#                         if all of them print PASS
#   make <module>         run tb/tb_<module>.vhd   (e.g. make alu, make top)
#   make hazards          pipeline hazard integration test
#   make system           run programs/demo.mem against programs/demo.golden
#   make system MEM=programs/foo.mem GOLDEN=programs/foo.golden IRQ=-1
#   make spec             rebuild doc/spec.pdf (pdflatex, two passes)
#   make clean
# =============================================================================
GHDL     ?= ghdl
WORK     := build
GFLAGS   := --std=08 --workdir=$(WORK)
RUNFLAGS := --assert-level=error --ieee-asserts=disable-at-0

MEM      ?= programs/demo.mem
GOLDEN   ?= programs/demo.golden
IN       ?= 0000ABCD
IRQ      ?= 40

# analysis order (dependencies first)
RTL_ORDER := cpu_pkg pc pc_mux data_mem instr_mem if_d regfile control alu \
             ccr addr_adder sp_unit branch_check forward_unit hazard_unit \
             reset_fsm intr_fsm d_x1 x1_x2 x2_m m_w top
RTL_SRC   := $(addprefix rtl/,$(addsuffix .vhd,$(RTL_ORDER)))

# one testbench per RTL module (+ integration benches)
MODULES   := pc pc_mux instr_mem if_d regfile control hazard_unit d_x1 \
             forward_unit alu ccr x1_x2 addr_adder sp_unit branch_check x2_m \
             data_mem m_w reset_fsm intr_fsm top
TESTS     := $(MODULES) hazards system
TB_SRC    := tb/tb_pkg.vhd $(addprefix tb/tb_,$(addsuffix .vhd,$(TESTS)))

.PHONY: all analyze spec clean $(TESTS)

all: analyze
	@pass=0; fail=0; failed=""; \
	for t in $(TESTS); do \
	  if $(MAKE) --no-print-directory run-$$t; then pass=$$((pass+1)); \
	  else fail=$$((fail+1)); failed="$$failed $$t"; fi; \
	done; \
	echo "=================================================="; \
	echo " testbenches passed: $$pass   failed: $$fail $$failed"; \
	echo "=================================================="; \
	test $$fail -eq 0

analyze: $(WORK)/.analyzed

$(WORK)/.analyzed: $(RTL_SRC) $(TB_SRC)
	@mkdir -p $(WORK)
	$(GHDL) -a $(GFLAGS) $(RTL_SRC)
	$(GHDL) -a $(GFLAGS) $(TB_SRC)
	@touch $@

run-%: analyze
	$(GHDL) -e $(GFLAGS) tb_$*
	$(GHDL) -r $(GFLAGS) tb_$* $(RUNFLAGS)

run-system: analyze
	$(GHDL) -e $(GFLAGS) tb_system
	$(GHDL) -r $(GFLAGS) tb_system $(RUNFLAGS) -gMEM_FILE=$(MEM) \
	  -gGOLDEN_FILE=$(GOLDEN) -gIN_VALUE=$(IN) -gIRQ_CYCLE=$(IRQ)

$(TESTS): %: run-%

spec:
	cd doc && pdflatex -interaction=nonstopmode spec.tex >/dev/null && \
	          pdflatex -interaction=nonstopmode spec.tex >/dev/null
	@echo "doc/spec.pdf rebuilt"

clean:
	rm -rf $(WORK) e~*.o *.o *.cf tb_* work
	rm -f doc/*.aux doc/*.log doc/*.out doc/*.toc
