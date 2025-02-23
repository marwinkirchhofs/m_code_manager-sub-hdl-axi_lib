
/*
* company:
* author/engineer:
* creation date:
* project name:
* target devices:
* tool versions:
*
* * DESCRIPTION:
* Buffered pipeline for ifc_data_stream_hs that implements the "buffered 
* handshake" example from
* https://zipcpu.com/blog/2017/08/14/strategies-for-pipelining.html
*
* pipeline latency is the STAGES parameter (so no additional in/out registers)
*
* * INTERFACE:
*		[port name]		- [port description]
* * inputs:
* * outputs:
*
*/

module data_stream_hs_buffered_pipeline #(
    parameter int               DATA_WIDTH = 32,
    parameter int               STAGES = 2
) (
    input                       clk,
    input                       rst_n,

    ifc_data_stream_hs.slave    if_data_in,
    ifc_data_stream_hs.master   if_data_out
);

    localparam int STRB_WIDTH = $ceil(DATA_WIDTH/8);
    genvar i;

    //----------------------------------------------------------
    // INTERNAL SIGNALS
    //----------------------------------------------------------

    ifc_data_stream_hs #(
        .DATA_WIDTH             (DATA_WIDTH)
    ) if_data_pl_stage [STAGES+1] (clk);

    // (index 0 is as dummy for consistent indexing, index STAGES is if_data_out)
    logic [DATA_WIDTH-1:0]              stage_buffer_data   [STAGES+1];
    logic [STRB_WIDTH-1:0]              stage_buffer_strb   [STAGES+1];
    logic                               stage_buffer_valid  [STAGES+1];


    //----------------------------------------------------------
    // OPERATION
    //----------------------------------------------------------

    assign if_data_pl_stage[STAGES].ready = if_data_out.ready;
    assign if_data_out.valid = if_data_pl_stage[STAGES].valid;
    assign if_data_out.data = if_data_pl_stage[STAGES].data;
    assign if_data_out.strb = if_data_pl_stage[STAGES].strb;

    assign if_data_pl_stage[0].data = if_data_in.data;
    assign if_data_pl_stage[0].strb = if_data_in.strb;
    assign if_data_pl_stage[0].valid = if_data_in.valid;
    assign if_data_in.ready = if_data_pl_stage[0].ready;

    assign stage_buffer_data[0] = '0;
    assign stage_buffer_strb[0] = '0;
    assign stage_buffer_valid[0] = 1'b0;

    generate
    begin: gen_pipeline_stages
        // (note how the "stage" is in-between of the interfaces, but the code 
        // is based on interfaces. that's why indexing is i for the (input-side) 
        // ready signal, and i+1 for the (output-side) valid/data signals)
        for (i=0; i<STAGES; i++) begin
            always_ff @(posedge clk) begin
                if (~rst_n) begin
                    if_data_pl_stage[i].ready <= 1'b0;
                    if_data_pl_stage[i+1].valid <= 1'b0;
                    stage_buffer_valid[i+1] <= 1'b0;
                end else begin
                    if_data_pl_stage[i].ready <= if_data_pl_stage[i+1].ready;

                    // have to figure out where to direct the incoming data to 
                    // (next stage data if either clean or getting advanced, 
                    // otherwise next stage buffer)
                    if (if_data_pl_stage[i+1].hs_ & if_data_pl_stage[i].hs_) begin
                        // case: both stage in and stage out handshake
                        if_data_pl_stage[i+1].valid <= 1'b1;
                        if (stage_buffer_valid[i+1]) begin
                            if_data_pl_stage[i+1].data <= stage_buffer_valid[i+1];
                            stage_buffer_data[i+1] <= if_data_pl_stage[i].data;
                            stage_buffer_strb[i+1] <= if_data_pl_stage[i].strb;
                            // (no need to assert stage_buffer_valid, it already 
                            // is)
                        end else begin
                            if_data_pl_stage[i+1].data <= if_data_pl_stage[i].data;
                            if_data_pl_stage[i+1].strb <= if_data_pl_stage[i].strb;
                        end

                    end else if (if_data_pl_stage[i+1].hs_) begin
                        // case: stage out handshake only

                        if_data_pl_stage[i+1].valid <= stage_buffer_valid[i+1];
                        stage_buffer_valid[i+1] <= 1'b0;
                        // slight logic simplification: instead of conditionally 
                        // advancing data, just take whatever is in the stage 
                        // buffer, alongside with the valid signal. If it's 
                        // invalid, doesn't matter what the data is or was.
                        if_data_pl_stage[i+1].data <= stage_buffer_data[i+1];
                        if_data_pl_stage[i+1].strb <= stage_buffer_strb[i+1];

                    end else if (if_data_pl_stage[i].hs_) begin
                        // case: stage in handshake only
                        if (~if_data_pl_stage[i+1].valid) begin
                            if_data_pl_stage[i+1].data <= if_data_pl_stage[i].data;
                            if_data_pl_stage[i+1].strb <= if_data_pl_stage[i].strb;
                            if_data_pl_stage[i+1].valid <= 1'b1;
                        end else begin
                            // if data can't go into next stage data right-away, 
                            // it needs to go into the stage buffer. note that 
                            // by design it's safe to write into the state 
                            // buffer, the stage in handshake can't occur if the 
                            // stage buffer is valid and not being advanced this 
                            // cycle.
                            stage_buffer_data[i+1] <= if_data_pl_stage[i].data;
                            stage_buffer_strb[i+1] <= if_data_pl_stage[i].strb;
                            stage_buffer_valid[i+1] <= 1'b1;
                        end
                    end

                end
            end
        end
    end
    endgenerate

    //----------------------------------------------------------
    // SUBMODULES
    //----------------------------------------------------------

endmodule

