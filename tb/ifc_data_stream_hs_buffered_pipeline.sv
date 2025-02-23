`timescale 1ns/1ps

interface ifc_data_stream_hs_buffered_pipeline #(
    parameter int               DATA_WIDTH = 32
) (
    input clk
);

    localparam int STRB_WIDTH = $ceil(DATA_WIDTH/8);

    logic [DATA_WIDTH-1:0]          dut_in_data;
    logic [STRB_WIDTH-1:0]          dut_in_strb;
    logic                           dut_in_ready;
    logic                           dut_in_valid;
    logic [DATA_WIDTH-1:0]          dut_out_data;
    logic [STRB_WIDTH-1:0]          dut_out_strb;
    logic                           dut_out_ready;
    logic                           dut_out_valid;

    clocking cb @(posedge clk);
        default input #0.7 output #0.3;
        inout dut_in_data, dut_in_strb, dut_in_valid;
        inout dut_out_ready;
        input dut_out_data, dut_out_strb, dut_out_valid;
        input dut_in_ready;
    endclocking

endinterface
