// Sequence whose length comes from configuration rather than a hardcoded constant.
class cfg_sequence extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(cfg_sequence)

  int num_transactions = 10;

  function new(string name = "cfg_sequence");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < num_transactions; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      void'(req.randomize());
      send_request(req);
      wait_for_item_done();
    end
  endtask
endclass

// Env subclass that retrieves sig_cfg and int from config_db in build_phase,
// demonstrating the standard parent-sets / child-gets UVM pattern.
class cfg_env extends sig_model_env;
  `uvm_component_utils(cfg_env)

  sig_cfg cfg;
  int     num_tx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(sig_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "sig_cfg not found in config_db for cfg_env")
    if (!uvm_config_db#(int)::get(this, "", "num_tx", num_tx))
      `uvm_fatal("NO_CFG", "num_tx not found in config_db for cfg_env")
    `uvm_info(get_type_name(),
      $sformatf("Config retrieved: label='%s', num_tx=%0d", cfg.label, num_tx),
      UVM_MEDIUM)
  endfunction
endclass

class test_config_db extends uvm_test;
  `uvm_component_utils(test_config_db)

  cfg_env      env;
  cfg_sequence seq;
  sig_cfg      cfg;

  function new(string name = "test_config_db", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg                  = sig_cfg::type_id::create("cfg");
    cfg.num_transactions = 5;
    cfg.label            = "config_db_test";

    // Standard pattern: parent sets for a named child before creating it.
    // Scope resolves to "uvm_test_top.env" which cfg_env.get(this,"",...)
    // matches exactly.
    uvm_config_db#(sig_cfg)::set(this, "env", "cfg",   cfg);
    uvm_config_db#(int)::set   (this, "env", "num_tx", cfg.num_transactions);

    env = cfg_env::type_id::create("env", this);
    seq = cfg_sequence::type_id::create("seq");
    seq.num_transactions = cfg.num_transactions;
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info(get_type_name(),
      $sformatf("Running '%s' with %0d transactions",
                cfg.label, cfg.num_transactions), UVM_MEDIUM)
    seq.start(env.sig_agnt_d.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
      $sformatf("Config DB test PASS: drove %0d transactions (label='%s')",
                cfg.num_transactions, cfg.label), UVM_MEDIUM)
  endfunction
endclass
