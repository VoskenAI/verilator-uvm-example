# UVM with Verilator — Feature Test Suite

**Developed and maintained by [Vosken.AI](https://vosken.ai)**
*Design Hardware at the Speed of Thought*

---

A practical, runnable UVM testbench that compiles and simulates entirely under open-source [Verilator](https://github.com/verilator/verilator). The repository demonstrates eleven commonly-used UVM patterns — each in its own self-checking test — with a shell-based test runner that verifies expected output automatically.

Intended as a reference implementation, a starting point for UVM+Verilator testbenches, and a knowledge base for AI-assisted hardware verification workflows.

> **Original work:** This repository extends the minimal UVM+Verilator example by [Antmicro](https://antmicro.com), Copyright © 2025 Antmicro, licensed under Apache 2.0. Significant additions and restructuring by Vosken.AI, 2025.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Repository Structure](#repository-structure)
3. [How to Build and Run](#how-to-build-and-run)
4. [Test Coverage](#test-coverage)
5. [How the Test Runner Works](#how-the-test-runner-works)
6. [Verilator-Specific Notes](#verilator-specific-notes)
7. [License](#license)

---

## Prerequisites

| Tool | Version tested | Where to get it |
|------|---------------|-----------------|
| Verilator | 5.046 | [verilator.org](https://verilator.org/guide/latest/install.html) |
| Accellera UVM | 1800.2-2017-1.0 | [accellera.org](https://www.accellera.org/downloads/standards/uvm) |
| C++ compiler | g++ ≥ 9 / clang++ ≥ 12 | System package manager |
| GTKWave | any | Optional — for waveform inspection |

### Install Verilator from source

```sh
# Debian/Ubuntu dependencies
sudo apt update && sudo apt install -y \
    bison flex libfl-dev help2man z3 \
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
Override at any time: `make UVM_HOME=/your/path`.

---

## Repository Structure

```
.
├── Makefile              # Build targets: compile, run, test, waves, clean
├── sim_main.cpp          # C++ simulation harness (eval loop + FST waveform)
├── run_tests.sh          # Self-checking test runner
│
├── tb/
│   └── tb.sv             # Top-level module: clock, reset, VIF → config_db
│
├── dv/
│   ├── sig_pkg.sv        # Package: `includes all .svh files in dependency order
│   │
│   ├── if/
│   │   └── sig_if.sv     # Interface with DRIVER and MONITOR clocking block modports
│   │
│   ├── env/              # Reusable UVM verification components
│   │   ├── sig_item.svh           # Base sequence item (rand sig_length, 4-bit)
│   │   ├── long_sig_item.svh      # Derived item: constraint sig_length >= 8
│   │   ├── sig_cfg.svh            # Config object (uvm_object + field macros)
│   │   ├── sig_driver_cbs.svh     # Callback base class + count_cb implementation
│   │   ├── sig_sequencer.svh      # uvm_sequencer #(sig_seq_item)
│   │   ├── sig_virt_sequencer.svh # Virtual sequencer (holds real sequencer handle)
│   │   ├── sig_sequence.svh       # Default random sequence (10 transactions)
│   │   ├── sig_virt_sequence.svh  # Virtual sequence (fork/join two sub-sequences)
│   │   ├── sig_driver.svh         # Drives sig high for sig_length clocks
│   │   ├── rsp_driver.svh         # Extends sig_driver; echoes response via item_done(rsp)
│   │   ├── sig_monitor.svh        # Counts pulse width; writes to analysis port
│   │   ├── sig_agent.svh          # Sequencer + driver + monitor; honours is_active
│   │   ├── sig_scoreboard.svh     # Matches sent/received items via TLM FIFOs
│   │   ├── sig_coverage.svh       # uvm_subscriber with manual bin counters
│   │   ├── sig_reg_block.svh      # uvm_reg_block: ctrl_reg (en, mode) + status_reg
│   │   ├── sig_model_env.svh      # Base environment: two agents + scoreboard
│   │   ├── broadcast_env.svh      # Adds coverage subscriber to sig_model_env
│   │   └── passive_env.svh        # Sets sig_agnt_m to UVM_PASSIVE
│   │
│   └── tests/            # One test class per file
│       ├── sig_model_test.svh
│       ├── test_factory_override.svh
│       ├── test_config_db.svh
│       ├── test_directed.svh
│       ├── test_callback.svh
│       ├── test_virtual_seq.svh
│       ├── test_verbosity.svh
│       ├── test_response.svh
│       ├── test_reg_model.svh
│       ├── test_broadcast_coverage.svh
│       └── test_passive_agent.svh
│
└── docs/
    └── verilator_uvm.md  # Generic UVM+Verilator patterns reference
```

### UVM Component Hierarchy

```
uvm_test_top  (any test class)
└── sig_model_env  (or broadcast_env / passive_env)
    ├── sig_agnt_d   (UVM_ACTIVE — stimulus)
    │   ├── sig_sequencer
    │   ├── sig_driver   (or rsp_driver)
    │   └── sig_monitor  ──ap──► scoreboard.item_collected_source
    ├── sig_agnt_m   (UVM_ACTIVE or UVM_PASSIVE)
    │   └── sig_monitor  ──ap──► scoreboard.item_collected_sink
    └── sig_scoreboard   (+ sig_coverage in broadcast_env)
```

### Signal Flow

`sig_driver` asserts `sig` high for `sig_length` clock cycles, then deasserts.
Both monitors independently count the pulse width and write a `sig_seq_item` to the scoreboard.
`check_phase` verifies every sent length matches every received length — a loopback self-check with no external reference model.

---

## How to Build and Run

### Compile

```sh
make compile
```

Elaborates with Verilator and compiles the C++ model into `obj_dir/Vtbench_top`.

### Run the default test

```sh
make
```

Compiles (if needed) and runs `sig_model_test`. Produces `dump.fst`.

### Run a specific test

```sh
make TESTNAME=test_factory_override
```

Or, after the binary is already built:

```sh
./obj_dir/Vtbench_top +UVM_TESTNAME=test_config_db
```

### Run all 11 tests

```sh
make test
```

Expected output:

```
PASS  sig_model_test
PASS  test_factory_override
PASS  test_config_db
PASS  test_directed
PASS  test_callback
PASS  test_virtual_seq
PASS  test_verbosity
PASS  test_response
PASS  test_reg_model
PASS  test_broadcast_coverage
PASS  test_passive_agent

Results: 11 passed, 0 failed
```

### View waveforms

```sh
make waves
```

Opens `dump.fst` in GTKWave. The FST waveform is written on every simulation run.

### Clean

```sh
make clean
```

Removes `obj_dir/` and `dump.fst`.

---

## Test Coverage

| Test | UVM Pattern | Key APIs |
|------|-------------|----------|
| `sig_model_test` | Baseline loopback | `uvm_sequence`, `uvm_driver`, `uvm_monitor`, `uvm_scoreboard`, analysis ports |
| `test_factory_override` | Type substitution | `factory.set_type_override_by_type`, derived item class |
| `test_config_db` | Configuration passing | `uvm_config_db#(T)::set/get`, `uvm_object` with field macros |
| `test_directed` | Directed stimulus | `rand_mode(0)`, `randomize() with {}`, multi-sequence test |
| `test_callback` | Extensible hooks | `uvm_callback`, `uvm_register_cb`, `uvm_do_callbacks` |
| `test_virtual_seq` | Multi-agent coordination | `uvm_sequencer` (virtual), `uvm_declare_p_sequencer`, `fork/join` |
| `test_verbosity` | Message filtering | `set_report_verbosity_level_hier`, per-component override |
| `test_response` | Driver feedback | `item_done(rsp)`, `get_response(rsp)`, `set_id_info` |
| `test_reg_model` | Register abstraction | `uvm_reg_block`, `predict`, `get`, `set`, `reset` (SW only) |
| `test_broadcast_coverage` | Fan-out + coverage | Analysis port to multiple exports, `uvm_subscriber`, manual bins |
| `test_passive_agent` | Monitor-only agent | `UVM_PASSIVE` via config_db, no driver or sequencer instantiated |

### What Is Not Covered

| Feature | Reason |
|---------|--------|
| `covergroup` / `coverpoint` | Requires Verilator `--coverage` flag (not enabled) |
| RAL frontdoor (`uvm_reg_adapter`) | Requires a real bus interface; this DUT has none |
| RAL backdoor (`uvm_hdl_*`) | Requires DPI-C, disabled by `+define+UVM_NO_DPI` |
| TLM 2.0 | Not included in the UVM 1800.2 base package |
| Custom UVM phases | Standard build/connect/run/check/report phases cover all patterns here |
| `uvm_event` / `uvm_barrier` | Not demonstrated; useful for fine-grained multi-agent synchronization |

---

## How the Test Runner Works

`run_tests.sh` executes each test binary and evaluates the output against a per-test list of assertions:

| Syntax | Meaning |
|--------|---------|
| `"pattern"` | Output **must** contain this string (evaluated as an extended regex) |
| `"!pattern"` | Output must **not** contain this string |

All tests unconditionally require `UVM_ERROR : 0` and `UVM_FATAL : 0`.
A test is marked `FAIL` if any assertion fails, and the specific failing pattern is printed.

---

## Verilator-Specific Notes

| Flag / Feature | Notes |
|----------------|-------|
| `+define+UVM_NO_DPI` | Mandatory. Disables the DPI-C bridge; without it Verilator fails linking. All pure-SV UVM operations remain functional. |
| `--timing` | Mandatory. Enables the time-aware scheduler for `fork/join`, `@(posedge clk)`, and `#n` delays. |
| `sim_main.cpp` | Required for waveform output. Verilator's auto-generated `main()` (`--binary`) calls `traceEverOn()` but never opens the FST file. The custom 25-line harness adds `tfp->open("dump.fst")`. |
| Incremental builds | Verilator tracks top-level sources but may miss changes inside `+incdir` directories. Run `make clean && make compile` after adding or removing `.svh` files. |

---

## License

The original Antmicro example is copyright © 2025 Antmicro and licensed under the
[Apache License, Version 2.0](LICENSE).

Additions and modifications by Vosken.AI are also provided under the Apache License, Version 2.0.

You may use, copy, modify, and distribute this work under the terms of that license.
See the [LICENSE](LICENSE) file for the full text.
