`timescale 1ns/1ps

interface ifc_data_stream_hs #(
    parameter int               DATA_WIDTH = 32,
    parameter real              T_SETUP = 0.9,
    parameter real              T_CTOQ = 0.3
) (
    input clk,
    input rst_n
);

    localparam int STRB_WIDTH = $ceil(DATA_WIDTH/8);

    logic [DATA_WIDTH-1:0]          data;
    logic [STRB_WIDTH-1:0]          strb;
    logic                           ready;
    logic                           valid;

    // shortcut to avoid having to write `(if_<...>.ready & if_<...>.valid)`
    function automatic hs();
        return ready & valid;
    endfunction

    // (named hs_ to not interfere with existing usage of hs() )
    logic hs_;
    assign hs_ = ready & valid;

    // TODO: I might need a way to put the clocking block back in, but still use 
    // the interface in a testbench with assignments (instead of accessing via 
    // the modport in a test agent). Currently that is causig a 'written by both 
    // continuous and procedural assignment' error.
//     clocking cb @(posedge clk);
//         default input #T_SETUP output #T_CTOQ;
//         input ready;
//         output data, valid, strb;
//     endclocking;

    modport master (
//         clocking cb,
        input ready,
        output data, valid, strb,
        import hs, hs_
    );

    modport slave (
        output ready,
        input data, valid, strb,
        import hs, hs_
    );

endinterface
