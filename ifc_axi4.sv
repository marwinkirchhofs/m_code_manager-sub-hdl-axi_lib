`timescale 1ns/1ps

interface ifc_axi4 #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 0,
    parameter int USER_WIDTH = 0,
    parameter real T_SETUP = 1,
    parameter real T_CTOQ = 2
) (
    input clk,
    input rst_n
);

    localparam int STRB_WIDTH = DATA_WIDTH/8;

    // WRITE ADDRESS CHANNEL
    logic [ID_WIDTH-1:0]            awid;      // "process" ID
    logic [ADDR_WIDTH-1:0]          awaddr;
    logic [7:0]                     awlen;     // burst length
    logic [2:0]                     awsize;    // transfer size
    logic [1:0]                     awburst;   // burst type
    logic                           awlock;    // exclusive write
    logic [3:0]                     awcache;   // cacheable information
    logic [2:0]                     awprot;    // access permissions
    logic [3:0]                     awqos;     // priority indication recommended
    logic [3:0]                     awregion;  // "slave interface multiplexing"
    logic [USER_WIDTH-1:0]          awuser;    // unspecified
    logic                           awvalid;
    logic                           awready;

    // WRITE DATA CHANNEL
    logic [ID_WIDTH-1:0]            wid;  // removed in AXI4 TODO: check with the IP interfaces
    logic [DATA_WIDTH-1:0]          wdata;
    logic [STRB_WIDTH-1:0]          wstrb;
    logic                           wlast;
    logic [USER_WIDTH-1:0]          wuser;     // unspecified
    logic                           wvalid;
    logic                           wready;

    // WRITE RESPONSE CHANNEL
    logic [ID_WIDTH-1:0]            bid;       // "process" ID
    logic [1:0]                     bresp;
    logic [USER_WIDTH-1:0]          buser;     // unspecified
    logic                           bvalid;
    logic                           bready;

    // READ ADDRESS CHANNEL
    logic [ID_WIDTH-1:0]            arid;      // "process" ID
    logic [ADDR_WIDTH-1:0]          araddr;
    logic [7:0]                     arlen;     // burst length
    logic [2:0]                     arsize;    // transfer size
    logic [1:0]                     arburst;   // burst type
    logic                           arlock;    // exclusive read
    logic [3:0]                     arcache;   // cacheable information
    logic [2:0]                     arprot;    // access permissions
    logic [3:0]                     arqos;     // priority indication recommended
    logic [3:0]                     arregion;  // "slave interface multiplexing"
    logic [USER_WIDTH-1:0]          aruser;    // unspecified
    logic                           arvalid;
    logic                           arready;

    // READ DATA CHANNEL
    logic [ID_WIDTH-1:0]            rid;       // "process" ID
    logic [DATA_WIDTH-1:0]          rdata;
    logic [1:0]                     rresp;
    logic                           rlast;
    logic [USER_WIDTH-1:0]          ruser;     // unspecified
    logic                           rvalid;
    logic                           rready;

    modport master (
        // WRITE ADDRESS CHANNEL
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
        output awqos, awregion, awuser, awvalid,
        input awready,
        // WRITE DATA CHANNEL
        output wid, wdata, wstrb, wlast, wuser, wvalid,
        input wready,
        // WRITE RESPONSE CHANNEL
        input bid, bresp, buser, bvalid,
        output bready,
        // READ ADDRESS CHANNEL
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
        output arqos, arregion, aruser, arvalid,
        input arready,
        // READ DATA CHANNEL
        input rid, rdata, rresp, rlast, ruser, rvalid,
        output rready
        );

    modport slave (
        // WRITE ADDRESS CHANNEL
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
        input awqos, awregion, awuser, awvalid,
        output awready,
        // WRITE DATA CHANNEL
        input wid, wdata, wstrb, wlast, wuser, wvalid,
        output wready,
        // WRITE RESPONSE CHANNEL
        output bid, bresp, buser, bvalid,
        input bready,
        // READ ADDRESS CHANNEL
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
        input arqos, arregion, aruser, arvalid,
        output arready,
        // READ DATA CHANNEL
        output rid, rdata, rresp, rlast, ruser, rvalid,
        input rready
        );

    modport monitor (
        // WRITE ADDRESS CHANNEL
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
        input awqos, awregion, awuser, awvalid,
        input awready,
        // WRITE DATA CHANNEL
        input wid, wdata, wstrb, wlast, wuser, wvalid,
        input wready,
        // WRITE RESPONSE CHANNEL
        input bid, bresp, buser, bvalid,
        input bready,
        // READ ADDRESS CHANNEL
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
        input arqos, arregion, aruser, arvalid,
        input arready,
        // READ DATA CHANNEL
        input rid, rdata, rresp, rlast, ruser, rvalid,
        input rready
        );

`ifndef VERILATOR
    // it might be that verilator has issues at dealing with assertions, so 
    // exclude them from verilator (TODO: check with the current verilator 
    // options set)
    assert_valid_bus_width: assert property (
            @(posedge clk) DATA_WIDTH inside {8, 16, 32, 64, 128, 256, 512, 1024});
`endif
    
endinterface
