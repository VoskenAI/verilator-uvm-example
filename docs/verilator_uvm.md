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

### Recommended directory layout

```
tb/tb_top.sv              — top-level module (clock, reset, interface instantiation)
dv/tb_pkg.sv              — package that `includes all .svh files
dv/if/dut_if.sv           — interface with clocking block modports
dv/env/                   — reusable UVM components (.svh files)
dv/tests/                 — one test class per .svh file
```

### C++ simulation harness

A minimal `sim_main.cpp` is required to open the FST trace file. Key points:

- `contextp->commandArgs(argc, argv)` — forwards `+UVM_TESTNAME=` and other plusargs to the SV side
- `topp->trace(tfp, 99)` + `tfp->open("dump.fst")` — enables and opens FST waveform capture
- `nextTimeSlot()` — advances simulated time; required when `--timing` is set

See `sim_main.cpp` in this repo for a complete working example (~25 lines).

---

## Package Structure

All UVM code lives in a single package file that `` `include ``s `.svh` files in dependency order. No file-level compilation units — everything is one package imported by the top module.

```systemverilog
package tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"     // include if not already pulled in by uvm_pkg

  // Items and config objects (no component dependencies)
  `include "my_item.svh"
  `include "my_item_extended.svh"   // derived items after base
  `include "my_cfg.svh"

  // Callback base class — must precede the driver that registers it
  `include "my_driver_cbs.svh"

  // Sequencer before any sequence (sequences reference the sequencer type)
  `include "my_sequencer.svh"
  `include "my_virt_sequencer.svh"
  `include "my_sequence.svh"
  `include "my_virt_sequence.svh"

  // Components
  `include "my_driver.svh"
  `include "my_monitor.svh"
  `include "my_agent.svh"
  `include "my_scoreboard.svh"
  `include "my_coverage.svh"
  `include "my_reg_block.svh"

  // Environments — base class before any derived environment
  `include "my_env.svh"
  `include "my_env_extended.svh"

  // Tests last — they depend on everything above
  `include "my_base_test.svh"
  `include "test_smoke.svh"
  `include "test_directed.svh"
  // ... more tests
endpackage : tb_pkg
```

---

## Top-Level Module

```systemverilog
module tb_top;
  import uvm_pkg::*;
  import tb_pkg::*;

  bit clk;
  bit reset_n;

  always #5 clk = ~clk;        // 10-unit clock period

  initial begin
    reset_n = 0;
    #20 reset_n = 1;
  end

  dut_if intf (.clk(clk), .reset_n(reset_n));

  dut u_dut (
    .clk     (clk),
    .reset_n (reset_n),
    .data_in (intf.data_in),
    .data_out(intf.data_out)
  );

  initial begin
    // Push virtual interface handles into config_db with wildcard scope
    // so any component anywhere in the hierarchy can retrieve them by type
    uvm_config_db#(virtual dut_if.DRIVER)::set(uvm_root::get(), "*", "vif", intf.DRIVER);
    uvm_config_db#(virtual dut_if.MONITOR)::set(uvm_root::get(), "*", "vif", intf.MONITOR);
  end

  initial begin
    run_test();   // test name comes from +UVM_TESTNAME on the command line
  end
endmodule
```

Two separate `set()` calls for the same key `"vif"` with different parameterized types (`DRIVER` vs `MONITOR`) is correct — `uvm_config_db` is keyed on `{scope, key, type}` so they don't collide.

---

## Interface with Clocking Blocks

```systemverilog
interface dut_if (input logic clk, reset_n);
  logic       valid;
  logic [7:0] data;
  logic       ready;

  clocking driver_cb @(posedge clk);
    default input #1 output #1;
    output valid, data;
    input  ready;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1 output #1;
    input valid, data, ready;
  endclocking

  modport DRIVER  (clocking driver_cb,  input clk, reset_n);
  modport MONITOR (clocking monitor_cb, input clk, reset_n);
endinterface
```

Separate clocking blocks for DRIVER and MONITOR:
- Prevent the driver from accidentally sampling signals it should only drive (and vice versa).
- The `#1` input skew samples signals one time unit after the clock edge, avoiding races with RTL `always` blocks that update on the same edge.
- Typed modports (`virtual dut_if.DRIVER` vs `virtual dut_if.MONITOR`) make the intent explicit and caught at compile time.

---

## Sequence Item

