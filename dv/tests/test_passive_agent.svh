class test_passive_agent extends uvm_test;
  `uvm_component_utils(test_passive_agent)

  passive_env  env;
  sig_sequence seq;

  function new(string name = "test_passive_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = passive_env::type_id::create("env", this);
    seq = sig_sequence::type_id::create("seq");
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.start(env.sig_agnt_d.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    if (env.sig_agnt_m.get_is_active() != UVM_PASSIVE)
      `uvm_error(get_type_name(), "sig_agnt_m is not UVM_PASSIVE")
    else if (env.sig_agnt_m.driver != null)
      `uvm_error(get_type_name(), "passive sig_agnt_m.driver should be null")
    else if (env.sig_agnt_m.sequencer != null)
      `uvm_error(get_type_name(), "passive sig_agnt_m.sequencer should be null")
    else
      `uvm_info(get_type_name(),
          "Passive agent PASS: sig_agnt_m has monitor only (no driver, no sequencer)",
          UVM_MEDIUM)
  endfunction
endclass
