`timescale 1ns/1ps

/*
* testbench depends on the util_pkg from
* https://github.com/marwinkirchhofs/m_code_manager-sub-hdl-sim_util_pkg
*
* !!! pay attention: due to the buffered register signal, a ready signal at the 
* pipeline output will appear at the pipeline input PIPELINE_STAGES amount of 
* cycles later. That can become problematic for transactions of a certain length, 
* if anything on the pipeline input reacts to the data stream ready signal after 
* the last data handshake (from that side's perspective). If you need to know 
* for sure that the pipeline is flushed, and that a new ready signal actually 
* means that the receiver on the other side of the pipeline is available AGAIN 
* for the next transaction: You need to wait for 2*PIPELINE_STAGES more cycles 
* of ready being asserted at the pipeline input, after the last pipeline input 
* data handshake (1 time for data traveling the pipeline, 1 time for ready 
* coming back).
*/

import data_stream_hs_buffered_pipeline_sim_pkg::*;
import util_pkg::*;

module tb_data_stream_hs_buffered_pipeline;

localparam                      DATA_WIDTH = 32;
localparam                      PIPELINE_STAGES = 3;

localparam                      TIMEOUT = 1000;

localparam                      CLK_PERIOD = 10;
localparam                      RST_CYCLES = 6;
localparam                      RST_ACTIVE = RST_ACTIVE_LOW;

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

cls_agent_data_stream_hs_buffered_pipeline #(DATA_WIDTH) agent_dut;
ifc_data_stream_hs_buffered_pipeline #(DATA_WIDTH) if_dut (clk);

ifc_data_stream_hs #(DATA_WIDTH) if_data_dut_in (clk);
ifc_data_stream_hs #(DATA_WIDTH) if_data_dut_out (clk);
assign if_dut.dut_in_ready = if_data_dut_in.ready;
assign if_data_dut_in.valid = if_dut.dut_in_valid;
assign if_data_dut_in.data = if_dut.dut_in_data;
assign if_data_dut_in.strb = if_dut.dut_in_strb;
assign if_data_dut_out.ready = if_dut.dut_out_ready;
assign if_dut.dut_out_valid = if_data_dut_out.valid;
assign if_dut.dut_out_data = if_data_dut_out.data;
assign if_dut.dut_out_strb = if_data_dut_out.strb;

// DUT

data_stream_hs_buffered_pipeline #(
    .DATA_WIDTH                 (DATA_WIDTH),
    .STAGES                     (PIPELINE_STAGES)
) inst_dut (
    .clk                        (clk),
    .rst_n                      (if_rst.rst),
    .if_data_in                 (if_data_dut_in),
    .if_data_out                (if_data_dut_out)
);


//----------------------------
// OPERATION
//----------------------------

initial begin
    $timeformat(-9, 1, "ns", 3);

    rst_ctrl = new(if_rst);
    agent_dut = new(if_dut);

    rst_ctrl.init();
    rst_ctrl.trigger(RST_CYCLES);

    fork begin
        fork
        begin
            agent_dut.init();
            agent_dut.run();
        end
        begin
            #TIMEOUT;
            $error("Timeout reached!");
        end
        join_any
        disable fork;
    end join
    
    $stop;
end

endmodule
