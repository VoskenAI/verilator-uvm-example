# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Prerequisites

- **Verilator** on `PATH` (tested with 5.046, built from source)
- **UVM sources** with `UVM_HOME` pointing to the `src/` directory (default: `~/opt/accellera/1800.2-2017-1.0/src`)

## Commands

```sh
make                                     # compile + run default test (sig_model_test)
make compile                             # elaborate only → obj_dir/Vtbench_top
make run                                 # run simulation → dump.fst waveform
make TESTNAME=test_factory_override      # compile + run a specific test
make test                                # compile then run all 11 tests via run_tests.sh
make waves                               # open dump.fst in GTKWave
make clean                               # remove obj_dir/ and dump.fst
```

Run a single test without recompiling:

```sh
./obj_dir/Vtbench_top +UVM_TESTNAME=test_config_db
```

## Repository Layout

```
Makefile / sim_main.cpp / run_tests.sh  — build and test infrastructure
tb/tb.sv                                — top-level Verilator module
dv/sig_pkg.sv                           — package that includes all .svh files
dv/if/sig_if.sv                         — interface with DRIVER/MONITOR modports
dv/env/*.svh                            — reusable UVM components
dv/tests/*.svh                          — one UVM test class per file
docs/verilator_uvm.md                   — UVM+Verilator patterns reference
```

## Architecture

### Compilation flow

Verilator compiles three top-level sources in order:
1. `$UVM_HOME/uvm_pkg.sv` — Accellera UVM library
2. `dv/sig_pkg.sv` — project package (`` `include ``s all `.svh` files)
3. `tb/tb.sv` — top-level module

`sim_main.cpp` drives the eval loop and records an FST waveform.

### UVM component hierarchy

```
uvm_test_top  (any test class)
└── sig_model_env  (or broadcast_env / passive_env)
    ├── sig_agnt_d   (UVM_ACTIVE — drives the DUT)
    │   ├── sig_sequencer
    │   ├── sig_driver   (or rsp_driver for test_response)
    │   └── sig_monitor  → ap → scoreboard.item_collected_source
    ├── sig_agnt_m   (UVM_ACTIVE or UVM_PASSIVE)
    │   └── sig_monitor  → ap → scoreboard.item_collected_sink
    └── sig_scoreboard   (+ sig_coverage in broadcast_env)
```

### Signal flow

`sig_driver` asserts `sig` high for `sig_length` clock cycles then deasserts. Both monitors measure pulse width and write a `sig_seq_item` into the scoreboard. `check_phase` compares every sent/received length pair.

`sig_if` has separate `DRIVER` and `MONITOR` clocking blocks (both `posedge clk`, `#1` skew). `tb.sv` pushes both modport handles into `uvm_config_db` with wildcard scope `"*"`.

## Key Verilator Constraints

- **`+define+UVM_NO_DPI`** — disables DPI-C. Pure-SV UVM works (factory, config_db, callbacks, register SW model). DPI-dependent features do not.
- **`--timing`** — required for `fork/join`, `@(posedge clk)`, and UVM time-based scheduler.
- **`covergroup`** — requires `--coverage` flag (not enabled). Use manual bin counters in a `uvm_subscriber` instead.
- **Incremental builds** — after editing `.svh` files, Verilator may not detect the change. Run `make clean && make compile` to be safe.

## config_db Scope Pattern

```systemverilog
// In test build_phase — targets child named "env":
uvm_config_db#(T)::set(this, "env", "key", val);
// Matches get() called inside env:
uvm_config_db#(T)::get(this, "", "key", val);
```

Full scope = `parent.get_full_name() + "." + child_path`. Use `"*"` on the set side to match any descendant.

## Include Order in sig_pkg.sv

Files must be included in dependency order (base classes before derived):

```
sig_item → long_sig_item → sig_cfg → sig_driver_cbs → sig_sequencer →
sig_virt_sequencer → sig_sequence → sig_virt_sequence → sig_driver →
rsp_driver → sig_monitor → sig_agent → sig_scoreboard → sig_coverage →
sig_reg_block → sig_model_env → broadcast_env → passive_env →
[all test files]
```

## Test List

| Test | Key UVM Feature |
|------|----------------|
| `sig_model_test` | Baseline sequences, analysis ports, scoreboard |
| `test_factory_override` | `set_type_override_by_type`, factory transparency |
| `test_config_db` | `uvm_config_db` object + scalar, parent→child pattern |
| `test_directed` | `rand_mode(0)`, `randomize() with {}` inline constraints |
| `test_callback` | `uvm_callback`, `uvm_register_cb`, `uvm_do_callbacks` |
| `test_virtual_seq` | Virtual sequencer, `uvm_declare_p_sequencer`, fork/join |
| `test_verbosity` | `set_report_verbosity_level_hier`, per-component override |
| `test_response` | `item_done(rsp)`, `get_response(rsp)` response channel |
| `test_reg_model` | `uvm_reg_block` SW model: predict/get/set/randomize/reset |
| `test_broadcast_coverage` | Analysis port fan-out, `uvm_subscriber`, manual bins |
| `test_passive_agent` | `UVM_PASSIVE` via config_db, monitor-only agent |
