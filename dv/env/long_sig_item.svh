class long_sig_item extends sig_seq_item;
  `uvm_object_utils(long_sig_item)

  constraint long_c { sig_length >= 8; }

  function new(string name = "long_sig_item");
    super.new(name);
  endfunction
endclass
