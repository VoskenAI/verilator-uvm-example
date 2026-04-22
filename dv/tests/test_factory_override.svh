class factory_check_seq extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(factory_check_seq)

  int min_length = 15;

  function new(string name = "factory_check_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < 10; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      void'(req.randomize());
      send_request(req);
      wait_for_item_done();
      if (req.sig_length < min_length) min_length = req.sig_length;
    end
  endtask
endclass

class test_factory_override extends uvm_test;
  `uvm_component_utils(test_factory_override)

  sig_model_env     env;
  factory_check_seq seq;

  function new(string name = "test_factory_override", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_type_override_by_type(sig_seq_item::get_type(), long_sig_item::get_type());
    env = sig_model_env::type_id::create("env", this);
    seq = factory_check_seq::type_id::create("seq");
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.start(env.sig_agnt_d.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    if (seq.min_length < 8)
      `uvm_error("FACTORY_FAIL",
        $sformatf("Factory override failed: min sig_length=%0d, expected >=8",
                  seq.min_length))
    else
      `uvm_info(get_type_name(),
        $sformatf("Factory override PASS: min sig_length observed = %0d",
                  seq.min_length), UVM_MEDIUM)
  endfunction
endclass
