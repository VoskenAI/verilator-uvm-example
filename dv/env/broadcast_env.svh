// Env that fans sig_agnt_d's monitor analysis port out to BOTH the scoreboard
// (inherited from sig_model_env) AND a sig_coverage subscriber — demonstrating
// uvm_analysis_port broadcast to multiple consumers.
class broadcast_env extends sig_model_env;
  `uvm_component_utils(broadcast_env)

  sig_coverage coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    coverage = sig_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    sig_agnt_d.monitor.item_collected_port.connect(coverage.analysis_export);
  endfunction
endclass