```systemverilog
class my_item extends uvm_sequence_item;
  rand bit [7:0] data;
  rand bit [3:0] burst_len;
  constraint c_valid_burst { burst_len inside {[1:15]}; }

  `uvm_object_utils_begin(my_item)
    `uvm_field_int(data,      UVM_ALL_ON)
    `uvm_field_int(burst_len, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "my_item");
    super.new(name);
  endfunction
endclass
```

`uvm_object_utils` + `uvm_field_*` macros enable `copy()`, `compare()`, `print()`, `pack()`/`unpack()` without writing them manually. Register every field you want visible in those operations.

---

## Driver Pattern

```systemverilog
class my_driver extends uvm_driver #(my_item);
  virtual dut_if.DRIVER vif;

  `uvm_component_utils(my_driver)
  `uvm_register_cb(my_driver, my_driver_cb)   // omit if callbacks not needed

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual dut_if.DRIVER)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", {"virtual interface must be set for: ", get_full_name()});
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.driver_cb.valid <= 0;
    @(posedge vif.reset_n);   // wait for reset to deassert
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive(my_item item);
    vif.driver_cb.valid <= 1;
    vif.driver_cb.data  <= item.data;
    @(posedge vif.clk);
    vif.driver_cb.valid <= 0;
    `uvm_do_callbacks(my_driver, my_driver_cb, post_drive(item))
  endtask
endclass
```

**Reset handling with `fork/join_any`** — use this pattern when a reset can interrupt an in-flight transaction:

```systemverilog
virtual task run_phase(uvm_phase phase);
  forever begin
    fork begin
      fork
        begin @(negedge vif.reset_n) vif.driver_cb.valid <= 0; end
        begin seq_item_port.get_next_item(req); drive(req); seq_item_port.item_done(); end
      join_any
      disable fork;
    end join
  end
endtask
```

---

## Monitor Pattern

```systemverilog
class my_monitor extends uvm_monitor;
  virtual dut_if.MONITOR vif;
  uvm_analysis_port #(my_item) ap;

  `uvm_component_utils(my_monitor)

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual dut_if.MONITOR)::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", {"virtual interface must be set for: ", get_full_name()});
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_item item;
    forever begin
      @(posedge vif.clk);
      if (vif.monitor_cb.valid) begin
        item = my_item::type_id::create("item");
        item.data = vif.monitor_cb.data;
        ap.write(item);   // broadcast to all connected subscribers
      end
    end
  endtask
endclass
```

---

## Agent Pattern

```systemverilog
class my_agent extends uvm_agent;
  my_sequencer sequencer;
  my_driver    driver;
  my_monitor   monitor;

  `uvm_component_utils(my_agent)

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = my_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
      sequencer = my_sequencer::type_id::create("sequencer", this);
      driver    = my_driver::type_id::create("driver",    this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
```

`is_active` defaults to `UVM_ACTIVE`. Override via config_db to make the agent passive (monitor only).

---

## Scoreboard (Analysis FIFO Pattern)

```systemverilog
class my_scoreboard extends uvm_scoreboard;
  uvm_analysis_export #(my_item) expected_export;
  uvm_analysis_export #(my_item) actual_export;
  uvm_tlm_analysis_fifo #(my_item) expected_fifo;
  uvm_tlm_analysis_fifo #(my_item) actual_fifo;
  int items_checked = 0;

  `uvm_component_utils(my_scoreboard)

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    expected_fifo = new("expected_fifo", this);
    actual_fifo   = new("actual_fifo",   this);
    expected_export = expected_fifo.analysis_export;
    actual_export   = actual_fifo.analysis_export;
  endfunction

  task run_phase(uvm_phase phase);
    my_item exp_item, act_item;
    forever begin
      expected_fifo.get(exp_item);
      actual_fifo.get(act_item);
      if (!exp_item.compare(act_item))
        `uvm_error("SCB", $sformatf("Mismatch!\nExpected: %s\nActual:   %s",
                                     exp_item.sprint(), act_item.sprint()))
      items_checked++;
    end
  endtask

  function void check_phase(uvm_phase phase);
    if (expected_fifo.size() != 0 || actual_fifo.size() != 0)
      `uvm_error("SCB", "Unmatched items remain in FIFOs at end of test")
  endfunction
endclass
```

`uvm_tlm_analysis_fifo` decouples producers from the scoreboard — monitors write at any rate; the scoreboard drains the FIFO during `run_phase`.

---

## Environment Pattern

```systemverilog
class my_env extends uvm_env;
  my_agent      agent;
  my_scoreboard scoreboard;

  `uvm_component_utils(my_env)

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = my_agent::type_id::create("agent",      this);
    scoreboard = my_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.monitor.ap.connect(scoreboard.actual_export);
  endfunction
endclass
```

