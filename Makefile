UVM_HOME  ?= $(HOME)/opt/accellera/1800.2-2017-1.0/src
TESTNAME  ?= sig_model_test
TOP       := tbench_top
OBJ_DIR   := obj_dir
WAVE_FILE := dump.fst
JOBS      := $(shell sysctl -n hw.logicalcpu 2>/dev/null || echo 4)

DV_DIR := $(CURDIR)/dv
TB_DIR := $(CURDIR)/tb

VERILATOR_FLAGS = \
    -Wno-fatal                \
    --cc                      \
    --exe sim_main.cpp        \
    --build                   \
    --timing                  \
    -j $(JOBS)                \
    --top-module $(TOP)       \
    --trace-fst               \
    --trace-structs           \
    +incdir+$(UVM_HOME)       \
    +define+UVM_NO_DPI        \
    +incdir+$(DV_DIR)         \
    +incdir+$(DV_DIR)/if      \
    +incdir+$(DV_DIR)/env     \
    +incdir+$(DV_DIR)/tests

SOURCES = $(UVM_HOME)/uvm_pkg.sv $(DV_DIR)/sig_pkg.sv $(TB_DIR)/tb.sv

SV_DEPS = $(wildcard $(DV_DIR)/if/*.sv \
                     $(DV_DIR)/env/*.svh \
                     $(DV_DIR)/tests/*.svh)

# --- xsim (AMD/Xilinx Vivado Simulator) ----------------------------------
# Uses xsim's precompiled UVM 1.2 library (no UVM_HOME download needed).
# Requires `source /opt/Xilinx/Vivado/<ver>/settings64.sh` so xvlog/xelab/xsim
# are on PATH. XILINX_VIVADO is set by settings64.sh.
XSIM_SNAPSHOT := $(TOP)_sim
XSIM_UVM_INC  := $(XILINX_VIVADO)/data/system_verilog/uvm_1.2

XSIM_SV_FILES = $(DV_DIR)/if/sig_if.sv $(DV_DIR)/sig_pkg.sv $(TB_DIR)/tb.sv

XSIM_INCDIRS = -i $(XSIM_UVM_INC) -i $(DV_DIR) -i $(DV_DIR)/if \
               -i $(DV_DIR)/env -i $(DV_DIR)/tests

.PHONY: all compile run waves test clean help \
        xsim xsim_compile xsim_run xsim_test xsim_clean

help:
	@echo "Verilator targets:"
	@echo "  all      - compile + run (default)"
	@echo "  compile  - elaborate with Verilator"
	@echo "  run      - run simulation (produces $(WAVE_FILE))"
	@echo "  test     - compile then run all tests via run_tests.sh"
	@echo "  waves    - open $(WAVE_FILE) in GTKWave"
	@echo "  clean    - remove generated files"
	@echo ""
	@echo "xsim targets (Vivado must be sourced first):"
	@echo "  xsim         - xsim_compile + xsim_run"
	@echo "  xsim_compile - elaborate with xvlog + xelab"
	@echo "  xsim_run     - run simulation under xsim"
	@echo "  xsim_test    - run all tests via run_tests_xsim.sh"
	@echo "  xsim_clean   - remove xsim artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  TESTNAME=$(TESTNAME)  (override with make TESTNAME=other_test)"
	@echo "  UVM_HOME=$(UVM_HOME)"

all: compile run

compile: $(OBJ_DIR)/V$(TOP)

$(OBJ_DIR)/V$(TOP): $(SOURCES) $(SV_DEPS)
	verilator $(VERILATOR_FLAGS) $(SOURCES)

run: $(OBJ_DIR)/V$(TOP)
	$(OBJ_DIR)/V$(TOP) +UVM_TESTNAME=$(TESTNAME)

test: compile
	bash run_tests.sh

waves: $(WAVE_FILE)
	gtkwave $(WAVE_FILE) &

clean:
	rm -rf $(OBJ_DIR) $(WAVE_FILE)

xsim: xsim_compile xsim_run

xsim_compile:
	@if [ -z "$(XILINX_VIVADO)" ]; then \
	  echo "ERROR: XILINX_VIVADO not set. Source Vivado settings64.sh first."; \
	  exit 1; \
	fi
	xvlog --sv -L uvm $(XSIM_INCDIRS) $(XSIM_SV_FILES)
	xelab -L uvm --timescale 1ns/1ps $(TOP) -s $(XSIM_SNAPSHOT)

xsim_run:
	xsim $(XSIM_SNAPSHOT) -R --testplusarg "UVM_TESTNAME=$(TESTNAME)"

xsim_test: xsim_compile
	bash run_tests_xsim.sh

xsim_clean:
	rm -rf xsim.dir .Xil *.jou *.log *.pb *.wdb webtalk*.backup.jou webtalk*.backup.log
