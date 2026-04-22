class test_virtual_seq extends uvm_test;
  `uvm_component_utils(test_virtual_seq)

  sig_model_env      env;
  sig_virt_sequencer vseqr;

  function new(string name = "test_virtual_seq", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env   = sig_model_env::type_id::create("env",   this);
    vseqr = sig_virt_sequencer::type_id::create("vseqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    vseqr.seqr = env.sig_agnt_d.sequencer;
  endfunction

  task run_phase(uvm_phase phase);
    sig_virt_sequence vseq;
    phase.raise_objection(this);
    vseq = sig_virt_sequence::type_id::create("vseq");
    vseq.start(vseqr);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    int total = env.sig_scb.items_checked;
    if (total != 10)
      `uvm_error(get_type_name(), $sformatf(
          "Expected 10 items (5 short + 5 long), scoreboard checked %0d", total))
    else
      `uvm_info(get_type_name(), $sformatf(
          "Virtual seq test PASS: items_checked=%0d", total), UVM_MEDIUM)
  endfunction
endclass
