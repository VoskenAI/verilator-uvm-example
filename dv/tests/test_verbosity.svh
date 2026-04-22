class test_verbosity extends uvm_test;
  `uvm_component_utils(test_verbosity)

  sig_model_env env;
  sig_sequence  seq;

  function new(string name = "test_verbosity", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sig_model_env::type_id::create("env", this);
    seq = sig_sequence::type_id::create("seq");
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // --- 1. Global verbosity = LOW: MEDIUM messages are suppressed ---
    set_report_verbosity_level_hier(UVM_LOW);
    `uvm_info("VERB", "PHASE1_LOW_VISIBLE",    UVM_LOW)
    `uvm_info("VERB", "PHASE1_MED_SUPPRESSED", UVM_MEDIUM)

    // --- 2. Global verbosity = HIGH: both MEDIUM and HIGH now pass ---
    set_report_verbosity_level_hier(UVM_HIGH);
    `uvm_info("VERB", "PHASE2_MED_VISIBLE",    UVM_MEDIUM)
    `uvm_info("VERB", "PHASE2_HIGH_VISIBLE",   UVM_HIGH)

    // --- 3. Per-component override: lower the test back to LOW,
    //        leaving env and children at HIGH.
    //        A MEDIUM message from this component is now suppressed,
    //        while env.sig_scb is still at HIGH (confirmed via get). ---
    set_report_verbosity_level(UVM_LOW);
    `uvm_info("VERB", "PHASE3_MED_SUPPRESSED_ON_TEST", UVM_MEDIUM)

    if (env.sig_scb.get_report_verbosity_level() >= UVM_HIGH)
      `uvm_info("VERB", "PHASE3_SCB_STILL_HIGH_CONFIRMED", UVM_LOW)
    else
      `uvm_error("VERB", "per-component override failed: scoreboard verbosity not HIGH")

    // Restore to MEDIUM for the sequence run
    set_report_verbosity_level_hier(UVM_MEDIUM);
    seq.start(env.sig_agnt_d.sequencer);

    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    `uvm_info(get_type_name(), "Verbosity test PASS", UVM_MEDIUM)
  endfunction
endclass
