// Driver that echoes each driven transaction back to the sequence as a response.
// Override sig_driver's run_phase to call item_done(rsp) instead of item_done().
class rsp_driver extends sig_driver;
  `uvm_component_utils(rsp_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    sig_seq_item rsp;
    forever begin
      fork begin
          fork
            begin
              @(posedge vif.reset) vif.driver_cb.sig <= 0;
            end
            begin
              seq_item_port.get_next_item(req);
              drive();
              rsp = sig_seq_item::type_id::create("rsp");
              rsp.set_id_info(req);
              rsp.sig_length = req.sig_length;
              seq_item_port.item_done(rsp);
            end
          join_any
          disable fork;
      end join
    end
  endtask
endclass
