class test_callback extends uvm_test;
  `uvm_component_utils(test_callback)

  sig_model_env env;
  sig_sequence  seq;
  count_cb      cb;

  function new(string name = "test_callback", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sig_model_env::type_id::create("env", this);
    seq = sig_sequence::type_id::create("seq");
    cb  = count_cb::type_id::create("cb");
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    uvm_callbacks #(sig_driver, sig_driver_cb)::add(env.sig_agnt_d.driver, cb);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.start(env.sig_agnt_d.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    if (cb.call_count != 10)
      `uvm_error("CB_FAIL",
        $sformatf("Expected 10 callback calls, got %0d", cb.call_count))
    else
      `uvm_info(get_type_name(),
        $sformatf("Callback test PASS: post_drive called %0d times", cb.call_count),
        UVM_MEDIUM)
  endfunction
endclass
