// Sequence that deliberately seeds every coverage bin before random fill.
class coverage_seq extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(coverage_seq)

  function new(string name = "coverage_seq");
    super.new(name);
  endfunction

  task send_fixed(int unsigned len);
    req = sig_seq_item::type_id::create("req");
    wait_for_grant();
    req.rand_mode(0);
    req.sig_length = len;
    send_request(req);
    wait_for_item_done();
  endtask

  virtual task body();
    send_fixed(2);   // short  bin [1:4]
    send_fixed(7);   // medium bin [5:10]
    send_fixed(13);  // long   bin [11:15]
    for (int i = 0; i < 7; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      void'(req.randomize());
      send_request(req);
      wait_for_item_done();
    end
  endtask
endclass

// Test that connects the monitor's analysis port to BOTH scoreboard and
// coverage collector, demonstrating uvm_analysis_port broadcast.
class test_broadcast_coverage extends uvm_test;
  `uvm_component_utils(test_broadcast_coverage)

  broadcast_env env;
  coverage_seq  seq;

  function new(string name = "test_broadcast_coverage", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = broadcast_env::type_id::create("env", this);
    seq = coverage_seq::type_id::create("seq");
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.start(env.sig_agnt_d.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    real cov = env.coverage.get_coverage();
    if (cov < 100.0)
      `uvm_error(get_type_name(), $sformatf(
          "Expected 100%% coverage, got %.0f%%", cov))
    else
      `uvm_info(get_type_name(), $sformatf(
          "Broadcast+coverage test PASS: coverage=%.0f%%", cov), UVM_MEDIUM)
  endfunction
endclass
