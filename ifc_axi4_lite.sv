`timescale 1ns/1ps

interface ifc_axi4_lite #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input clk,
    input rst_n
);

    // TODO: check if you want to make the master output signals clocking, so 
    // you don't always have to wait for the clock in the task

    localparam int STRB_WIDTH = DATA_WIDTH/8;

    // WRITE ADDRESS CHANNEL
    logic [ADDR_WIDTH-1:0]          awaddr;
    logic [2:0]                     awprot;    // access permissions
    logic                           awvalid;
    logic                           awready;

    // WRITE DATA CHANNEL
    logic [DATA_WIDTH-1:0]          wdata;
    logic [STRB_WIDTH-1:0]          wstrb;
    logic                           wvalid;
    logic                           wready;

    // WRITE RESPONSE CHANNEL
    logic [1:0]                     bresp;
    logic                           bvalid;
    logic                           bready;

    // READ ADDRESS CHANNEL
    logic [ADDR_WIDTH-1:0]          araddr;
    logic [2:0]                     arprot;    // access permissions
    logic                           arvalid;
    logic                           arready;

    // READ DATA CHANNEL
    logic [DATA_WIDTH-1:0]          rdata;
    logic [1:0]                     rresp;
    logic                           rvalid;
    logic                           rready;

    function hs_ar();
        return arready & arvalid;
    endfunction
    function hs_r();
        return rready & rvalid;
    endfunction
    function hs_aw();
        return awready & awvalid;
    endfunction
    function hs_w();
        return wready & wvalid;
    endfunction

    modport master (
        import hs_r, hs_ar, hs_w, hs_aw,
        // WRITE ADDRESS CHANNEL
        output awaddr, awprot,
        output awvalid,
        input awready,
        // WRITE DATA CHANNEL
        output wdata, wstrb, wvalid,
        input wready,
        // WRITE RESPONSE CHANNEL
        input bresp, bvalid,
        output bready,
        // READ ADDRESS CHANNEL
        output araddr, arprot,
        output arvalid,
        input arready,
        // READ DATA CHANNEL
        input rdata, rresp, rvalid,
        output rready
        );

    modport slave (
        import hs_r, hs_ar, hs_w, hs_aw,
        // WRITE ADDRESS CHANNEL
        input awaddr, awprot,
        input awvalid,
        output awready,
        // WRITE DATA CHANNEL
        input wdata, wstrb, wvalid,
        output wready,
        // WRITE RESPONSE CHANNEL
        output bresp, bvalid,
        input bready,
        // READ ADDRESS CHANNEL
        input araddr, arprot,
        input arvalid,
        output arready,
        // READ DATA CHANNEL
        output rdata, rresp, rvalid,
        input rready
        );

`ifndef VERILATOR
    // it might be that verilator has issues at dealing with assertions, so 
    // exclude them from verilator (TODO: check with the current verilator 
    // options set)
    assert_valid_bus_width: assert property (
            @(posedge clk) DATA_WIDTH inside {32, 64});
`endif
    
endinterface
