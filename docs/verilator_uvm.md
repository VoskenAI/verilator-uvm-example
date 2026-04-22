# UVM with Verilator — Patterns Reference

> Knowledge file for AI-assisted UVM testbench development under Verilator.
> Maintained by [Vosken.AI](https://vosken.ai) — Design Hardware at the Speed of Thought.

---

## Environment Setup

### Required Verilator flags

```makefile
VERILATOR_FLAGS = \
    -Wno-fatal                    \
    --cc                          \   # generate C++ model (use with --exe and --build)
    --exe sim_main.cpp            \   # custom C++ harness — required for FST trace output
    --build                       \   # compile immediately after elaboration
    --timing                      \   # fork/join, @(posedge clk), #n delays
    -j $(JOBS)                    \
    --top-module tb_top           \
    --trace-fst                   \   # add FST trace capability to generated model
    --trace-structs               \
    +incdir+$(UVM_HOME)           \
    +define+UVM_NO_DPI            \   # disable DPI-C bridge (required)
    +incdir+$(DV_DIR)             \
    +incdir+$(DV_DIR)/if          \
    +incdir+$(DV_DIR)/env         \
    +incdir+$(DV_DIR)/tests
```

**`--binary` vs `--cc --exe sim_main.cpp --build`**: `--binary` tells Verilator to generate its own `main()` and is fine for running tests. However, Verilator's generated main does **not** open an FST trace file — `--trace-fst` only adds trace *capability* to the model; the `main()` must also call `tfp->open("dump.fst")`. Use a custom `sim_main.cpp` (25 lines) whenever you need waveform output.

**`+define+UVM_NO_DPI`** — mandatory. Without it Verilator fails because UVM tries to import DPI-C symbols that don't exist in a Verilator build.

**`--timing`** — mandatory for any time-consuming operation: `fork/join`, `@(event)`, `#n` delays. Without it the scheduler is purely combinational and UVM phases that wait on time will hang or produce incorrect results.

### Source compilation order

```makefile
SOURCES = $(UVM_HOME)/uvm_pkg.sv \
          $(DV_DIR)/tb_pkg.sv    \
          $(TB_DIR)/tb_top.sv
```

UVM library must be first, then your project package, then the top-level module. Verilator elaborates them left to right.

### C++ simulation harness

A minimal `sim_main.cpp` is required to open the FST trace file:

```cpp
#include "verilated.h"
#include "Vtb_top.h"           // generated — name matches --top-module
#include "verilated_fst_c.h"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);   // forwards +UVM_TESTNAME= and other plusargs

    const std::unique_ptr<Vtb_top> topp{new Vtb_top{contextp.get(), ""}};

    VerilatedFstC* tfp = new VerilatedFstC;
    topp->trace(tfp, 99);
    tfp->open("dump.fst");

    while (!contextp->gotFinish()) {
        topp->eval();
        tfp->dump(contextp->time());
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());   // advance time — required with --timing
    }

    topp->final();
    tfp->dump(contextp->time());
    tfp->close();
    delete tfp;
    contextp->statsPrintSummary();
    return 0;
}
```

---
