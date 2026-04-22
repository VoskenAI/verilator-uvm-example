// Sequence that retrieves a response from the driver after each transaction.
// Verifies the echoed sig_length matches what was sent.
class rsp_sequence extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(rsp_sequence)

  int mismatch_count = 0;

  function new(string name = "rsp_sequence");
    super.new(name);
  endfunction

  virtual task body();
    sig_seq_item rsp;
    for (int i = 0; i < 10; i++) begin
      req = sig_seq_item::type_id::create("req");
      start_item(req);
      void'(req.randomize());
      finish_item(req);       // blocks until driver calls item_done(rsp)
      get_response(rsp);      // retrieve the echoed response
      if (rsp.sig_length != req.sig_length) begin
        `uvm_error("RSP_MISMATCH", $sformatf(
            "item %0d: sent sig_length=%0d, response sig_length=%0d",
            i, req.sig_length, rsp.sig_length))
        mismatch_count++;
      end
    end
  endtask
endclass

class test_response extends uvm_test;
  `uvm_component_utils(test_response)

  sig_model_env env;
  rsp_sequence  seq;

  function new(string name = "test_response", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    set_type_override_by_type(sig_driver::get_type(), rsp_driver::get_type());
    env = sig_model_env::type_id::create("env", this);
    seq = rsp_sequence::type_id::create("seq");
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    seq.start(env.sig_agnt_d.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    if (seq.mismatch_count != 0)
      `uvm_error(get_type_name(), $sformatf(
          "%0d response mismatches detected", seq.mismatch_count))
    else
      `uvm_info(get_type_name(),
          "Response test PASS: all 10 responses matched requests", UVM_MEDIUM)
  endfunction
endclass
