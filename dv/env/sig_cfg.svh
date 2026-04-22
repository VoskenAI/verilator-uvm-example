class sig_cfg extends uvm_object;
  int    num_transactions = 10;
  string label            = "default";

  `uvm_object_utils_begin(sig_cfg)
    `uvm_field_int(num_transactions, UVM_DEFAULT)
    `uvm_field_string(label,         UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "sig_cfg");
    super.new(name);
  endfunction
endclass
