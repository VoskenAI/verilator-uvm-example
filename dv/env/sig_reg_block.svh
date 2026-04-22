class sig_ctrl_reg extends uvm_reg;
  `uvm_object_utils(sig_ctrl_reg)

  rand uvm_reg_field en;    // bit [0]   : enable
  rand uvm_reg_field mode;  // bits [3:1]: operating mode

  function new(string name = "sig_ctrl_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    en   = uvm_reg_field::type_id::create("en");
    mode = uvm_reg_field::type_id::create("mode");
    //            parent  size  lsb  access  volatile  reset  has_reset  is_rand  individually_accessible
    en.configure  (this,  1,    0,   "RW",   0,        1'b0,  1,         1,       0);
    mode.configure(this,  3,    1,   "RW",   0,        3'b0,  1,         1,       0);
  endfunction
endclass

class sig_status_reg extends uvm_reg;
  `uvm_object_utils(sig_status_reg)

  rand uvm_reg_field busy;
  rand uvm_reg_field err_flag;

  function new(string name = "sig_status_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    busy     = uvm_reg_field::type_id::create("busy");
    err_flag = uvm_reg_field::type_id::create("err_flag");
    busy.configure    (this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    err_flag.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
  endfunction
endclass

class sig_reg_block extends uvm_reg_block;
  `uvm_object_utils(sig_reg_block)

  rand sig_ctrl_reg   ctrl;
  rand sig_status_reg status;

  function new(string name = "sig_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    ctrl   = sig_ctrl_reg::type_id::create("ctrl");
    status = sig_status_reg::type_id::create("status");
    ctrl.configure  (this, null, "");
    status.configure(this, null, "");
    ctrl.build();
    status.build();
    default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN);
    default_map.add_reg(ctrl,   'h0, "RW");
    default_map.add_reg(status, 'h4, "RW");
    lock_model();
  endfunction
endclass
