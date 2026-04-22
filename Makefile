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

.PHONY: all compile run waves test clean help

help:
	@echo "Targets:"
	@echo "  all      - compile + run (default)"
	@echo "  compile  - elaborate with Verilator"
	@echo "  run      - run simulation (produces $(WAVE_FILE))"
	@echo "  test     - compile then run all tests via run_tests.sh"
	@echo "  waves    - open $(WAVE_FILE) in GTKWave"
	@echo "  clean    - remove generated files"
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
