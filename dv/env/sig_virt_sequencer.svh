class sig_virt_sequencer extends uvm_sequencer;
  sig_sequencer seqr;

  `uvm_component_utils(sig_virt_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
