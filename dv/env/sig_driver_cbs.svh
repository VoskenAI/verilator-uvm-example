class sig_driver_cb extends uvm_callback;
  `uvm_object_utils(sig_driver_cb)

  function new(string name = "sig_driver_cb");
    super.new(name);
  endfunction

  virtual task post_drive(sig_seq_item item);
  endtask
endclass

class count_cb extends sig_driver_cb;
  `uvm_object_utils(count_cb)

  int call_count = 0;

  function new(string name = "count_cb");
    super.new(name);
  endfunction

  virtual task post_drive(sig_seq_item item);
    call_count++;
    `uvm_info("COUNT_CB", $sformatf("post_drive #%0d: sig_length=%0d",
              call_count, item.sig_length), UVM_HIGH)
  endtask
endclass
