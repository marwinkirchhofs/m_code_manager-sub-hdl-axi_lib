`timescale 1ns/1ps

/*
* !!! README - MAKE IT RUN !!!
* a few things that you have to change in order to make the testbench template 
* runnable
* * tb_<module>.sv (aka this file)
*     * generate clocks - connect to dut ports
*     * make sure that the reset is synchronous to the correct clock
*     * connect the reset to the dut
*     * instantiate any other necessary module in the test environment, like 
*       a component model
* * agent_<module>.sv
*     * name if_<module>.clk to the/a correct clock from the actual interface
*     * adapt the btn_change example
*         * for writing you own code: comment it out
*         * for doing a functionality check: change if_<module>.buttons into 
*           a signal that exists in you interface
*/


import util_pkg::*;
import axi_lite_reg_file_direct_access_sim_pkg::*;
import reg_file_pkg::*;

module tb_axi_lite_reg_file_direct_access;

localparam                      TIMEOUT = 1000;

localparam                      CLK_PERIOD = 10;
localparam                      RST_CYCLES = 6;
localparam                      RST_ACTIVE = RST_ACTIVE_LOW;

localparam                      REGISTER_WIDTH = 32;
localparam                      PARALLEL_ACCESS = 1;

//----------------------------
// CLOCK/RESET
//----------------------------

logic                           clk;

initial begin
    clk <= 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

ifc_rst #(CLK_PERIOD) if_rst (clk);
cls_rst_ctrl #(RST_ACTIVE) rst_ctrl;

//----------------------------
// SUBMODULES
//----------------------------

cls_agent_axi_lite_reg_file_direct_access #(
    .REGISTER_WIDTH             (REGISTER_WIDTH),
    .NUM_REGISTERS              (REG_FILE_NUM_REGISTERS)
) agent_axi_lite_reg_file_direct_access;

ifc_axi_lite_reg_file_direct_access #(
    .REGISTER_WIDTH             (REGISTER_WIDTH),
    .NUM_REGISTERS              (REG_FILE_NUM_REGISTERS)
) if_axi_lite_reg_file_direct_access(clk, if_rst.rst);

ifc_axi4_lite #(
) if_axi_ctrl (clk, if_rst.rst);

axi_lite_reg_file_direct_access #(
    .REGISTER_WIDTH             (REGISTER_WIDTH),
    .NUM_REGISTERS              (REG_FILE_NUM_REGISTERS)
) inst_axi_lite_reg_file_direct_access (
    .clk (if_axi_lite_reg_file_direct_access.clk),
    .rst_n (if_rst.rst),
    .if_axi_ctrl (if_axi_ctrl),
    .if_reg_file_hw (if_axi_lite_reg_file_direct_access.if_reg_file_hw),
    .o_axi_ctrl_trigger (if_axi_lite_reg_file_direct_access.axi_ctrl_trigger)
);

// connect the DUT's if_axi_ctrl to the agent's if_axi_sim
assign if_axi_ctrl.awaddr       = if_axi_lite_reg_file_direct_access.if_axi_sim.awaddr;
assign if_axi_ctrl.awprot       = if_axi_lite_reg_file_direct_access.if_axi_sim.awprot;
assign if_axi_ctrl.awvalid      = if_axi_lite_reg_file_direct_access.if_axi_sim.awvalid;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.awready   = if_axi_ctrl.awready;
assign if_axi_ctrl.wdata        = if_axi_lite_reg_file_direct_access.if_axi_sim.wdata;
assign if_axi_ctrl.wstrb        = if_axi_lite_reg_file_direct_access.if_axi_sim.wstrb;
assign if_axi_ctrl.wvalid       = if_axi_lite_reg_file_direct_access.if_axi_sim.wvalid;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.wready    = if_axi_ctrl.wready;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.bresp     = if_axi_ctrl.bresp;
assign if_axi_ctrl.bready       = if_axi_lite_reg_file_direct_access.if_axi_sim.bready;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.bvalid    = if_axi_ctrl.bvalid;
assign if_axi_ctrl.araddr       = if_axi_lite_reg_file_direct_access.if_axi_sim.araddr;
assign if_axi_ctrl.arprot       = if_axi_lite_reg_file_direct_access.if_axi_sim.arprot;
assign if_axi_ctrl.arvalid      = if_axi_lite_reg_file_direct_access.if_axi_sim.arvalid;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.arready   = if_axi_ctrl.arready;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.rdata     = if_axi_ctrl.rdata;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.rresp     = if_axi_ctrl.rresp;
assign if_axi_lite_reg_file_direct_access.if_axi_sim.rvalid    = if_axi_ctrl.rvalid;
assign if_axi_ctrl.rready       = if_axi_lite_reg_file_direct_access.if_axi_sim.rready;

//----------------------------
// OPERATION
//----------------------------

initial begin
    $timeformat(-9, 1, "ns", 3);

    rst_ctrl = new(if_rst);
    agent_axi_lite_reg_file_direct_access = new(if_axi_lite_reg_file_direct_access);

    rst_ctrl.init();
    rst_ctrl.trigger(RST_CYCLES);

    fork
    begin
        agent_axi_lite_reg_file_direct_access.run();
    end
    begin
        #TIMEOUT;
        $error("Timeout reached! Aborting...");
    end
    join_any;
    $stop;
end

endmodule
