`timescale 1ns/1ps

interface ifc_data_stream_hs #(
    parameter int DATA_WIDTH = 32
) (
    input clk,
    input rst_n
);

    localparam int STRB_WIDTH = DATA_WIDTH/8;

    logic [DATA_WIDTH-1:0]          data;
    logic [STRB_WIDTH-1:0]          strb;
    logic                           ready;
    logic                           valid;

    // shortcut to avoid having to write `(if_<...>.ready & if_<...>.valid)`
    function hs();
        return ready & valid;
    endfunction

    modport master (
        input ready,
        output data, valid, strb
    );

    modport slave (
        output ready,
        input data, valid, strb
    );

    modport monitor (
        input data, ready, valid, strb
    );
    
endinterface
