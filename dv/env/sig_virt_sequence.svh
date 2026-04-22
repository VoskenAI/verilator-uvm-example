class short_burst_seq extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(short_burst_seq)

  function new(string name = "short_burst_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < 5; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      void'(req.randomize() with { sig_length inside {[1:4]}; });
      send_request(req);
      wait_for_item_done();
    end
  endtask
endclass

class long_burst_seq extends uvm_sequence #(sig_seq_item);
  `uvm_object_utils(long_burst_seq)

  function new(string name = "long_burst_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < 5; i++) begin
      req = sig_seq_item::type_id::create("req");
      wait_for_grant();
      void'(req.randomize() with { sig_length inside {[8:15]}; });
      send_request(req);
      wait_for_item_done();
    end
  endtask
endclass

class sig_virt_sequence extends uvm_sequence;
  `uvm_object_utils(sig_virt_sequence)
  `uvm_declare_p_sequencer(sig_virt_sequencer)

  function new(string name = "sig_virt_sequence");
    super.new(name);
  endfunction

  virtual task body();
    short_burst_seq short_seq;
    long_burst_seq  long_seq;
    short_seq = short_burst_seq::type_id::create("short_seq");
    long_seq  = long_burst_seq::type_id::create("long_seq");
    short_seq.start(p_sequencer.seqr);
    long_seq.start(p_sequencer.seqr);
  endtask
endclass
