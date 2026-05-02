#!/usr/bin/env bash
# Run every UVM test under xsim and verify expected output.
# Mirrors run_tests.sh (which targets the Verilator binary).
#
# Pattern syntax:
#   "pattern"   — output MUST contain this (grep -E)
#   "!pattern"  — output must NOT contain this (grep -E)
#
# Exit code: 0 = all passed, 1 = at least one failed.

set -euo pipefail

SNAPSHOT=tbench_top_sim
pass=0
fail=0

if ! command -v xsim >/dev/null; then
  echo "ERROR: xsim not found on PATH. Source Vivado settings64.sh first." >&2
  exit 1
fi

if [ ! -d "xsim.dir/$SNAPSHOT" ]; then
  echo "Snapshot not built. Run: make xsim_compile" >&2
  exit 1
fi

check() {
  local name=$1; shift
  local out ok=1

  out=$(xsim "$SNAPSHOT" -R --testplusarg "UVM_TESTNAME=$name" 2>&1)

  if ! printf '%s\n' "$out" | grep -qE "UVM_ERROR : +0$"; then
    printf '  [FAIL] UVM_ERROR not 0\n'; ok=0
  fi
  if ! printf '%s\n' "$out" | grep -qE "UVM_FATAL : +0$"; then
    printf '  [FAIL] UVM_FATAL not 0\n'; ok=0
  fi

  for pat in "$@"; do
    if [[ "$pat" == "!"* ]]; then
      local real="${pat#!}"
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
    printf 'PASS  %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL  %s\n' "$name"
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------

check sig_model_test \
  "Sent length.*are the same"

check test_factory_override \
  "Factory override PASS" \
  "min sig_length observed = ([89]|1[0-5])"

check test_config_db \
  "label='config_db_test', num_tx=5" \
  "drove 5 transactions"

check test_directed \
  "Directed test PASS" \
  "directed=3 items .len=7." \
  "constrained=3 items" \
  "max=4 items .len=15."

check test_callback \
  "post_drive called 10 times"

check test_virtual_seq \
  "Virtual seq test PASS" \
  "items_checked=10"

check test_verbosity \
  "PHASE1_LOW_VISIBLE" \
  "!PHASE1_MED_SUPPRESSED" \
  "PHASE2_MED_VISIBLE" \
  "PHASE2_HIGH_VISIBLE" \
  "!PHASE3_MED_SUPPRESSED_ON_TEST" \
  "PHASE3_SCB_STILL_HIGH_CONFIRMED" \
  "Verbosity test PASS"

check test_response \
  "Response test PASS" \
  "all 10 responses matched"

check test_reg_model \
  "predict PASS" \
  "set/get PASS" \
  "reset PASS" \
  "Register model test PASS"

check test_broadcast_coverage \
  "Broadcast.*coverage test PASS" \
  "coverage=100"

check test_passive_agent \
  "Passive agent PASS" \
  "no driver, no sequencer"

# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
