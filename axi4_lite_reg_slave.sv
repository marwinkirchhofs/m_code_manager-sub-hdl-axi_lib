
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
*
* TODO: find a better structure for the parameterization headers, such that the 
* base address also gets set set there. And, for pure theory, think about how 
* a user could specify multiple register files through that package. It might be 
* an idea to just shift the entire axi parameterization to headers, include axi 
* bus address width. It would allow to again have any function in the package, 
    * instead of in the module.
*/

import axi_lib_pkg::*;
import reg_file_pkg::*;

module axi4_lite_reg_slave #(
    parameter                           ADDR_WIDTH              = 32,
    parameter                           AXI_DATA_WIDTH          = 32,
    parameter                           AXI_BASE_ADDR           = '0,
    parameter                           REGISTER_WIDTH          = 32,
    parameter                           NUM_REGISTERS           = 16,
    // delay reading from the register file for timing optimization. Is 
    // implemented as a parallel wait, not as a pipeline, such that the data 
    // path from register file to axi can be made multi-cycle if READ_LATENCY>1
    // (note that the core has a read latency of 2 anyways (register address, 
    // fetch data), the parameter just sets the additional latency)
    parameter                           ADD_READ_LATENCY        = 0,
    // same story like read, but for write
    parameter                           ADD_WRITE_LATENCY       = 0
) (
    input                                   clk,
    input                                   rst_n,

    ifc_axi4_lite.slave                     if_axi,
    ifc_reg_file_direct_access.master       if_reg_file,
    output logic    [NUM_REGISTERS-1:0]     o_write_trigger
);

    typedef logic [ADDR_WIDTH-1:0] axi_addr_t;
    /*
    * be aware: the function does synthesize, but as expected, it can introduce 
    * a considerable timing problem. You are comparing a 32-bit register against 
    * a good number of values using LUTs. Already for only 3 integers in the map 
    * table, that gives 3 hierarchy levels of LUTs for the CE port. Might get 
* worse with a larger number of choices. Good thing is there is no fanout...
    */
    function automatic reg_file_item_t get_reg_item_from_axi_addr(
        axi_addr_t axi_addr,
        axi_addr_t base_address = '0
    );
        reg_file_item_t          hit;
        hit.entry_found = 1'b0;

        for (int i=0; i<REG_FILE_NUM_REGISTERS; i++) begin
            if (axi_addr_t'(AXI_LITE_REG_MAP_TABLE[i].addr) == (axi_addr - base_address)) begin
                hit.entry_found = 1'b1;
                hit.id = reg_file_id_t'(i);
                hit.entry = AXI_LITE_REG_MAP_TABLE[i];
            end
        end

        return hit;
    endfunction

    //----------------------------------------------------------
    // INTERNAL SIGNALS
    //----------------------------------------------------------

    // AXI READ
    reg_file_item_t                         reg_file_item_read;

    st_axi_lite_read_addr_t                 st_read_addr;
    st_axi_lite_read_addr_t                 st_read_addr_next;

    logic   [ADDR_WIDTH-1:0]                reg_read_addr;
    logic                                   fetch_read_data;
    logic   [$clog2(ADD_READ_LATENCY+1)-1:0]    count_wait_fetch_read_data;

    // AXI WRITE
    reg_file_item_t                         reg_file_item_write;

    st_axi_lite_write_addr_t                st_write_addr;
    st_axi_lite_write_addr_t                st_write_addr_next;

    logic   [$clog2(ADD_WRITE_LATENCY+1)-1:0]   count_resolve_write_addr;

    // REGISTER FILE WRITE ACCESS
    // access to the register file write needs to be multiplexed, because the 
    // read channel can write-access it as well - namely when a register is set 
    // to be clear-on-write
    logic                                   reg_clear_req;
    reg_file_id_t                           reg_clear_id;
    logic                                   reg_write_req;
    reg_file_id_t                           reg_write_id;
    logic   [ADDR_WIDTH-1:0]                reg_write_addr;
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

    assign reg_file_item_read = get_reg_item_from_axi_addr(reg_read_addr, AXI_BASE_ADDR);
    
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
//                 if (if_axi.arready & if_axi.arvalid) begin
                if (if_axi.hs_ar()) begin
                    st_read_addr_next = ST_AXI_LITE_READ_FETCH;
                end else begin
                    st_read_addr_next = ST_AXI_LITE_READ_READY;
                end
            end
            ST_AXI_LITE_READ_FETCH: begin
                // one intermediate cycle to fetch read data from the register 
                // file (otherwise you have a full path from the read address to 
                // the register file, on which you also need to resolve the 
                // address into the correct register ID. Goodbye clock frequency)
                if (count_wait_fetch_read_data == '0) begin
                    st_read_addr_next = ST_AXI_LITE_READ_VALID;
                end else begin
                    st_read_addr_next = st_read_addr;
                end
            end
            ST_AXI_LITE_READ_VALID: begin
//                 if (if_axi.rvalid & if_axi.rready) begin
                if (if_axi.hs_r()) begin
                    st_read_addr_next = ST_AXI_LITE_READ_READY;
                end else begin
                    st_read_addr_next = ST_AXI_LITE_READ_VALID;
                end
            end
            default: begin
                st_read_addr_next = ST_AXI_LITE_READ_READY;
            end
        endcase
    end

    // READ FETCH
    generate begin: gen_read_fetch_count
        if (ADD_READ_LATENCY>0) begin
            always_ff @(posedge clk) begin
                if (fetch_read_data) begin
                    count_wait_fetch_read_data <= ADD_READ_LATENCY;
                end else begin
                    count_wait_fetch_read_data <= count_wait_fetch_read_data - 1;
                end
            end
        end else begin
            assign count_wait_fetch_read_data = '0;
        end
    end endgenerate

    // READ OPERATION

    // register address
    always_ff @(posedge clk)
    begin: proc_register_read_address
        fetch_read_data <= 1'b0;
        if (if_axi.hs_ar()) begin
            reg_read_addr       <= if_axi.araddr;

            if (st_read_addr == ST_AXI_LITE_READ_READY) begin
                fetch_read_data <= 1'b1;
            end
        end
    end

    // fetch read data
    always_ff @(posedge clk)
    begin: proc_read_operation
        if (~rst_n) begin
            // note: some signals here would not need a reset. The resets are 
            // added to allow consistency in control sets help with placement.
            reg_clear_req                   <= 1'b0;
            reg_clear_id                    <= '0;
            // (reset wouldn't be necessary for the axi read data field, but it 
            // turned out to help with timing in experiments)
            if_axi.rdata                    <= '0;
            // signalize an error on the slave when not in a transaction 
            // completion cycle
            if_axi.rresp                    <= AXI4_RESP_SLVERR;
        end else begin

            reg_clear_req                   <= 1'b0;
            reg_clear_id                    <= '0;
            // attempt to keep those out of the CE path
            if_axi.rdata                    <= if_axi.rdata;
            if_axi.rresp                    <= if_axi.rresp;

//             if (if_axi.arready & if_axi.arvalid) begin
            if (fetch_read_data) begin

                // check for a valid address
                if (reg_file_item_read.entry_found) begin
                    // TODO: mask data

                    // fetch data from the register file
                    if_axi.rresp        <= AXI4_RESP_OKAY;
                    if (reg_file_item_read.entry.clear_on_read) begin
                        reg_clear_req       <= 1'b1;
                        reg_clear_id        <= reg_file_item_read.id;
                    end
                end
                // read data can be taken out of the address validity checking 
                // path, because the axi data field doesn't matter if the slave 
                // responds with an error
                if_axi.rdata        <= if_reg_file.read_data[reg_file_item_read.id];
            end else if (if_axi.rvalid & if_axi.rready) begin
                if_axi.rresp        <= AXI4_RESP_SLVERR;
            end

        end
    end

    //----------------------------
    // WRITE
    //----------------------------

//     assign reg_file_item_write = get_reg_item_from_axi_addr(if_axi.awaddr, AXI_BASE_ADDR);
    assign reg_file_item_write = get_reg_item_from_axi_addr(reg_write_addr, AXI_BASE_ADDR);

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
        st_write_addr_next = st_write_addr;
        case (st_write_addr)
            ST_AXI_LITE_WRITE_READY: begin
                if (if_axi.awready & if_axi.awvalid) begin
                    if (ADD_WRITE_LATENCY > 0) begin
                        // remember: you don't have to go through the extra 
                        // state, if you don't require additional write latency
                        st_write_addr_next = ST_AXI_LITE_WRITE_RESOLVE;
                    end else begin
                        st_write_addr_next = ST_AXI_LITE_WRITE_VALID;
                    end
                end
            end
            ST_AXI_LITE_WRITE_RESOLVE: begin
                if (count_resolve_write_addr == '0) begin
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
            default: begin
                st_write_addr_next = ST_AXI_LITE_WRITE_READY;
            end
        endcase
    end

    // WRITE RESOLVE
    generate begin: gen_write_resolve_count
        if (ADD_WRITE_LATENCY>0) begin
            always_ff @(posedge clk) begin
                if (if_axi.hs_aw()) begin
                    count_resolve_write_addr <= ADD_WRITE_LATENCY;
                end else begin
                    count_resolve_write_addr <= count_resolve_write_addr - 1;
                end
            end
        end else begin
            assign count_resolve_write_addr = '0;
        end
    end endgenerate

    // WRITE OPERATION

    // register address
    always_ff @(posedge clk)
    begin: proc_register_write_address
        if (if_axi.awready & if_axi.awvalid) begin
            reg_write_addr      <= if_axi.awaddr;
        end
    end

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

//             if (if_axi.awready & if_axi.awvalid) begin
            if (if_axi.wready & if_axi.wvalid) begin
                // check for a valid address
                if (reg_file_item_write.entry_found) begin
                    // TODO: apply wstrb

                    // TODO: mask data
                    if (reg_file_item_write.entry.memory_mapped) begin
                        reg_write_id        <= reg_file_item_write.id;
                        reg_write_req       <= 1'b1;
                    end
                    if (reg_file_item_write.entry.trigger_on_write) begin
                        o_write_trigger[reg_file_item_write.id] <= 1'b1;
                    end
                end
                reg_write_data      <= if_axi.wdata;
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

