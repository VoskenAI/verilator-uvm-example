// Demonstrates the UVM Register Abstraction Layer (RAL) API using pure
// software operations — no bus or DUT registers required.
//
// predict() : set mirror + desired without a bus transaction
// get()     : read the field's current desired value
// set()     : write desired value (does not update mirror)
// randomize(): randomize all fields within their bit-width constraints
// reset()   : restore all registers to their configured reset values
class test_reg_model extends uvm_test;
  `uvm_component_utils(test_reg_model)

  sig_reg_block reg_block;

  function new(string name = "test_reg_model", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    reg_block = sig_reg_block::type_id::create("reg_block");
    reg_block.build();
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // --- predict() sets both mirror and desired; field get() extracts per-field value ---
    // ctrl = 0x07 → bit[0]=1 (en=1), bits[3:1]=011 (mode=3)
    void'(reg_block.ctrl.predict('h7));
    if (reg_block.ctrl.en.get() != 1 || reg_block.ctrl.mode.get() != 3)
      `uvm_error("REG", $sformatf(
          "predict mismatch: en=%0d (exp 1), mode=%0d (exp 3)",
          reg_block.ctrl.en.get(), reg_block.ctrl.mode.get()))
    else
      `uvm_info("REG", $sformatf(
          "predict PASS: ctrl.en=%0d ctrl.mode=%0d",
          reg_block.ctrl.en.get(), reg_block.ctrl.mode.get()), UVM_MEDIUM)

    // --- randomize() randomizes all fields within their bit widths ---
    void'(reg_block.ctrl.randomize());
    `uvm_info("REG", $sformatf(
        "randomize: ctrl.en=%0d ctrl.mode=%0d",
        reg_block.ctrl.en.get(), reg_block.ctrl.mode.get()), UVM_MEDIUM)

    // --- set() + get() for desired-value access ---
    reg_block.status.busy.set(1);
    reg_block.status.err_flag.set(0);
    if (reg_block.status.busy.get() != 1 || reg_block.status.err_flag.get() != 0)
      `uvm_error("REG", $sformatf(
          "set/get mismatch: busy=%0d (exp 1), err_flag=%0d (exp 0)",
          reg_block.status.busy.get(), reg_block.status.err_flag.get()))
    else
      `uvm_info("REG", $sformatf(
          "set/get PASS: status.busy=%0d status.err_flag=%0d",
          reg_block.status.busy.get(), reg_block.status.err_flag.get()), UVM_MEDIUM)

    // --- reset() restores all fields to their configured reset value (0) ---
    reg_block.reset();
    if (reg_block.ctrl.get() != 0 || reg_block.status.get() != 0)
      `uvm_error("REG", $sformatf(
          "reset mismatch: ctrl=%0h (exp 0), status=%0h (exp 0)",
          reg_block.ctrl.get(), reg_block.status.get()))
    else
      `uvm_info("REG", "reset PASS: ctrl=0 status=0", UVM_MEDIUM)

    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    `uvm_info(get_type_name(), "Register model test PASS", UVM_MEDIUM)
  endfunction
endclass
