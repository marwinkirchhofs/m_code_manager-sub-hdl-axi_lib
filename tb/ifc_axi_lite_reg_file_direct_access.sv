interface ifc_axi_lite_reg_file_direct_access #(
    parameter               REGISTER_WIDTH = 32,
    parameter               NUM_REGISTERS = 16
) (
    input clk,
    input rst_n
);

    // the idea is: you need to connect the axi4 from the sim axi master to the 
    // axi4-lite interface of the dut. The best way (afaik) to connect 
    // interfaces is by straight assignment in rtl-style code. So I'll do that 
    // in the tb, then that's out of the way. The agent can operate the 
    // if_axi_sim via the axi sim master. That should also free us of any 
    // potential inconsistencies with the clocking block in the axi sim 
    // interface, if the signals are assigned to and from the axi ctrl interface 
    // at specific points in time.
    ifc_axi4                        if_axi_sim (clk, rst_n);
//     ifc_axi4_lite                   if_axi_ctrl (clk, rst_n);
    ifc_reg_file_direct_access      #(
        .REGISTER_WIDTH         (REGISTER_WIDTH),
        .NUM_REGISTERS          (NUM_REGISTERS)
    ) if_reg_file_hw (clk);
    logic [NUM_REGISTERS-1:0]       axi_ctrl_trigger;

endinterface
