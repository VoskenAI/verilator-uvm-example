// Env that correctly configures sig_agnt_m as UVM_PASSIVE before build_phase
// creates the agent — fixing the default ACTIVE instantiation in sig_model_env.
class passive_env extends sig_model_env;
  `uvm_component_utils(passive_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(uvm_active_passive_enum)::set(
        this, "sig_agnt_m", "is_active", UVM_PASSIVE);
    super.build_phase(phase);
  endfunction
endclass
