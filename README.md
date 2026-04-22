# UVM with Verilator — Feature Test Suite

> Built and maintained by **[Vosken.AI](https://vosken.ai)** — Design Hardware at the Speed of Thought

A practical, runnable UVM testbench that compiles and simulates entirely under open-source [Verilator](https://github.com/verilator/verilator). The repository demonstrates eleven commonly-used UVM patterns, each in its own self-checking test, with a shell-based test runner that verifies expected output automatically.

Use this as a reference, a starting point for your own UVM+Verilator TB, or a knowledge base for AI-assisted verification development.

Based on the original minimal example by [Antmicro](https://antmicro.com) (Copyright © 2025).

---

## What This Repository Covers

Each test targets a distinct UVM pattern that comes up in real verification work:

| Test | UVM Feature |
|------|-------------|
| `sig_model_test` | Component hierarchy, sequences, analysis ports, scoreboard `check_phase` |
| `test_factory_override` | `set_type_override_by_type`, derived items, factory transparency |
| `test_config_db` | `uvm_config_db` with a custom `uvm_object` and scalar; parent→child scope pattern |
| `test_directed` | `rand_mode(0)`, `randomize() with {}` inline constraints, multi-phase test structure |
| `test_callback` | `uvm_callback`, `uvm_register_cb`, `uvm_do_callbacks`, call-count verification |
| `test_virtual_seq` | Virtual sequencer, `uvm_declare_p_sequencer`, fork/join parallel sub-sequences |
| `test_verbosity` | `set_report_verbosity_level_hier`, per-component override, phase-gated messages |
| `test_response` | `item_done(rsp)`, `get_response(rsp)`, driver-to-sequence response channel |
| `test_reg_model` | `uvm_reg_block` SW model: `predict()`, `get()`, `set()`, `randomize()`, `reset()` |
| `test_broadcast_coverage` | Analysis port fan-out to multiple subscribers, `uvm_subscriber`, manual bin coverage |
| `test_passive_agent` | `UVM_PASSIVE` via config_db, monitor-only agent, no driver/sequencer created |

### What Is Not Covered

These UVM features require capabilities not available under this setup:

| Feature | Reason |
|---------|--------|
| `covergroup` / `coverpoint` | Requires Verilator `--coverage` flag (adds significant build overhead; not enabled) |
| RAL frontdoor (`uvm_reg_adapter`) | Requires a real bus interface; this DUT has none |
| RAL backdoor (`uvm_hdl_*`) | Requires DPI-C, disabled with `+define+UVM_NO_DPI` |
| TLM 2.0 | Not included in the UVM 1800.2 base package used here |
| Custom UVM phases | Not needed; standard phases cover all demonstrated patterns |
| `uvm_event` / `uvm_barrier` | Not demonstrated; useful for multi-agent synchronization |

---

## Repository Structure

```
Makefile           — Verilator build rules; compile/run/test/waves/clean targets
sim_main.cpp       — C++ simulation harness: eval loop, FST waveform, plusarg forwarding
run_tests.sh       — Self-checking test runner (PASS/FAIL per test, supports !pattern)

tb/
  tb.sv            — Top-level module: clock gen, reset, VIF registration via config_db

dv/
  sig_pkg.sv       — Single package that `includes all .svh files in dependency order
  if/
    sig_if.sv      — DUT interface: DRIVER and MONITOR clocking block modports
  env/             — Reusable UVM components
    sig_item.svh         — Base sequence item (rand sig_length, 4-bit)
    long_sig_item.svh    — Factory override target (constraint: sig_length >= 8)
    sig_cfg.svh          — Config object (uvm_object subclass with field macros)
    sig_driver_cbs.svh   — Callback base class (sig_driver_cb) + count_cb impl
    sig_sequencer.svh    — Standard uvm_sequencer parameterized on sig_seq_item
    sig_virt_sequencer.svh — Virtual sequencer (holds handle to real sequencer)
    sig_sequence.svh     — Default random sequence (10 transactions)
    sig_virt_sequence.svh  — Virtual sequence (fork/join two sub-sequences)
    sig_driver.svh       — Drives sig high for sig_length clocks; callback hook
    rsp_driver.svh       — Extends sig_driver; returns response via item_done(rsp)
    sig_monitor.svh      — Counts pulse width; writes sig_seq_item to analysis port
    sig_agent.svh        — Bundles sequencer + driver + monitor; respects is_active
    sig_scoreboard.svh   — Matches sent/received items via TLM FIFOs
    sig_coverage.svh     — uvm_subscriber with manual bin coverage (no covergroup)
    sig_reg_block.svh    — uvm_reg_block: ctrl_reg (en, mode) + status_reg
    sig_model_env.svh    — Base environment: two agents + scoreboard
    broadcast_env.svh    — Extends sig_model_env; adds coverage subscriber
    passive_env.svh      — Extends sig_model_env; sets sig_agnt_m to UVM_PASSIVE
  tests/           — One test class per .svh file (included last in sig_pkg.sv)

docs/
  verilator_uvm.md — Generic UVM+Verilator patterns reference (portable to any project)
```

### UVM Component Hierarchy

```
uvm_test_top  (any test class)
└── sig_model_env  (or broadcast_env / passive_env)
    ├── sig_agnt_d   (UVM_ACTIVE — drives the DUT)
    │   ├── sig_sequencer
    │   ├── sig_driver   (or rsp_driver for test_response)
    │   └── sig_monitor  ──ap──► scoreboard.item_collected_source
    ├── sig_agnt_m   (UVM_ACTIVE or UVM_PASSIVE depending on test)
    │   └── sig_monitor  ──ap──► scoreboard.item_collected_sink
    └── sig_scoreboard   (+ sig_coverage in broadcast_env)
```

### Signal Flow

`sig_driver` asserts `sig` high for `sig_length` clock cycles, then deasserts. Both monitors independently count the pulse width and write a `sig_seq_item` to the scoreboard. `check_phase` verifies every sent length matches every received length — a loopback self-check with no external reference model needed.

---

## Prerequisites

| Tool | Version tested | Notes |
|------|---------------|-------|
| Verilator | 5.046 | Build from source |
| Accellera UVM | 1800.2-2017-1.0 | Free download |
| C++ compiler | g++ / clang++ | For `sim_main.cpp` |
| GTKWave | any | Optional, for waveforms |

### Install Verilator

```sh
# Linux dependencies:
sudo apt update && sudo apt install -y bison flex libfl-dev help2man z3 \
    git autoconf make g++ perl python3

git clone https://github.com/verilator/verilator
pushd verilator && autoconf && ./configure && make -j$(nproc) && popd
export PATH="$(pwd)/verilator/bin:$PATH"
```

### Install UVM sources

```sh
wget https://www.accellera.org/images/downloads/standards/uvm/Accellera-1800.2-2017-1.0.tar.gz
tar -xzf Accellera-1800.2-2017-1.0.tar.gz
export UVM_HOME="$(pwd)/1800.2-2017-1.0/src"
```

The Makefile defaults `UVM_HOME` to `~/opt/accellera/1800.2-2017-1.0/src`. Override with `make UVM_HOME=/path/to/src`.

---

## How to Run

### Run the default test

```sh
make
```

Compiles and runs `sig_model_test` (the baseline loopback test). Produces `dump.fst`.

### Run a specific test

```sh
make TESTNAME=test_factory_override
```

Or skip recompilation if the binary is already built:

```sh
./obj_dir/Vtbench_top +UVM_TESTNAME=test_config_db
```

### Run all 11 tests

```sh
make test
```

This compiles once, then runs every test via `run_tests.sh`, which checks each test's output against expected patterns and absence patterns. Example output:

```
PASS  sig_model_test
PASS  test_factory_override
PASS  test_config_db
...
Results: 11 passed, 0 failed
```

### Inspect waveforms

```sh
make waves
```

Opens `dump.fst` in GTKWave. The waveform is produced by `sim_main.cpp` on every run.

### Clean build artifacts

```sh
make clean
```

Removes `obj_dir/` and `dump.fst`.

---

## How the Test Runner Works

`run_tests.sh` runs each test binary and checks stdout+stderr against a list of patterns:

- `"pattern"` — output **must** contain this (checked with `grep -E`)
- `"!pattern"` — output must **not** contain this

Every test also automatically requires `UVM_ERROR : 0` and `UVM_FATAL : 0`. Any test that fails a pattern check prints which pattern failed before reporting `FAIL`.

---

## Verilator-Specific Notes

- **`+define+UVM_NO_DPI`** — disables the DPI-C bridge. All pure-SV UVM operations work (factory, config_db, callbacks, register SW model). DPI-dependent features (`uvm_hdl_*` backdoor, some UVM internal utilities) do not.
- **`--timing`** — required for `fork/join`, `@(posedge clk)` delays, and the UVM time-based scheduler. Without it, time-consuming operations hang.
- **`sim_main.cpp`** — Verilator's auto-generated main (`--binary`) does not open a trace file. The custom harness is required to produce `dump.fst`.
- **Incremental builds** — Verilator may not detect changes to `.svh` files. Run `make clean && make compile` after adding or removing files.

---

## License

Copyright © 2025 Antmicro. Licensed under the Apache License 2.0 — see [LICENSE](LICENSE).
