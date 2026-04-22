# UVM with Verilator — Patterns Reference

> Knowledge file for AI-assisted UVM testbench development under Verilator.
> Maintained by [Vosken.AI](https://vosken.ai) — Design Hardware at the Speed of Thought.

---

## Environment Setup

### Required flags

```makefile
VERILATOR_FLAGS = \
    -Wno-fatal               \
    --cc                     \   # generate C++ model
    --exe sim_main.cpp       \   # C++ harness
    --build                  \   # compile after elaboration
    --timing                 \   # fork/join, @(posedge clk), delays
    -j $(JOBS)               \
    --top-module tbench_top  \
    --trace-fst              \   # FST waveform output
    --trace-structs          \
    +incdir+$(UVM_HOME)      \
    +define+UVM_NO_DPI       \   # disable DPI-C bridge
    +incdir+$(DV_DIR)        \
    +incdir+$(DV_DIR)/if     \
    +incdir+$(DV_DIR)/env    \
    +incdir+$(DV_DIR)/tests
```

**`+define+UVM_NO_DPI`** — mandatory. Without it Verilator fails because UVM tries to import DPI-C symbols that don't exist.

**`--timing`** — mandatory for any time-consuming operation: `fork/join`, `@(event)`, `#n` delays. Without it the scheduler is purely combinational and UVM phases that wait on time will hang.

### Source order

```makefile
SOURCES = $(UVM_HOME)/uvm_pkg.sv \
          $(DV_DIR)/sig_pkg.sv   \
          $(TB_DIR)/tb.sv
```

UVM library first, then your package, then the top module.

### C++ sim harness

```cpp
#include "verilated.h"
#include "Vtbench_top.h"
#include "verilated_fst_c.h"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);   // passes +UVM_TESTNAME= to the SV side

    const std::unique_ptr<Vtbench_top> topp{new Vtbench_top{contextp.get(), ""}};

    VerilatedFstC* tfp = new VerilatedFstC;
    topp->trace(tfp, 99);
    tfp->open("dump.fst");

    while (!contextp->gotFinish()) {
        topp->eval();
        tfp->dump(contextp->time());
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }

    topp->final();
    tfp->close();
    delete tfp;
    return 0;
}
```

`contextp->commandArgs(argc, argv)` is what makes `+UVM_TESTNAME=foo` reach `run_test()`. The eval loop calls `nextTimeSlot()` to advance simulated time, which is required for `--timing` mode.

---

## Package Structure

All UVM code lives in a single package (`sig_pkg.sv`) that `` `include ``s `.svh` files in dependency order. No file-level compilation units — everything is one package.

```systemverilog
package sig_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"   // if not already in uvm_pkg

  // Items and cfg objects first (no dependencies)
  `include "sig_item.svh"
  `include "long_sig_item.svh"
  `include "sig_cfg.svh"

  // Callback base class — must precede driver
  `include "sig_driver_cbs.svh"

  // Sequencer before sequences
  `include "sig_sequencer.svh"
  `include "sig_virt_sequencer.svh"
  `include "sig_sequence.svh"
  `include "sig_virt_sequence.svh"

  // Components
  `include "sig_driver.svh"
  `include "sig_monitor.svh"
  `include "sig_agent.svh"
  `include "sig_scoreboard.svh"
  `include "sig_coverage.svh"
  `include "sig_reg_block.svh"

  // Environments (base first, then derived)
  `include "sig_model_env.svh"
  `include "broadcast_env.svh"
  `include "passive_env.svh"

  // Tests last
  `include "sig_model_test.svh"
  `include "test_factory_override.svh"
  // ... more tests
endpackage : sig_pkg
```

---

## Top-Level Module Pattern

```systemverilog
module tbench_top;
  import uvm_pkg::*;
  import sig_pkg::*;

  bit clk;
  bit reset;

  always #5 clk = ~clk;           // 10-unit period

  initial begin
    reset = 1;
    #12 reset = 0;
  end

  sig_if intf (clk, reset);

  initial begin
    // Push typed virtual interface handles into config_db
    // Wildcard "*" makes them available to any component
    uvm_config_db#(virtual sig_if.DRIVER)::set(uvm_root::get(), "*", "vif", intf.DRIVER);
    uvm_config_db#(virtual sig_if.MONITOR)::set(uvm_root::get(), "*", "vif", intf.MONITOR);
  end

  initial begin
    run_test();   // picks up +UVM_TESTNAME from command line
  end
endmodule
```

Two separate `set()` calls for the same key `"vif"` with different parameterized types is fine — `uvm_config_db` is keyed on `{scope, key, type}`.

---

## Interface with Clocking Blocks

```systemverilog
interface sig_if (input logic clk, reset);
  logic sig;

  clocking driver_cb @(posedge clk);
    default input #1 output #1;
    output sig;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1 output #1;
    input sig;
  endclocking

  modport DRIVER  (clocking driver_cb, input clk, reset);
  modport MONITOR (clocking monitor_cb, input clk, reset);
endinterface
```

Using typed modports (`virtual sig_if.DRIVER` vs `virtual sig_if.MONITOR`) prevents the driver from accidentally reading signals and the monitor from driving them. Separate clocking blocks with `#1` input skew avoid race conditions with `always` blocks.

---

## Sequence Item

```systemverilog
class sig_seq_item extends uvm_sequence_item;
  rand bit [3:0] sig_length;
  constraint c_nonzero { sig_length > 0; }

  `uvm_object_utils_begin(sig_seq_item)
    `uvm_field_int(sig_length, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "sig_seq_item");
    super.new(name);
  endfunction
endclass
```

`uvm_field_int` enables `copy()`, `compare()`, `print()`, `pack()`/`unpack()` automatically.

---

## Driver Pattern

```systemverilog
class sig_driver extends uvm_driver #(sig_seq_item);
  virtual sig_if.DRIVER vif;

  `uvm_component_utils(sig_driver)
  `uvm_register_cb(sig_driver, sig_driver_cb)   // optional: callback hook

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual sig_if.DRIVER)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "virtual interface must be set");
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      fork begin
        fork
          begin @(posedge vif.reset) vif.driver_cb.sig <= 0; end
          begin
            seq_item_port.get_next_item(req);
            drive();
            seq_item_port.item_done();
          end
        join_any
        disable fork;
      end join
    end
  endtask

  virtual task drive();
    vif.driver_cb.sig <= 1;
    for (int i = 0; i < req.sig_length; i++) @(posedge vif.clk);
    vif.driver_cb.sig <= 0;
    @(posedge vif.clk);
    `uvm_do_callbacks(sig_driver, sig_driver_cb, post_drive(req))
  endtask
endclass
```

The `fork/join_any` + `disable fork` pattern handles reset interrupting an in-flight transaction cleanly.

---

## Monitor Pattern

```systemverilog
class sig_monitor extends uvm_monitor;
  virtual sig_if.MONITOR vif;
  uvm_analysis_port #(sig_seq_item) item_collected_port;

  `uvm_component_utils(sig_monitor)

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    item_collected_port = new("item_collected_port", this);
    if (!uvm_config_db#(virtual sig_if.MONITOR)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", "virtual interface must be set");
  endfunction

  virtual task run_phase(uvm_phase phase);
    sig_seq_item item;
    forever begin
      @(posedge vif.monitor_cb.sig);    // wait for pulse start
      item = sig_seq_item::type_id::create("item");
      item.sig_length = 0;
      while (vif.monitor_cb.sig) begin
        item.sig_length++;
        @(posedge vif.clk);
      end
      item_collected_port.write(item);
    end
  endtask
endclass
```

---

## Scoreboard (Analysis FIFO Pattern)

```systemverilog
class sig_scoreboard extends uvm_scoreboard;
  uvm_analysis_export #(sig_seq_item) item_collected_source;
  uvm_analysis_export #(sig_seq_item) item_collected_sink;
  uvm_tlm_analysis_fifo #(sig_seq_item) source_fifo;
  uvm_tlm_analysis_fifo #(sig_seq_item) sink_fifo;
  int items_checked = 0;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    source_fifo = new("source_fifo", this);
    sink_fifo   = new("sink_fifo",   this);
    item_collected_source = source_fifo.analysis_export;
    item_collected_sink   = sink_fifo.analysis_export;
  endfunction

  task run_phase(uvm_phase phase);
    sig_seq_item sent, rcvd;
    forever begin
      source_fifo.get(sent);
      sink_fifo.get(rcvd);
      if (sent.sig_length !== rcvd.sig_length)
        `uvm_error("SCB", $sformatf("Mismatch: sent=%0d rcvd=%0d", sent.sig_length, rcvd.sig_length))
      else
        `uvm_info("SCB", $sformatf("Sent length %0d are the same", sent.sig_length), UVM_LOW)
      items_checked++;
    end
  endtask
endclass
```

---

## UVM Factory Override

```systemverilog
// In test build_phase:
factory.set_type_override_by_type(
    sig_seq_item::get_type(),
    long_sig_item::get_type());

// long_sig_item.svh — constraint overrides base:
class long_sig_item extends sig_seq_item;
  `uvm_object_utils(long_sig_item)
  constraint c_long { sig_length >= 8; }  // more specific than c_nonzero
  function new(string name = "long_sig_item"); super.new(name); endfunction
endclass
```

The factory intercepts every `sig_seq_item::type_id::create(...)` call and returns a `long_sig_item` instead. Driver, monitor, and scoreboard are unchanged — factory transparency is the point.

---

## uvm_config_db — Correct Scope Pattern

```systemverilog
// Test sets config targeting child named "env":
uvm_config_db#(sig_cfg)::set(this, "env", "cfg", cfg_h);
uvm_config_db#(int)::set(this, "env", "num_tx", 5);

// env retrieves in its own build_phase:
uvm_config_db#(sig_cfg)::get(this, "", "cfg", cfg_h);
uvm_config_db#(int)::get(this, "", "num_tx", num_tx);
```

**Scope rule:** `set(parent, child_path, key, val)` creates scope string `parent.get_full_name().child_path`. `get(comp, "", key, val)` looks up scope `comp.get_full_name()`. These must match. Common mistake: using `set(this, "*", ...)` and `get(this, "", ...)` on the same component — the wildcard expands to children, not self.

**Custom config object:**

```systemverilog
class sig_cfg extends uvm_object;
  int    num_transactions = 10;
  string label            = "default";

  `uvm_object_utils_begin(sig_cfg)
    `uvm_field_int   (num_transactions, UVM_ALL_ON)
    `uvm_field_string(label,            UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "sig_cfg"); super.new(name); endfunction
endclass
```

---

## Directed / Constrained Sequences

```systemverilog
// Directed — bypass randomization entirely:
class directed_seq extends uvm_sequence #(sig_seq_item);
  task body();
    repeat (3) begin
      req = sig_seq_item::type_id::create("req");
      start_item(req);
      req.sig_length.rand_mode(0);   // disable randomization for this field
      req.sig_length = 7;
      finish_item(req);
    end
  endtask
endclass

// Inline constraint — randomize() with {}:
class constrained_seq extends uvm_sequence #(sig_seq_item);
  task body();
    repeat (3) begin
      req = sig_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { sig_length inside {[1:3]}; })
        `uvm_fatal("RAND", "randomize failed")
      finish_item(req);
    end
  endtask
endclass
```

`start_item()` arbitrates with the sequencer; `finish_item()` sends. Always call both together.

---

## Callbacks

```systemverilog
// 1. Define callback base class:
class sig_driver_cb extends uvm_callback;
  `uvm_object_utils(sig_driver_cb)
  function new(string name = "sig_driver_cb"); super.new(name); endfunction
  virtual task post_drive(sig_seq_item item); endtask
endclass

// 2. Register and call inside driver:
`uvm_register_cb(sig_driver, sig_driver_cb)
// Inside drive():
`uvm_do_callbacks(sig_driver, sig_driver_cb, post_drive(req))

// 3. Implement concrete callback in test:
class count_cb extends sig_driver_cb;
  int call_count = 0;
  virtual task post_drive(sig_seq_item item);
    call_count++;
  endtask
endclass

// 4. Register in test build_phase or run_phase:
count_cb cb = count_cb::type_id::create("cb");
uvm_callbacks #(sig_driver, sig_driver_cb)::add(drv_handle, cb);
```

Callbacks are ordered — multiple callbacks on the same hook execute in registration order.

---

## Virtual Sequencer and Virtual Sequence

```systemverilog
// Virtual sequencer — holds handles to real sequencers, no item type:
class sig_virt_sequencer extends uvm_sequencer;
  sig_sequencer seqr;
  `uvm_component_utils(sig_virt_sequencer)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
endclass

// Virtual sequence — runs sub-sequences on real sequencers:
class sig_virt_sequence extends uvm_sequence;
  `uvm_object_utils(sig_virt_sequence)
  `uvm_declare_p_sequencer(sig_virt_sequencer)   // casts m_sequencer → p_sequencer

  task body();
    short_burst_seq short_seq = short_burst_seq::type_id::create("short_seq");
    long_burst_seq  long_seq  = long_burst_seq::type_id::create("long_seq");
    fork
      short_seq.start(p_sequencer.seqr);
      long_seq.start(p_sequencer.seqr);
    join
  endtask
endclass

// In test run_phase:
sig_virt_sequence vseq = sig_virt_sequence::type_id::create("vseq");
vseq.start(vseqr_handle);
```

The virtual sequencer has no associated driver — it only coordinates. `uvm_declare_p_sequencer` generates the `p_sequencer` handle by casting `m_sequencer`.

---

## Driver-to-Sequence Response Channel

```systemverilog
// rsp_driver — overrides item_done to return a response:
class rsp_driver extends sig_driver;
  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive();
      rsp = sig_seq_item::type_id::create("rsp");
      rsp.set_id_info(req);           // copies transaction_id and sequence_id
      rsp.sig_length = req.sig_length;
      seq_item_port.item_done(rsp);   // item_done(rsp) vs item_done()
    end
  endtask
endclass

// In sequence body():
for (int i = 0; i < 10; i++) begin
  sig_seq_item rsp;
  start_item(req); finish_item(req);
  get_response(rsp);                  // blocks until driver calls item_done(rsp)
  if (rsp.sig_length !== req.sig_length)
    `uvm_error("RSP", "Response mismatch")
end
```

`set_id_info(req)` is critical — the response won't be routed back to the correct sequence without matching IDs.

---

## Verbosity Control

```systemverilog
// Lower verbosity globally (test level applies to all children):
uvm_top.set_report_verbosity_level_hier(UVM_LOW);

// Raise verbosity for a specific phase window:
uvm_top.set_report_verbosity_level_hier(UVM_HIGH);

// Override for a single component only:
scoreboard_handle.set_report_verbosity_level(UVM_HIGH);

// Print messages (only emitted when verbosity >= message level):
`uvm_info("TAG", "PHASE1_LOW_VISIBLE",  UVM_LOW)    // always visible
`uvm_info("TAG", "PHASE1_MED_SUPPRESSED", UVM_MEDIUM) // suppressed when level=LOW
```

`set_report_verbosity_level_hier` walks the component tree. `set_report_verbosity_level` sets only the called component.

UVM verbosity levels: `UVM_NONE=0`, `UVM_LOW=100`, `UVM_MEDIUM=200`, `UVM_HIGH=300`, `UVM_FULL=400`, `UVM_DEBUG=500`.

---

## Register Model (Software-Only RAL)

```systemverilog
// Register definition:
class sig_ctrl_reg extends uvm_reg;
  uvm_reg_field en;
  uvm_reg_field mode;

  `uvm_object_utils(sig_ctrl_reg)
  function new(string name = "sig_ctrl_reg");
    super.new(name, 8, UVM_NO_COVERAGE);   // 8-bit register
  endfunction

  function void build();
    en   = uvm_reg_field::type_id::create("en");
    mode = uvm_reg_field::type_id::create("mode");
    en  .configure(this, 1, 0, "RW", 0, 1'h0, 1, 1, 1);  // 1-bit at pos 0
    mode.configure(this, 3, 1, "RW", 0, 3'h0, 1, 1, 1);  // 3-bit at pos 1
  endfunction
endclass

// Register block:
class sig_reg_block extends uvm_reg_block;
  sig_ctrl_reg ctrl;
  uvm_reg_map  reg_map;

  `uvm_object_utils(sig_reg_block)
  function new(string name = "sig_reg_block"); super.new(name, UVM_NO_COVERAGE); endfunction

  function void build();
    ctrl = sig_ctrl_reg::type_id::create("ctrl");
    ctrl.build();
    ctrl.configure(this, null, "");
    reg_map = create_map("reg_map", 0, 1, UVM_LITTLE_ENDIAN);
    reg_map.add_reg(ctrl, 'h0, "RW");
    lock_model();
  endfunction
endclass

// SW-only operations in test (no bus adapter needed):
reg_blk.ctrl.predict(8'hAB);         // set predicted value
reg_blk.ctrl.get();                   // return predicted value (no bus access)
reg_blk.ctrl.en.set(1'b0);           // set field predicted value
reg_blk.ctrl.write();                 // would need adapter — don't use in SW-only
reg_blk.ctrl.randomize();             // randomize field values
reg_blk.reset();                      // reset all registers to reset values
```

`UVM_NO_COVERAGE` avoids the `covergroup` dependency. `lock_model()` must be called after all registers and maps are added.

---

## Analysis Port Fan-Out (Broadcast)

```systemverilog
// Analysis port connects to multiple exports — each write() call reaches all:
class broadcast_env extends sig_model_env;
  sig_coverage coverage;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    coverage = sig_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);    // connects monitor → scoreboard
    // Second connection — same port, additional subscriber:
    sig_agnt_d.monitor.item_collected_port.connect(coverage.analysis_export);
  endfunction
endclass

// Coverage subscriber (manual bins — no covergroup):
class sig_coverage extends uvm_subscriber #(sig_seq_item);
  int unsigned bin_short = 0, bin_medium = 0, bin_long = 0;

  `uvm_component_utils(sig_coverage)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void write(sig_seq_item t);
    if      (t.sig_length inside {[1:4]})   bin_short++;
    else if (t.sig_length inside {[5:10]})  bin_medium++;
    else if (t.sig_length inside {[11:15]}) bin_long++;
  endfunction

  function real get_coverage();
    int hit = (bin_short > 0) + (bin_medium > 0) + (bin_long > 0);
    return 100.0 * hit / 3;
  endfunction
endclass
```

`uvm_subscriber` provides `analysis_export` automatically. `write()` is the only pure virtual method to implement.

---

## UVM_PASSIVE Agent

```systemverilog
// Set BEFORE super.build_phase creates the agent:
class passive_env extends sig_model_env;
  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(
        this, "sig_agnt_m", "is_active", UVM_PASSIVE);
    super.build_phase(phase);   // agent reads is_active during its own build_phase
  endfunction
endclass

// sig_agent.build_phase:
class sig_agent extends uvm_agent;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = sig_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
      sequencer = sig_sequencer::type_id::create("sequencer", this);
      driver    = sig_driver::type_id::create("driver", this);
    end
  endfunction
endclass
```

**Ordering rule:** The parent's `build_phase` runs top-down. The config_db `set()` in the parent must happen before `super.build_phase()` (which triggers child `build_phase` calls). The agent reads `is_active` in its own `build_phase`, which runs inside `super.build_phase(phase)` of the parent.

---

## Self-Checking Test Runner Pattern

```bash
#!/usr/bin/env bash
check() {
  local name=$1; shift
  local out ok=1
  out=$("$BIN" "+UVM_TESTNAME=$name" 2>&1)

  # Always check zero errors/fatals:
  if ! printf '%s\n' "$out" | grep -qE "UVM_ERROR : +0$"; then
    printf '  [FAIL] UVM_ERROR not 0\n'; ok=0
  fi

  for pat in "$@"; do
    if [[ "$pat" == "!"* ]]; then
      # Absence check — pattern must NOT appear:
      local real="${pat#!}"
      if printf '%s\n' "$out" | grep -qE "$real"; then
        printf '  [FAIL] should be absent: %s\n' "$real"; ok=0
      fi
    else
      if ! printf '%s\n' "$out" | grep -qE "$pat"; then
        printf '  [FAIL] expected: %s\n' "$pat"; ok=0
      fi
    fi
  done

  [ "$ok" -eq 1 ] && { printf 'PASS  %s\n' "$name"; ((pass++)); } \
                  || { printf 'FAIL  %s\n' "$name"; ((fail++)); }
}

check test_verbosity \
  "PHASE1_LOW_VISIBLE"        \
  "!PHASE1_MED_SUPPRESSED"    \   # must NOT appear
  "PHASE2_MED_VISIBLE"
```

---

## What Does Not Work Under Verilator + UVM_NO_DPI

| Feature | Why it fails | Alternative |
|---------|-------------|-------------|
| `covergroup` / `coverpoint` | Requires `--coverage` flag | Manual bin counters in `uvm_subscriber` |
| `uvm_hdl_read/write` (backdoor) | DPI-C disabled | Software predict/get/set |
| `uvm_reg::write/read` (frontdoor) | Needs bus adapter + real bus | Software predict/get/set |
| `$urandom` seeding via DPI | DPI-C disabled | `$random` works; use `--seed` for Verilator |
| Some UVM internal assertions | DPI guards disabled | Use `UVM_NO_DPI`; most assertions are no-ops |

---

## Naming Conventions Used in This Repo

| Category | Convention | Example |
|----------|-----------|---------|
| Sequence items | `*_item.svh` | `sig_seq_item`, `long_sig_item` |
| Config objects | `*_cfg.svh` | `sig_cfg` |
| Drivers | `*_driver.svh` | `sig_driver`, `rsp_driver` |
| Monitors | `*_monitor.svh` | `sig_monitor` |
| Agents | `*_agent.svh` | `sig_agent` |
| Environments | `*_env.svh` | `sig_model_env`, `broadcast_env` |
| Tests | `test_*.svh` or `*_test.svh` | `test_factory_override`, `sig_model_test` |
| Callbacks | `*_cbs.svh` | `sig_driver_cbs` |
| Reg blocks | `*_reg_block.svh` | `sig_reg_block` |
| Coverage | `*_coverage.svh` | `sig_coverage` |
