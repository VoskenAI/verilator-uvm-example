// Functional coverage collector — subscribes to the monitor's analysis port
// and tracks which sig_length bins have been hit.
// Manual bin counting is used because Verilator requires --coverage to enable
// covergroup instrumentation (not set in this project's Makefile).
class sig_coverage extends uvm_subscriber #(sig_seq_item);
  `uvm_component_utils(sig_coverage)

  // Equivalent covergroup concept:
  //   covergroup sig_len_cg;
  //     sig_length_cp: coverpoint trans.sig_length {
  //       bins short  = {[1:4]};
  //       bins medium = {[5:10]};
  //       bins long   = {[11:15]};
  //     }
  //   endgroup
  int unsigned bin_short  = 0;
  int unsigned bin_medium = 0;
  int unsigned bin_long   = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void write(sig_seq_item t);
    if      (t.sig_length inside {[1:4]})   bin_short++;
    else if (t.sig_length inside {[5:10]})  bin_medium++;
    else if (t.sig_length inside {[11:15]}) bin_long++;
  endfunction

  function real get_coverage();
    int unsigned hit = (bin_short > 0) + (bin_medium > 0) + (bin_long > 0);
    return 100.0 * hit / 3;
  endfunction

  function void check_phase(uvm_phase phase);
    real cov = get_coverage();
    `uvm_info(get_type_name(), $sformatf(
        "Functional coverage: %.0f%% (short=%0d, medium=%0d, long=%0d)",
        cov, bin_short, bin_medium, bin_long), UVM_MEDIUM)
    if (cov < 100.0)
      `uvm_warning(get_type_name(), $sformatf(
          "Coverage below 100%%: %.0f%%", cov))
  endfunction
endclass
