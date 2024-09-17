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
import axi4_master_sim_pkg::*;

module tb_axi4_master;

localparam                      TIMEOUT = 15000;

localparam                      CLK_PERIOD = 10;
localparam                      RST_CYCLES = 6;
localparam                      RST_ACTIVE = RST_ACTIVE_LOW;

localparam                      NUM_PARAMETERIZATIONS = 2;

localparam                      AXI_ADDR_WIDTH = 15;
localparam                      AXI_DATA_WIDTH = 32;
localparam                      AXI_ID_WIDTH = 0;
localparam                      AXI_USER_WIDTH = 0;

localparam                      USER_DATA_WIDTH = 8;

localparam                      MAX_TOTAL_TRANSACTION_LENGTH = 1000;
localparam                      REGISTER_DATA_STREAM = {0, 1};

localparam real                 T_SETUP = 1;
localparam real                 T_CTOQ = 2;

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

//----------------------------------------------------------
// SUBMODULES
//----------------------------------------------------------

//----------------------------
// REGISTER_DATA_STREAM = 1
//----------------------------

// INTERFACES
ifc_axi4 #(
    .ADDR_WIDTH         (AXI_ADDR_WIDTH),
    .DATA_WIDTH         (AXI_DATA_WIDTH),
    .ID_WIDTH           (AXI_ID_WIDTH),
    .USER_WIDTH         (AXI_USER_WIDTH)
) if_axi [NUM_PARAMETERIZATIONS] (clk, if_rst.rst);

// why are the read and write interface not embedded into ifc_axi4_master?  
// Becasue I didn't know how then you would connect to the data stream signals 
// through a clocking block, regardless of the data direction. So these 
// interfaces "translate" between the class-driven clocking if_axi4_master and 
// the actual dut.
ifc_data_stream_hs #(
    .DATA_WIDTH         (USER_DATA_WIDTH)
) if_data_read [NUM_PARAMETERIZATIONS] (clk, if_rst.rst);

ifc_data_stream_hs #(
    .DATA_WIDTH         (USER_DATA_WIDTH)
) if_data_write [NUM_PARAMETERIZATIONS] (clk, if_rst.rst);

cls_agent_axi4_master #(
    .USER_DATA_WIDTH    (USER_DATA_WIDTH),
    .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH     (AXI_DATA_WIDTH),
    .AXI_USER_WIDTH     (AXI_USER_WIDTH),
    .AXI_ID_WIDTH       (AXI_ID_WIDTH),
    .MAX_TOTAL_TRANSACTION_LENGTH   (MAX_TOTAL_TRANSACTION_LENGTH),
    .T_SETUP            (T_SETUP),
    .T_CTOQ             (T_CTOQ)
) agent_axi4_master [NUM_PARAMETERIZATIONS];

ifc_axi4_master #(
    .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH),
    .AXI_USER_WIDTH     (AXI_USER_WIDTH),
    .AXI_ID_WIDTH       (AXI_ID_WIDTH),
    .USER_DATA_WIDTH    (USER_DATA_WIDTH),
    .MAX_TOTAL_TRANSACTION_LENGTH   (MAX_TOTAL_TRANSACTION_LENGTH),
    .T_SETUP            (T_SETUP),
    .T_CTOQ             (T_CTOQ)
) if_axi4_master [NUM_PARAMETERIZATIONS] (clk);

