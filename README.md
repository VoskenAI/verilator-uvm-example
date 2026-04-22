# UVM with Verilator — Feature Test Suite

> **Updated by [Vosken.AI](https://vosken.ai) — Design Hardware at the Speed of Thought**

A practical UVM testbench running under open-source Verilator, demonstrating eleven commonly-used UVM patterns with a fully self-checking test suite.

Based on the original example by [Antmicro](https://antmicro.com) (Copyright © 2025).

---

## Prerequisites

| Tool | Version tested | Notes |
|------|---------------|-------|
| Verilator | 5.046 | Build from source (see below) |
| Accellera UVM | 1800.2-2017-1.0 | Free download from accellera.org |
| GTKWave | any | Optional — for waveform viewing |

### Install Verilator (Linux / macOS)

```sh
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

The Makefile defaults `UVM_HOME` to `~/opt/accellera/1800.2-2017-1.0/src`.

---

## Quick Start

```sh
make                                     # compile + run sig_model_test
make TESTNAME=test_factory_override      # run a specific test
make test                                # compile then run all 11 tests
make waves                               # open dump.fst in GTKWave
make clean                               # remove obj_dir/ and dump.fst
```

Run all tests and see pass/fail summary:

```sh
make test
# Results: 11 passed, 0 failed
```

---

## Repository Layout

```
Makefile           # Build rules (Verilator flags, test runner target)
sim_main.cpp       # C++ harness: eval loop + FST waveform trace
run_tests.sh       # Self-checking test runner (supports !pattern absence checks)
tb/
  tb.sv            # Top-level module: clock, reset, VIF config_db registration
dv/
  sig_pkg.sv       # Package that `includes all .svh files in dependency order
  if/
    sig_if.sv      # Interface with DRIVER/MONITOR clocking block modports
  env/             # Reusable UVM components (items, sequences, driver, monitor, …)
  tests/           # One .svh per UVM test class
docs/
  verilator_uvm.md # UVM+Verilator patterns reference for AI-assisted TB development
```

---

## UVM Feature Coverage

| Test | UVM Feature Demonstrated |
|------|--------------------------|
| `sig_model_test` | Baseline: component hierarchy, sequences, analysis ports, scoreboard `check_phase` |
| `test_factory_override` | `set_type_override_by_type`, `uvm_object` subclassing, factory transparency |
| `test_config_db` | `uvm_config_db` with custom `uvm_object` and `int`; parent→named-child scope pattern |
| `test_directed` | `rand_mode(0)`, `randomize() with {}` inline constraints, multi-phase directed test |
| `test_callback` | `uvm_callback`, `uvm_register_cb`, `uvm_do_callbacks`, call-count verification |
| `test_virtual_seq` | Virtual sequencer, `uvm_declare_p_sequencer`, fork/join parallel sub-sequences |
| `test_verbosity` | `set_report_verbosity_level_hier`, per-component override, phase-gated messages |
| `test_response` | `item_done(rsp)`, `get_response(rsp)`, driver-to-sequence response channel |
| `test_reg_model` | `uvm_reg_block`, `predict()`, `get()`, `set()`, `randomize()`, `reset()` (SW model) |
| `test_broadcast_coverage` | Analysis port fan-out to multiple subscribers, `uvm_subscriber`, manual bin coverage |
| `test_passive_agent` | `UVM_PASSIVE` via config_db, driver/sequencer not created, monitor-only agent |

---

## What Is Not Covered

These UVM features require capabilities not available in this setup:

| Feature | Reason |
|---------|--------|
| `covergroup` / `coverpoint` | Requires Verilator `--coverage` flag (not enabled) |
| RAL frontdoor (`uvm_reg_adapter`) | Requires a real bus interface; DUT here has no bus |
| RAL backdoor (`uvm_hdl_*`) | Requires DPI-C, disabled with `+define+UVM_NO_DPI` |
| TLM 2.0 (`uvm_tlm_generic_payload`) | Not exercised; TLM1 sufficient for this DUT |
| Custom UVM phases | Not needed; standard phases cover all demonstrated patterns |
| `uvm_event` / `uvm_barrier` | Not demonstrated; useful for multi-agent synchronization |

---

## Verilator-Specific Notes

- `+define+UVM_NO_DPI` — disables the DPI-C bridge. All pure-SV UVM operations work (factory, config_db, callbacks, register predict/get/set). DPI-dependent features do not.
- `--timing` — required for `fork/join`, `@(posedge clk)` delays, and time-based UVM scheduler operations.
- `--trace-fst` — generates `dump.fst` for waveform inspection with GTKWave.
- After renaming or removing `.svh` files, run `make clean && make compile` to force a full rebuild.

---

## License

Copyright © 2025 Antmicro. Licensed under the Apache License 2.0 — see [LICENSE](LICENSE).
