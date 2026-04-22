class directed_seq extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(directed_seq)

  int fixed_length = 7;
  int item_count   = 0;

  function new(string name = "directed_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < 3; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      req.rand_mode(0);
      req.sig_length = fixed_length;
      send_request(req);
      wait_for_item_done();
      item_count++;
    end
  endtask
endclass

class constrained_seq extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(constrained_seq)

  int item_count = 0;
  int max_seen   = 0;

  function new(string name = "constrained_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < 3; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      void'(req.randomize() with { sig_length inside {[1:3]}; });
      send_request(req);
      wait_for_item_done();
      item_count++;
      if (req.sig_length > max_seen) max_seen = req.sig_length;
    end
  endtask
endclass

class max_seq extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(max_seq)

  int item_count = 0;

  function new(string name = "max_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < 4; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      req.rand_mode(0);
      req.sig_length = 15;
      send_request(req);
      wait_for_item_done();
      item_count++;
    end
  endtask
endclass

class test_directed extends uvm_test;
  `uvm_component_utils(test_directed)

  sig_model_env   env;
  directed_seq    d_seq;
  constrained_seq c_seq;
  max_seq         m_seq;

  function new(string name = "test_directed", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env   = sig_model_env::type_id::create("env", this);
    d_seq = directed_seq::type_id::create("d_seq");
    c_seq = constrained_seq::type_id::create("c_seq");
    m_seq = max_seq::type_id::create("m_seq");
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    d_seq.start(env.sig_agnt_d.sequencer);
    c_seq.start(env.sig_agnt_d.sequencer);
    m_seq.start(env.sig_agnt_d.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    int ok = 1;

    if (d_seq.item_count != 3) begin
      `uvm_error(get_type_name(), $sformatf(
          "directed_seq: expected 3 items, got %0d", d_seq.item_count))
      ok = 0;
    end
    if (d_seq.fixed_length != 7) begin
      `uvm_error(get_type_name(), $sformatf(
          "directed_seq: expected fixed_length=7, got %0d", d_seq.fixed_length))
      ok = 0;
    end

    if (c_seq.item_count != 3) begin
      `uvm_error(get_type_name(), $sformatf(
          "constrained_seq: expected 3 items, got %0d", c_seq.item_count))
      ok = 0;
    end
    if (c_seq.max_seen > 3) begin
      `uvm_error(get_type_name(), $sformatf(
          "constrained_seq: max_seen=%0d exceeds constraint [1:3]", c_seq.max_seen))
      ok = 0;
    end

    if (m_seq.item_count != 4) begin
      `uvm_error(get_type_name(), $sformatf(
          "max_seq: expected 4 items, got %0d", m_seq.item_count))
      ok = 0;
    end

    if (ok)
      `uvm_info(get_type_name(), $sformatf(
          "Directed test PASS: directed=%0d items (len=%0d), constrained=%0d items (max=%0d), max=%0d items (len=15)",
          d_seq.item_count, d_seq.fixed_length,
          c_seq.item_count, c_seq.max_seen,
          m_seq.item_count), UVM_MEDIUM)
  endfunction
endclass
