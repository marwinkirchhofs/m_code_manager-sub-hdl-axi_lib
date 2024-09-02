
/*
* company:
* author/engineer:
* creation date:
* project name:
* target devices:
* tool versions:
*
* * DESCRIPTION:
*
*
* * INTERFACE:
*		[port name]		- [port description]
* * inputs:
* * outputs:
*
* TODO: currently, reading from the register file still takes up one cycle.  
* I think I would keep it like that, because it's axi lite anyway, so it's slow 
* by nature, and the additional register can help with timing.
* TODO: on that previous note, it might even be smart to introduce a latency 
* cycle from address handshake to the register file access. Bus is notorious to 
* cause timing issues, and nobody cares about that cycle after all.
*
* TODO: when writing to a non-mapped register, maybe the core should respond 
* with a slave error, instead of an okay. But if you get started on that, think 
* about if also in some way you want to define other "illegal" writes, which 
* should result in a slave error. Anyways, if you follow your own register 
* mapping table, it isn't a problem.
*/

import axi_lib_pkg::*;
import reg_file_pkg::*;

module axi4_lite_reg_slave #(
    parameter                           ADDR_WIDTH              = 32,
    parameter                           AXI_DATA_WIDTH          = 32,
    parameter                           REGISTER_WIDTH          = 32,
    parameter                           NUM_REGISTERS           = 16,
    parameter                           SAME_CYCLE_ADDR_DATA    = 1
) (
    input                                   clk,
    input                                   rst_n,

    ifc_axi4_lite.slave                     if_axi,
    ifc_reg_file_direct_access.master       if_reg_file,
    output logic    [NUM_REGISTERS-1:0]     o_write_trigger
);

    //----------------------------------------------------------
    // INTERNAL SIGNALS
    //----------------------------------------------------------

    // AXI READ
    reg_file_item_t                         reg_file_item_read;

    st_axi_lite_read_addr_t                 st_read_addr;
    st_axi_lite_read_addr_t                 st_read_addr_next;

    // AXI WRITE
    reg_file_item_t                         reg_file_item_write;

    st_axi_lite_write_addr_t                st_write_addr;
    st_axi_lite_write_addr_t                st_write_addr_next;

    // REGISTER FILE WRITE ACCESS
    // access to the register file write needs to be multiplexed, because the 
    // read channel can write-access it as well - namely when a register is set 
    // to be clear-on-write
    logic                                   reg_clear_req;
    reg_id_t                                reg_clear_id;
    logic                                   reg_write_req;
    reg_id_t                                reg_write_id;
    logic   [AXI_DATA_WIDTH-1:0]            reg_write_data;

    //----------------------------------------------------------
    // OPERATION
    //----------------------------------------------------------
    // coding style for the respective operation parts:
    // 1. comb/seq state machine for the ready/valid handshake state
    // 2. assignments based on current state
    // 3. sequential code based on current state and other signals

    //----------------------------
    // READ
    //----------------------------

    assign reg_file_item_read = get_reg_item_from_addr(if_axi.araddr);
    
    // READ HANDSHAKES
    assign if_axi.arready   =   st_read_addr == ST_AXI_LITE_READ_READY;
    assign if_axi.rvalid    =   st_read_addr == ST_AXI_LITE_READ_VALID;

    always_ff @(posedge clk)
    begin: fsm_read_addr_next
        if (~rst_n) begin
            st_read_addr <= ST_AXI_LITE_READ_READY;
        end else begin
            st_read_addr <= st_read_addr_next;
        end
    end

    always_comb
    begin: fsm_read_addr
        case (st_read_addr)
            ST_AXI_LITE_READ_READY: begin
                if (if_axi.arready & if_axi.arvalid) begin
                    st_read_addr_next = ST_AXI_LITE_READ_VALID;
                end
            end
            ST_AXI_LITE_READ_VALID: begin
                if (if_axi.rvalid & if_axi.rready) begin
                    st_read_addr_next = ST_AXI_LITE_READ_READY;
                end
            end
        endcase
    end

    // READ OPERATION

    // fetch read data
    always_ff @(posedge clk)
    begin: proc_read_operation
        if (~rst_n) begin
            // note: some signals here would not need a reset. The resets are 
            // added to allow consistency in control sets help with placement.
            reg_clear_req                   <= 1'b0;
            reg_clear_id                    <= '0;
            if_axi.rdata                    <= '0;
            // signalize an error on the slave when not in a transaction 
            // completion cycle
            if_axi.rresp                    <= AXI4_RESP_SLVERR;
        end else begin

            reg_clear_req                   <= 1'b0;
            reg_clear_id                    <= '0;
            if_axi.rdata                    <= '0;
            if_axi.rresp                    <= AXI4_RESP_SLVERR;

            if (if_axi.arready & if_axi.arvalid) begin
                // check for a valid address
                if (reg_file_item_read.entry_found) begin
                    // TODO: mask data

                    // fetch data from the register file
                    if_axi.rdata        <= if_reg_file.read_data[reg_file_item_read.id];
                    if_axi.rresp        <= AXI4_RESP_OKAY;
                    if (reg_file_item_read.entry.clear_on_read) begin
                        reg_clear_req       <= 1'b1;
                        reg_clear_id        <= reg_file_item_read.id;
                    end
                end
            end
        end
    end

    //----------------------------
    // WRITE
    //----------------------------

    assign reg_file_item_write = get_reg_item_from_addr(if_axi.awaddr);

    assign if_axi.awready   =   st_write_addr == ST_AXI_LITE_WRITE_READY;
    assign if_axi.wready    =   st_write_addr == ST_AXI_LITE_WRITE_VALID;
    assign if_axi.bvalid    =   st_write_addr == ST_AXI_LITE_WRITE_RESP;

    always_ff @(posedge clk)
    begin: fsm_write_addr_next
        if (~rst_n) begin
            st_write_addr <= ST_AXI_LITE_WRITE_READY;
        end else begin
            st_write_addr <= st_write_addr_next;
        end
    end

    /*
    * in theory, the protocol does allow to do the data handshake before the 
    * address handshake. However, that is up to the slave, and the slave is 
* perfectly allowed to wait for the address handshake before asserting wready.  
    * Since that makes implementation simple, and it's just a control interface, 
    * I'll do so here.
    */
    always_comb
    begin: fsm_write_addr
        case (st_write_addr)
            ST_AXI_LITE_WRITE_READY: begin
                if (if_axi.awready & if_axi.awvalid) begin
                    st_write_addr_next = ST_AXI_LITE_WRITE_VALID;
                end
            end
            ST_AXI_LITE_WRITE_VALID: begin
                if (if_axi.wready & if_axi.wvalid) begin
                    st_write_addr_next = ST_AXI_LITE_WRITE_RESP;
                end
            end
            ST_AXI_LITE_WRITE_RESP: begin
                if (if_axi.bvalid & if_axi.bready) begin
                    st_write_addr_next = ST_AXI_LITE_WRITE_READY;
                end
            end
        endcase
    end

    // WRITE OPERATION

    always_ff @(posedge clk)
    begin: proc_write_operation
        if (~rst_n) begin
            // note: some signals here would not need a reset. The resets are 
            // added to allow consistency in control sets help with placement.
            reg_write_data                  <= '0;
            reg_write_id                    <= '0;
            reg_write_req                   <= 1'b0;
            o_write_trigger                 <= '0;
        end else begin

            reg_write_data                  <= '0;
            reg_write_id                    <= '0;
            reg_write_req                   <= 1'b0;
            o_write_trigger                 <= '0;

            if (if_axi.awready & if_axi.awvalid) begin
                // check for a valid address
                if (reg_file_item_write.entry_found) begin
                    // TODO: apply wstrb

                    // TODO: mask data
                    if (reg_file_item_write.entry.memory_mapped) begin
                        reg_write_data      <= if_axi.wdata;
                        reg_write_id        <= reg_file_item_write.id;
                        reg_write_req       <= 1'b1;
                    end
                    if (reg_file_item_write.entry.trigger_on_write) begin
                        o_write_trigger[reg_file_item_write.id] <= 1'b1;
                    end

                end
            end
        end
    end

    // WRITE ANSWER
    always_comb
    begin: proc_write_answer
        case (st_write_addr)
            ST_AXI_LITE_WRITE_RESP: begin
                if_axi.bresp = AXI4_RESP_OKAY;
            end
            default: begin
                if_axi.bresp = AXI4_RESP_SLVERR;
            end
        endcase
    end

    //----------------------------
    // REGISTER FILE CONNECTION
    //----------------------------

    genvar i;

    generate
    for (i=0; i<NUM_REGISTERS; i++)
    begin: gen_proc_reg_file_access
        always_ff @(posedge clk)
        begin: proc_reg_file_access
            if (~rst_n) begin
                if_reg_file.write_req[i]    <= 1'b0;
                if_reg_file.write_data[i]   <= '0;
            end else begin
                if_reg_file.write_req[i]    <= 1'b0;
                if_reg_file.write_data[i]   <= '0;
                if (reg_write_req && reg_write_id == i) begin
                    if_reg_file.write_req[i]        <= 1'b1;
                    if_reg_file.write_data[i]       <= reg_write_data;
                end else if (reg_clear_req && reg_clear_id == i) begin
                    if_reg_file.write_req[i]        <= 1'b1;
                    if_reg_file.write_data[i]       <= '0;
                end
            end
        end
    end
    endgenerate

endmodule