---

## UVM Factory Override

```systemverilog
// Derived item with a tighter constraint:
class my_long_item extends my_item;
  `uvm_object_utils(my_long_item)
  constraint c_long { burst_len >= 8; }   // more specific than base constraint
  function new(string name = "my_long_item"); super.new(name); endfunction
endclass

// In test build_phase — redirect every my_item::type_id::create() to my_long_item:
factory.set_type_override_by_type(
    my_item::get_type(),
    my_long_item::get_type());

// Instance override — only for a specific path:
factory.set_inst_override_by_type(
    my_item::get_type(),
    my_long_item::get_type(),
    {get_full_name(), ".env.agent.sequencer.*"});
```

The factory intercepts every `my_item::type_id::create(...)` call in the hierarchy and substitutes the override type. Driver, monitor, scoreboard, and sequences are completely unaware of the substitution — factory transparency is the core value.

---

## uvm_config_db — Correct Scope Pattern

```systemverilog
// ─── In test build_phase — set config targeting a named child: ───────────────
uvm_config_db#(my_cfg)::set(this, "env",          "cfg",    cfg_h);
uvm_config_db#(int)::set   (this, "env",          "num_tx", 20);
// Using wildcard to reach all descendants:
uvm_config_db#(int)::set   (this, "env.*",        "num_tx", 20);

