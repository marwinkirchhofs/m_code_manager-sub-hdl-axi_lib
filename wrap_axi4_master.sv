
/*
* company:
* author/engineer:
* creation date:
* project name:
* target devices:
* tool versions:
*
* * DESCRIPTION:
* Top-level wrapper for the axi4_master module, which replaces all interfaces 
* and structs at port level with simple signals
*
* * INTERFACE:
*		[port name]		- [port description]
* * inputs:
* * outputs:
*/

import axi_lib_pkg::axi4_status_fields_t;
import axi_lib_pkg::axi4_master_msgs_t;

module wrap_axi4_master #(
    parameter                           AXI_ADDR_WIDTH                  = 32,
    parameter                           AXI_DATA_WIDTH                  = 32,
    parameter                           AXI_USER_WIDTH                  = 0,
    parameter                           AXI_ID_WIDTH                    = 0,
    parameter                           USER_DATA_WIDTH                 = 32,
    // maximum number of data words in one user transaction - meaning one time 
    // asserting trigger (both for read and write)
    parameter                           MAX_TOTAL_TRANSACTION_LENGTH    = 128,
    parameter                           REGISTER_DATA_STREAM            = 0
) (
    input                                   clk,
    input                                   rst_n,
    // OPERATION CONTROL
    output logic                            o_ready,
    input                                   i_trigger,
    input                                   i_direction,
    input logic [$clog2(MAX_TOTAL_TRANSACTION_LENGTH)-1:0]      i_num_data_words,
    // USER DATA CONNECTION
    output logic    [USER_DATA_WIDTH-1:0]   o_data_stream_read_data,
    output logic    [USER_DATA_WIDTH/8-1:0] o_data_stream_read_strb,
    output logic                            o_data_stream_read_valid,
    input                                   i_data_stream_read_ready,
    input           [USER_DATA_WIDTH-1:0]   i_data_stream_write_data,
    input           [USER_DATA_WIDTH/8-1:0] i_data_stream_write_strb,
    input                                   i_data_stream_write_valid,
    output logic                            o_data_stream_write_ready,
    // AXI RELATED PORTS
    output logic    [AXI_ID_WIDTH-1:0]      o_if_axi_awid,
    output logic    [AXI_ADDR_WIDTH-1:0]    o_if_axi_awaddr,
    output logic    [7:0]                   o_if_axi_awlen,
    output logic    [2:0]                   o_if_axi_awsize,
    output logic    [1:0]                   o_if_axi_awburst,
    output logic                            o_if_axi_awlock,
    output logic    [3:0]                   o_if_axi_awcache,
    output logic    [2:0]                   o_if_axi_awprot,
    output logic    [3:0]                   o_if_axi_awqos,
    output logic    [3:0]                   o_if_axi_awregion,
    output logic    [AXI_USER_WIDTH-1:0]    o_if_axi_awuser,
    output logic                            o_if_axi_awvalid,
    input                                   i_if_axi_awready,
    output logic    [AXI_ID_WIDTH-1:0]      o_if_axi_wid,
    output logic    [AXI_DATA_WIDTH-1:0]    o_if_axi_wdata,
    output logic    [AXI_DATA_WIDTH/8-1:0]  o_if_axi_wstrb,
    output logic                            o_if_axi_wlast,
    output logic    [AXI_USER_WIDTH-1:0]    o_if_axi_wuser,
    output logic                            o_if_axi_wvalid,
    input                                   i_if_axi_wready,
    input           [AXI_ID_WIDTH-1:0]      i_if_axi_bid,
    input           [1:0]                   i_if_axi_bresp,
    input           [AXI_USER_WIDTH-1:0]    i_if_axi_buser,
    input                                   i_if_axi_bvalid,
    output logic                            o_if_axi_bready,
    output logic    [AXI_ID_WIDTH-1:0]      o_if_axi_arid,
    output logic    [AXI_ADDR_WIDTH-1:0]    o_if_axi_araddr,
    output logic    [7:0]                   o_if_axi_arlen,
    output logic    [2:0]                   o_if_axi_arsize,
    output logic    [1:0]                   o_if_axi_arburst,
    output logic                            o_if_axi_arlock,
    output logic    [3:0]                   o_if_axi_arcache,
    output logic    [2:0]                   o_if_axi_arprot,
    output logic    [3:0]                   o_if_axi_arqos,
    output logic    [3:0]                   o_if_axi_arregion,
    output logic    [AXI_USER_WIDTH-1:0]    o_if_axi_aruser,
    output logic                            o_if_axi_arvalid,
    input                                   i_if_axi_arready,
    input           [AXI_ID_WIDTH-1:0]      i_if_axi_rid,
    input           [AXI_DATA_WIDTH-1:0]    i_if_axi_rdata,
    input           [1:0]                   i_if_axi_rresp,
    input                                   i_if_axi_rlast,
    input           [AXI_USER_WIDTH-1:0]    i_if_axi_ruser,
    input                                   i_if_axi_rvalid,
    output logic                            o_if_axi_rready,

    input           [2:0]                   i_op_burst_size,
    input           [1:0]                   i_op_burst_type,
    input           [3:0]                   i_op_cache,
    input           [2:0]                   i_op_prot,
    input           [2:0]                   i_op_qos,
    input           [3:0]                   i_op_region,
    input                                   i_op_lock,

    input   [AXI_ADDR_WIDTH-1:0]            i_base_address,

    // PARAMETERIZABLE AXI RELATED PORTS
    // that's a reserved signal of user-specifiable width, so it can't go in the 
    // axi status fields struct.
    input   [AXI_USER_WIDTH-1:0]            i_axi_user,
    // also has parameterizable width -> if you don't need the signal, just tie 
    // it to 0 (1 might work as well, tying to 1 is cheaper in hardware, but in 
    // a very unfortunate case could confuse an axi slave)
    input   [AXI_ID_WIDTH-1:0]              i_axi_id,

    output logic                            o_msgs_no_rlast,
    output logic    [1:0]                   o_msgs_wresp,
    input logic                             i_clear_messages
);

    localparam int USER_STRB_WIDTH = USER_DATA_WIDTH/8;
    localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;

    //----------------------------------------------------------
    // INTERNAL SIGNALS
    //----------------------------------------------------------

    ifc_axi4                            if_axi (clk, rst_n);
    ifc_data_stream_hs                  if_data_stream_write (clk, rst_n);
    ifc_data_stream_hs                  if_data_stream_read (clk, rst_n);
    axi4_status_fields_t                axi_status_fields;
    axi4_master_msgs_t                  axi_msgs;

    //----------------------------------------------------------
    // SUBMODULES
    //----------------------------------------------------------

    assign o_if_axi_awid = if_axi.awid;
    assign o_if_axi_awaddr = if_axi.awaddr;
    assign o_if_axi_awlen = if_axi.awlen;
    assign o_if_axi_awsize = if_axi.awsize;
    assign o_if_axi_awburst = if_axi.awburst;
    assign o_if_axi_awlock = if_axi.awlock;
    assign o_if_axi_awcache = if_axi.awcache;
    assign o_if_axi_awprot = if_axi.awprot;
    assign o_if_axi_awqos = if_axi.awqos;
    assign o_if_axi_awregion = if_axi.awregion;
    assign o_if_axi_awuser = if_axi.awuser;
    assign o_if_axi_awvalid = if_axi.awvalid;
    assign if_axi.awready = i_if_axi_awready;
    assign o_if_axi_wid = if_axi.wid;
    assign o_if_axi_wdata = if_axi.wdata;
    assign o_if_axi_wstrb = if_axi.wstrb;
    assign o_if_axi_wlast = if_axi.wlast;
    assign o_if_axi_wuser = if_axi.wuser;
    assign o_if_axi_wvalid = if_axi.wvalid;
    assign if_axi.wready = i_if_axi_wready;
    assign if_axi.bid = i_if_axi_bid;
    assign if_axi.bresp = i_if_axi_bresp;
    assign if_axi.buser = i_if_axi_buser;
    assign if_axi.bvalid = i_if_axi_bvalid;
    assign o_if_axi_bready = if_axi.bready;
    assign o_if_axi_arid = if_axi.arid;
    assign o_if_axi_araddr = if_axi.araddr;
    assign o_if_axi_arlen = if_axi.arlen;
    assign o_if_axi_arsize = if_axi.arsize;
    assign o_if_axi_arburst = if_axi.arburst;
    assign o_if_axi_arlock = if_axi.arlock;
    assign o_if_axi_arcache = if_axi.arcache;
    assign o_if_axi_arprot = if_axi.arprot;
    assign o_if_axi_arqos = if_axi.arqos;
    assign o_if_axi_arregion = if_axi.arregion;
    assign o_if_axi_aruser = if_axi.aruser;
    assign o_if_axi_arvalid = if_axi.arvalid;
    assign if_axi.arready = i_if_axi_arready;
    assign if_axi.rid = i_if_axi_rid;
    assign if_axi.rdata = i_if_axi_rdata;
    assign if_axi.rresp = i_if_axi_rresp;
    assign if_axi.rlast = i_if_axi_rlast;
    assign if_axi.ruser = i_if_axi_ruser;
    assign if_axi.rvalid = i_if_axi_rvalid;
    assign o_if_axi_rready = if_axi.rready;

    assign o_data_stream_write_ready = if_data_stream_write.ready;
    assign if_data_stream_write.data = i_data_stream_write_data;
    assign if_data_stream_write.valid = i_data_stream_write_data;
    assign if_data_stream_write.strb = i_data_stream_write_strb;
    assign o_data_stream_read_data = if_data_stream_read.data;
    assign o_data_stream_read_strb = if_data_stream_read.strb;
    assign o_data_stream_read_valid = if_data_stream_read.valid;
    assign if_data_stream_read.ready = i_data_stream_read_ready;

    assign axi_status_fields.burst_size = i_op_burst_size;
    assign axi_status_fields.burst_type = i_op_burst_type;
    assign axi_status_fields.cache = i_op_cache;
    assign axi_status_fields.prot = i_op_prot;
    assign axi_status_fields.qos = i_op_qos;
    assign axi_status_fields.region = i_op_region;
    assign axi_status_fields.lock = i_op_lock;

    assign o_msgs_no_rlast = axi_msgs.no_rlast;
    assign o_msgs_wresp = axi_msgs.wresp;

    axi4_master #(
        .AXI_ADDR_WIDTH                 (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH                 (AXI_DATA_WIDTH),
        .AXI_USER_WIDTH                 (AXI_USER_WIDTH),
        .AXI_ID_WIDTH                   (AXI_ID_WIDTH),
        .USER_DATA_WIDTH                (USER_DATA_WIDTH),
        .MAX_TOTAL_TRANSACTION_LENGTH   (MAX_TOTAL_TRANSACTION_LENGTH),
        .REGISTER_DATA_STREAM           (REGISTER_DATA_STREAM)
    ) inst_axi4_master (
        .clk                            (clk),
        .rst_n                          (rst_n),
        .o_ready                        (o_ready),
        .i_trigger                      (i_trigger),
        .i_direction                    (i_direction),
        .i_num_data_words               (i_num_data_words),
        .if_data_stream_write           (if_data_stream_write),
        .if_data_stream_read            (if_data_stream_read),
        .if_axi                         (if_axi),
        .i_axi_status_fields            (axi_status_fields),
        .i_base_address                 (i_base_address),
        .i_axi_user                     (i_axi_user),
        .i_axi_id                       (i_axi_id),
        .o_msgs                         (axi_msgs),
        .i_clear_messages               (i_clear_messages)
    );

endmodule

