`timescale 1ns/1ps

import axi_lib_pkg::axi4_status_fields_t;
import axi_lib_pkg::axi4_master_msgs_t;

interface ifc_axi4_master #(
    parameter               AXI_ADDR_WIDTH = 32,
    parameter               AXI_USER_WIDTH = 0,
    parameter               AXI_ID_WIDTH = 0,
    parameter               USER_DATA_WIDTH = 32,
    parameter               MAX_TOTAL_TRANSACTION_LENGTH    = 128,
    parameter real          T_SETUP = 1,
    parameter real          T_CTOQ = 2
) (
    input clk
);

    localparam STRB_WIDTH = USER_DATA_WIDTH/8;

    logic ready;
    logic trigger;
    logic [$clog2(MAX_TOTAL_TRANSACTION_LENGTH)-1:0] num_data_words;
    logic direction;
    logic [AXI_ADDR_WIDTH-1:0] base_address;
    logic [AXI_USER_WIDTH-1:0] axi_user;
    logic [AXI_ID_WIDTH-1:0] axi_id;
    logic clear_messages;
    axi4_status_fields_t axi_status_fields;
    axi4_master_msgs_t axi_master_msgs;

    // splitting up the data stream interface in single signals for easier 
    // handling - user has to manually connect these to the actual dut's 
    // ifc_data_stream_hs interfaces
    logic [USER_DATA_WIDTH-1:0]     write_data;
    logic [STRB_WIDTH-1:0]          write_strb;
    logic                           write_valid;
    logic                           write_ready;
    logic [USER_DATA_WIDTH-1:0]     read_data;
    logic [STRB_WIDTH-1:0]          read_strb;
    logic                           read_valid;
    logic                           read_ready;

    clocking cb @(posedge clk);
        default input #T_SETUP output #T_CTOQ;
        output trigger, num_data_words, direction, base_address, axi_user, axi_id, clear_messages;
        input ready;
        output write_data, write_strb, write_valid;
        input write_ready;
        output read_ready;
        input read_data, read_strb, read_valid;
        output axi_status_fields;
        input axi_master_msgs;
    endclocking

    modport testbench (
        clocking cb,
        output trigger, num_data_words, direction, base_address, axi_user, axi_id, clear_messages,
        input ready,
        output write_data, write_strb, write_valid,
        input write_ready,
        output read_ready,
        input read_data, read_strb, read_valid,
        output axi_status_fields,
        input axi_master_msgs
    );

endinterface