// ─── In env build_phase — retrieve using self as context: ────────────────────
if (!uvm_config_db#(my_cfg)::get(this, "", "cfg",    cfg_h))
  `uvm_fatal("CFG", "cfg not set")
if (!uvm_config_db#(int)::get   (this, "", "num_tx", num_tx))
  `uvm_fatal("CFG", "num_tx not set")
```

**Scope rule:** `set(parent, child_path, key, val)` stores under scope `parent.get_full_name() + "." + child_path`. `get(comp, "", key, val)` looks up scope `comp.get_full_name()`. The two must match.

**Common mistake:** `set(this, "*", "key", val)` followed by `get(this, "", "key", val)` on the **same** component — `"*"` expands to children, not the component itself, so the get fails.

**Custom config object:**

```systemverilog
class my_cfg extends uvm_object;
  int    num_transactions = 10;
  string test_label       = "default";
  bit    en_coverage      = 1;

  `uvm_object_utils_begin(my_cfg)
    `uvm_field_int   (num_transactions, UVM_ALL_ON)
    `uvm_field_string(test_label,       UVM_ALL_ON)
    `uvm_field_int   (en_coverage,      UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "my_cfg"); super.new(name); endfunction
endclass
```

---

## Directed and Constrained Sequences

```systemverilog
// ─── Directed: bypass randomization with rand_mode(0) ────────────────────────
class directed_seq extends uvm_sequence #(my_item);
  `uvm_object_utils(directed_seq)
  task body();
    repeat (5) begin
      req = my_item::type_id::create("req");
      start_item(req);
      req.burst_len.rand_mode(0);   // disable randomization for this field
      req.burst_len = 4;
      req.data      = 8'hAB;
      finish_item(req);
    end
  endtask
endclass

// ─── Inline constraint: randomize() with {} ──────────────────────────────────
class constrained_seq extends uvm_sequence #(my_item);
  `uvm_object_utils(constrained_seq)
  task body();
    repeat (5) begin
      req = my_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { burst_len inside {[1:3]}; data < 8'h80; })
        `uvm_fatal("RAND", "randomize() failed")
      finish_item(req);
    end
  endtask
endclass
```

`start_item()` arbitrates for the sequencer; `finish_item()` randomizes (if not already done) and sends. Always call both in sequence. Never call `randomize()` before `start_item()` — the sequencer may override randomization.

---

## Callbacks

```systemverilog
// 1. Define the callback base class with virtual hook methods:
class my_driver_cb extends uvm_callback;
  `uvm_object_utils(my_driver_cb)
  function new(string name = "my_driver_cb"); super.new(name); endfunction
  virtual task pre_drive(my_item item);  endtask   // hook before driving
  virtual task post_drive(my_item item); endtask   // hook after driving
endclass

// 2. In the driver class — register the callback type and invoke hooks:
class my_driver extends uvm_driver #(my_item);
  `uvm_register_cb(my_driver, my_driver_cb)
  // Inside drive():
  `uvm_do_callbacks(my_driver, my_driver_cb, pre_drive(req))
  // ... drive logic ...
  `uvm_do_callbacks(my_driver, my_driver_cb, post_drive(req))
endclass

// 3. Implement a concrete callback in the test:
class error_inject_cb extends my_driver_cb;
  `uvm_object_utils(error_inject_cb)
  virtual task post_drive(my_item item);
    // corrupt data on the bus after the item is driven
    @(posedge vif.clk) vif.driver_cb.data <= 8'hFF;
  endtask
endclass

// 4. Register the callback instance from the test:
error_inject_cb cb;
cb = error_inject_cb::type_id::create("error_cb");
uvm_callbacks #(my_driver, my_driver_cb)::add(env.agent.driver, cb);
```

Multiple callbacks on the same hook execute in the order they were registered. Use `uvm_callbacks::delete()` to remove a callback mid-test.

---

## Virtual Sequencer and Virtual Sequence

```systemverilog
// Virtual sequencer — coordinator, no item type, holds real sequencer handles:
class my_virt_sequencer extends uvm_sequencer;
  my_sequencer tx_seqr;   // handle wired in env connect_phase
  my_sequencer rx_seqr;
  `uvm_component_utils(my_virt_sequencer)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
endclass

// Virtual sequence — orchestrates sub-sequences on real sequencers:
class my_virt_sequence extends uvm_sequence;
  `uvm_object_utils(my_virt_sequence)
  `uvm_declare_p_sequencer(my_virt_sequencer)   // casts m_sequencer → p_sequencer

  task body();
    tx_burst_seq tx_seq = tx_burst_seq::type_id::create("tx_seq");
    rx_check_seq rx_seq = rx_check_seq::type_id::create("rx_seq");
    fork
      tx_seq.start(p_sequencer.tx_seqr);
      rx_seq.start(p_sequencer.rx_seqr);
    join   // fork/join waits for BOTH to finish
  endtask
endclass

// In test run_phase:
my_virt_sequence vseq = my_virt_sequence::type_id::create("vseq");
vseq.start(env.vseqr);
```

Wire the real sequencer handles in the env's `connect_phase`:

```systemverilog
function void connect_phase(uvm_phase phase);
  vseqr.tx_seqr = tx_agent.sequencer;
  vseqr.rx_seqr = rx_agent.sequencer;
endfunction
```

The virtual sequencer has no associated driver — it is a pure coordinator. `uvm_declare_p_sequencer` generates the typed `p_sequencer` handle by casting `m_sequencer` at the start of `body()`.

---

## Driver-to-Sequence Response Channel

```systemverilog
// Driver side — call item_done(rsp) instead of item_done():
class my_driver extends uvm_driver #(my_item);
  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      // Build a response item and echo it back:
      rsp = my_item::type_id::create("rsp");
      rsp.set_id_info(req);       // CRITICAL: copies transaction_id and sequence_id
      rsp.data = actual_output;   // fill in observed DUT output
      seq_item_port.item_done(rsp);
    end
  endtask
endclass

// Sequence side — call get_response() after finish_item():
class my_response_seq extends uvm_sequence #(my_item);
  task body();
    my_item rsp;
    for (int i = 0; i < 10; i++) begin
      start_item(req);
      req.randomize();
      finish_item(req);
      get_response(rsp);          // blocks until driver calls item_done(rsp)
      if (rsp.data !== expected_data(req))
        `uvm_error("SEQ", $sformatf("Response mismatch on item %0d", i))
    end
  endtask
endclass
```

`set_id_info(req)` is not optional — the TLM layer uses `transaction_id` and `sequence_id` to route the response back to the originating sequence. Without it the response is silently discarded or delivered to the wrong sequence.

---

## Verbosity Control

```systemverilog
// Set global verbosity for all components in the hierarchy:
uvm_top.set_report_verbosity_level_hier(UVM_LOW);    // suppress MEDIUM and above
uvm_top.set_report_verbosity_level_hier(UVM_HIGH);   // show up to HIGH

// Override verbosity for one component only (does not affect children):
scoreboard_handle.set_report_verbosity_level(UVM_HIGH);

// Messages — only printed when component's verbosity level >= message's level:
`uvm_info("TAG", "always visible",      UVM_LOW)
`uvm_info("TAG", "needs MEDIUM level",  UVM_MEDIUM)
`uvm_info("TAG", "needs HIGH level",    UVM_HIGH)
```

`set_report_verbosity_level_hier` walks the entire component subtree.
`set_report_verbosity_level` affects only the single component it is called on.

UVM verbosity constants: `UVM_NONE=0`, `UVM_LOW=100`, `UVM_MEDIUM=200`, `UVM_HIGH=300`, `UVM_FULL=400`, `UVM_DEBUG=500`.

---

## Register Model (Software-Only RAL)

When no bus adapter is available (no real bus interface on the DUT), use `predict()`/`get()`/`set()` to exercise the register model as a pure software object.

```systemverilog
// Register class:
class ctrl_reg extends uvm_reg;
  uvm_reg_field en;
  uvm_reg_field mode;

  `uvm_object_utils(ctrl_reg)
  function new(string name = "ctrl_reg");
    super.new(name, 8, UVM_NO_COVERAGE);   // 8-bit register, no functional coverage
  endfunction

  function void build();
    en   = uvm_reg_field::type_id::create("en");
    mode = uvm_reg_field::type_id::create("mode");
    // configure(parent, size_bits, lsb_pos, access, volatile, reset_val,
    //           has_reset, is_rand, individually_accessible)
    en  .configure(this, 1, 0, "RW", 0, 1'h0, 1, 1, 1);
    mode.configure(this, 3, 1, "RW", 0, 3'h0, 1, 1, 1);
  endfunction
endclass

// Register block:
class my_reg_block extends uvm_reg_block;
  ctrl_reg    ctrl;
  uvm_reg_map reg_map;

  `uvm_object_utils(my_reg_block)
  function new(string name = "my_reg_block"); super.new(name, UVM_NO_COVERAGE); endfunction

  function void build();
    ctrl = ctrl_reg::type_id::create("ctrl");
    ctrl.build();
    ctrl.configure(this, null, "");
    reg_map = create_map("reg_map", 'h0, 1, UVM_LITTLE_ENDIAN);
    reg_map.add_reg(ctrl, 'h0, "RW");
    lock_model();   // must be called after all registers are added
  endfunction
endclass

// SW-only operations (no bus, no adapter needed):
my_reg_block blk = my_reg_block::type_id::create("blk");
blk.build();

blk.ctrl.predict(8'hAB);         // set the predicted (mirrored) value
$display(blk.ctrl.get());        // read predicted value — no bus transaction
blk.ctrl.en.set(1'b0);           // set a single field's predicted value
void'(blk.ctrl.randomize());     // randomize all fields within constraints
blk.reset();                     // reset all registers to their reset values
```

`UVM_NO_COVERAGE` skips `covergroup` elaboration — required when not passing `--coverage` to Verilator. `lock_model()` marks the map as complete and enables address checking.

---

## Analysis Port Fan-Out (Broadcast to Multiple Subscribers)

A single `uvm_analysis_port` can connect to any number of exports. Each `write()` call is forwarded to every connected subscriber.

```systemverilog
// In connect_phase — connect the same port to two subscribers:
function void connect_phase(uvm_phase phase);
  agent.monitor.ap.connect(scoreboard.actual_export);
  agent.monitor.ap.connect(coverage.analysis_export);   // second connection — same port
endfunction

// Coverage subscriber using manual bins (no covergroup needed):
class my_coverage extends uvm_subscriber #(my_item);
  int unsigned bin_small  = 0;
  int unsigned bin_medium = 0;
  int unsigned bin_large  = 0;

  `uvm_component_utils(my_coverage)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  // write() is the only pure virtual method in uvm_subscriber:
  function void write(my_item t);
    if      (t.burst_len inside {[1:4]})   bin_small++;
    else if (t.burst_len inside {[5:10]})  bin_medium++;
    else if (t.burst_len inside {[11:15]}) bin_large++;
  endfunction

  function real get_coverage();
    int unsigned hit = (bin_small > 0) + (bin_medium > 0) + (bin_large > 0);
    return 100.0 * real'(hit) / 3.0;
  endfunction
endclass
```

---

## UVM_PASSIVE Agent

```systemverilog
// Set is_active BEFORE super.build_phase so the agent sees it in its own build_phase:
class my_env extends uvm_env;
  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(
        this, "rx_agent", "is_active", UVM_PASSIVE);
    super.build_phase(phase);   // triggers child build_phases; agent reads is_active here
  endfunction
endclass

// Agent conditionally creates driver and sequencer:
class my_agent extends uvm_agent;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = my_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
      sequencer = my_sequencer::type_id::create("sequencer", this);
      driver    = my_driver::type_id::create("driver",    this);
    end
  endfunction
endclass
```

**Ordering rule:** UVM `build_phase` is top-down. The parent calls `super.build_phase(phase)` which triggers all child `build_phase` calls. The config_db `set()` must happen **before** `super.build_phase()`, not after, or the child's `build_phase` will already have run with the default `UVM_ACTIVE`.

---

## Self-Checking Test Runner (Shell Script)

```bash
#!/usr/bin/env bash
set -euo pipefail

BIN=./obj_dir/Vtb_top
pass=0; fail=0

check() {
  local name=$1; shift
  local out ok=1
  out=$("$BIN" "+UVM_TESTNAME=$name" 2>&1)

  # Always require zero UVM errors and fatals:
  if ! printf '%s\n' "$out" | grep -qE "UVM_ERROR : +0$"; then
    printf '  [FAIL] UVM_ERROR not 0\n'; ok=0
  fi
  if ! printf '%s\n' "$out" | grep -qE "UVM_FATAL : +0$"; then
    printf '  [FAIL] UVM_FATAL not 0\n'; ok=0
  fi

  # Check each expected / forbidden pattern:
  for pat in "$@"; do
    if [[ "$pat" == "!"* ]]; then
      local real="${pat#!}"             # strip leading "!"
      if printf '%s\n' "$out" | grep -qE "$real"; then
        printf '  [FAIL] should be absent: %s\n' "$real"; ok=0
      fi
    else
      if ! printf '%s\n' "$out" | grep -qE "$pat"; then
        printf '  [FAIL] expected:          %s\n' "$pat"; ok=0
      fi
    fi
  done

  if [ "$ok" -eq 1 ]; then
    printf 'PASS  %s\n' "$name"; pass=$((pass + 1))
  else
    printf 'FAIL  %s\n' "$name"; fail=$((fail + 1))
  fi
}

# Usage examples:
check test_smoke \
  "items_checked=10"          \    # pattern MUST appear
  "!UVM_ERROR"                     # pattern must NOT appear

check test_verbosity \
  "PHASE_LOW_VISIBLE"         \
  "!PHASE_MED_SUPPRESSED"     \    # absence check
  "Verbosity test PASS"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

---

## What Does Not Work Under Verilator + UVM_NO_DPI

| Feature | Why it fails | Workaround |
|---------|-------------|------------|
| `covergroup` / `coverpoint` | Requires `--coverage` Verilator flag (not set) | Manual bin counters in `uvm_subscriber` |
| `uvm_hdl_read` / `uvm_hdl_write` (backdoor) | DPI-C disabled by `UVM_NO_DPI` | Software `predict()` / `get()` / `set()` |
| `uvm_reg::write` / `uvm_reg::read` (frontdoor) | Requires a real bus interface and `uvm_reg_adapter` | Software-only RAL operations |
| `$urandom` with DPI seeding | DPI-C disabled | `$random` or `--seed N` Verilator flag |
| `uvm_pkg` DPI assertions | DPI guards disabled | Define `UVM_NO_DPI`; most become no-ops |
| TLM 2.0 (`uvm_tlm_generic_payload`) | Not shipped with UVM 1800.2 base pkg | Use TLM 1.0 FIFOs and analysis ports |

---

## Recommended File Naming Conventions

| Category | Pattern | Purpose |
|----------|---------|---------|
| Sequence item | `<name>_item.svh` | Transaction data object |
| Config object | `<name>_cfg.svh` | Test configuration `uvm_object` |
| Driver | `<name>_driver.svh` | Drives DUT via virtual interface |
| Monitor | `<name>_monitor.svh` | Observes DUT, writes to analysis port |
| Agent | `<name>_agent.svh` | Bundles sequencer + driver + monitor |
| Scoreboard | `<name>_scoreboard.svh` | Compares expected vs actual items |
| Coverage | `<name>_coverage.svh` | `uvm_subscriber` with bin counting |
| Callback base | `<name>_cbs.svh` | `uvm_callback` hook definitions |
| Virtual sequencer | `<name>_virt_sequencer.svh` | Coordinator sequencer |
| Virtual sequence | `<name>_virt_sequence.svh` | Multi-agent orchestration |
| Register block | `<name>_reg_block.svh` | `uvm_reg_block` definition |
| Environment | `<name>_env.svh` | Top-level UVM environment |
| Test | `test_<scenario>.svh` | One test class per scenario |
| Package | `<project>_pkg.sv` | Wraps all `svh` includes |