genvar i;
generate begin: gen_dut_parameterizations

    for (i=0; i<NUM_PARAMETERIZATIONS; i++) begin

        // CONNECTIONS
        // data streams
        assign if_data_read[i].ready        = if_axi4_master[i].read_ready;
        assign if_axi4_master[i].read_valid = if_data_read[i].valid;
        assign if_axi4_master[i].read_data  = if_data_read[i].data;
        assign if_axi4_master[i].read_strb  = if_data_read[i].strb;
        assign if_axi4_master[i].write_ready= if_data_write[i].ready;
        assign if_data_write[i].valid       = if_axi4_master[i].write_valid;
        assign if_data_write[i].data        = if_axi4_master[i].write_data;
        assign if_data_write[i].strb        = if_axi4_master[i].write_strb;

        // MODULES
        axi4_master #(
            .AXI_ADDR_WIDTH                 (AXI_ADDR_WIDTH),
            .AXI_DATA_WIDTH                 (AXI_DATA_WIDTH),
            .AXI_USER_WIDTH                 (AXI_USER_WIDTH),
            .AXI_ID_WIDTH                   (AXI_ID_WIDTH),
            .USER_DATA_WIDTH                (USER_DATA_WIDTH),
            .MAX_TOTAL_TRANSACTION_LENGTH   (MAX_TOTAL_TRANSACTION_LENGTH),
            .REGISTER_DATA_STREAM           (REGISTER_DATA_STREAM[i])
        ) inst_axi4_master (
            .clk (if_axi4_master[i].clk),
            .rst_n (if_rst.rst),
            .o_ready (if_axi4_master[i].ready),
            .i_trigger (if_axi4_master[i].trigger),
            .i_num_data_words (if_axi4_master[i].num_data_words),
            .if_data_stream_write (if_data_write[i]),
            .if_data_stream_read (if_data_read[i]),
            .if_axi (if_axi[i]),
            .i_direction (if_axi4_master[i].direction),
            .i_axi_status_fields (if_axi4_master[i].axi_status_fields),
            .i_base_address (if_axi4_master[i].base_address),
            .i_axi_user (if_axi4_master[i].axi_user),
            .i_axi_id (if_axi4_master[i].axi_id),
            .o_msgs (if_axi4_master[i].axi_master_msgs),
            .i_clear_messages (if_axi4_master[i].clear_messages)
        );

        xip_bram_axi_test inst_xip_bram_axi_test (
          .s_axi_aclk(clk),        // input wire s_axi_aclk
          .s_axi_aresetn(if_rst.rst),  // input wire s_axi_aresetn
          .s_axi_awaddr(if_axi[i].awaddr),    // input wire [14 : 0] s_axi_awaddr
          .s_axi_awlen(if_axi[i].awlen),      // input wire [7 : 0] s_axi_awlen
          .s_axi_awsize(if_axi[i].awsize),    // input wire [2 : 0] s_axi_awsize
          .s_axi_awburst(if_axi[i].awburst),  // input wire [1 : 0] s_axi_awburst
          .s_axi_awlock(if_axi[i].awlock),    // input wire s_axi_awlock
          .s_axi_awcache(if_axi[i].awcache),  // input wire [3 : 0] s_axi_awcache
          .s_axi_awprot(if_axi[i].awprot),    // input wire [2 : 0] s_axi_awprot
          .s_axi_awvalid(if_axi[i].awvalid),  // input wire s_axi_awvalid
          .s_axi_awready(if_axi[i].awready),  // output wire s_axi_awready
          .s_axi_wdata(if_axi[i].wdata),      // input wire [31 : 0] s_axi_wdata
          .s_axi_wstrb(if_axi[i].wstrb),      // input wire [3 : 0] s_axi_wstrb
          .s_axi_wlast(if_axi[i].wlast),      // input wire s_axi_wlast
          .s_axi_wvalid(if_axi[i].wvalid),    // input wire s_axi_wvalid
          .s_axi_wready(if_axi[i].wready),    // output wire s_axi_wready
          .s_axi_bresp(if_axi[i].bresp),      // output wire [1 : 0] s_axi_bresp
          .s_axi_bvalid(if_axi[i].bvalid),    // output wire s_axi_bvalid
          .s_axi_bready(if_axi[i].bready),    // input wire s_axi_bready
          .s_axi_araddr(if_axi[i].araddr),    // input wire [14 : 0] s_axi_araddr
          .s_axi_arlen(if_axi[i].arlen),      // input wire [7 : 0] s_axi_arlen
          .s_axi_arsize(if_axi[i].arsize),    // input wire [2 : 0] s_axi_arsize
          .s_axi_arburst(if_axi[i].arburst),  // input wire [1 : 0] s_axi_arburst
          .s_axi_arlock(if_axi[i].arlock),    // input wire s_axi_arlock
          .s_axi_arcache(if_axi[i].arcache),  // input wire [3 : 0] s_axi_arcache
          .s_axi_arprot(if_axi[i].arprot),    // input wire [2 : 0] s_axi_arprot
          .s_axi_arvalid(if_axi[i].arvalid),  // input wire s_axi_arvalid
          .s_axi_arready(if_axi[i].arready),  // output wire s_axi_arready
          .s_axi_rdata(if_axi[i].rdata),      // output wire [31 : 0] s_axi_rdata
          .s_axi_rresp(if_axi[i].rresp),      // output wire [1 : 0] s_axi_rresp
          .s_axi_rlast(if_axi[i].rlast),      // output wire s_axi_rlast
          .s_axi_rvalid(if_axi[i].rvalid),    // output wire s_axi_rvalid
          .s_axi_rready(if_axi[i].rready)    // input wire s_axi_rready
        );

    end

end
endgenerate

//----------------------------
// OPERATION
//----------------------------

generate begin
    for (i=0; i<2; i++) begin
        initial begin
            agent_axi4_master[i] = new(if_axi4_master[i]);
        end
    end
end endgenerate

initial begin
    $timeformat(-9, 1, "ns", 3);

    rst_ctrl = new(if_rst);
//     for (int i=0; i<2; i++) begin
//         agent_axi4_master[i] = new(if_axi4_master[i]);
//     end

    rst_ctrl.init();
    rst_ctrl.trigger(RST_CYCLES);

    fork begin  // guard fork
        fork
            begin
                for (int i=0; i<NUM_PARAMETERIZATIONS; i++) begin
                    $display("Testing parameterization %0d", i);
                    agent_axi4_master[i].run(.stop(0));
                end
                $stop;
            end
            begin
                #TIMEOUT;
                $error("Simulation timeout reached!");
            end
        join_any
        disable fork;
    end join
    $stop;
end

endmodule
