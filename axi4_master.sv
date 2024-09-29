
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
* The core does not allow for simultaneous reading and writing. It is either one 
* or the other.
*
* The core does populate status information about the transaction in o_msgs. It 
* might be necessary to monitor those from the parent module side. As a rule 
* (hopefully), everything that causes a transaction to not be properly executed 
* (abort or whatever) has its according flag.
*
* !!!(in this first iteration,) it is possible for the core to stall with 
* a faulty or non-supported input! For example, wrap bursts are not implemented, 
* or if an incr burst is issued with i_num_data_words=0 (which makes no sense), 
* that can break things as well!!! TODO: of course fix that; it might be an idea 
* to add msgs flags for that -> require the parent to monitor the flags after 
* issuing anything.
*
* handshake latency data stream: As far as I see it, even with 
* REGISTER_DATA_STREAM=1, the ready signal of the first stage (if_axi.rready and 
* if_data_stream_write.ready) combinatorially depends on the ready and valid 
* signals of the second stage (if you don't want to potentially needlessly stall 
* the bus). If logic path depth becomes a problem on these ones, you need to 
* implement some solution for the respective data stream interface signals to be 
* registered at the interface. Some sort of lookahead or buffer at whatever your 
* data source/sink is, for example.
* 
* For INCR burst type transactions, the core just uses the maximum burst length 
* (256) as long as possible. Thus a package of i_num_data_words=260 items would 
* be transmitted as one burst of length 256, and the second burst of length 4.
*
* actually, in the long run the burst type could be a parameter. Or even two 
* parameters, one that tells whether it's a parameter or a port, the other one 
* to set it. Because in a lot of situations the master will connect to slave 
* that you'd always approach with the same type of burst, and then again you 
* just ease the implementation and make it potentially faster.
*
* strb: the core currently does not apply strb when reading (it is still 
* forwarded via the ifc_data_stream_hs interface of course).  I'm not sure if 
* it's better to add that as a parameter, or as a port.  Maybe time will tell, 
* and then I'll do that.
*
* !!!Data handshaking protocol: Since the data handshaking is exposed to the 
* data stream interface, that interface also needs to obey the axi handshaking 
* signal dependencies!!! TODO: An option could be to implement a sort of 
* heralding protocol checker (and maybe make that parameterizable), which 
* prevents the parent core from deadlocking the interface. Or I add that as an 
* option to an encapsulating core, not sure yet which is better.
* Edit: To be honest, there is not too much left to obey, as far as I see it.  
* Don't wait for a ready to assert the valid, that should do it at first glance,
* you can expect that from someone who uses this core.
* 
* write response: the write response (bresp) of the last write burst is 
* registered in o_msgs, should the parent want to look at that. The core aborts 
* at a non-okay response.
* 
* bresp: currently, the core is designed to always take at least one cycle for 
* the write response. I don't know for sure if that is required by the protocol, 
* I'll test that. However, it does help with timing closure...
*
* For incr bursts, non-aligned base addresses (with respect to AXI_DATA_WIDTH 
* and burst size) will most likely lead to faulty behavior.
*
* The long To-Do list:
* - handle (incoming) axi status signals:
*     - rid
*     - ruser
*     - rresp
*/

import axi_lib_pkg::*;

module axi4_master #(
    parameter                           AXI_ADDR_WIDTH                  = 32,
    parameter                           AXI_DATA_WIDTH                  = 32,
    parameter                           AXI_USER_WIDTH                  = 0,
    parameter                           AXI_ID_WIDTH                    = 0,
    parameter                           USER_DATA_WIDTH                 = 32,
    // maximum number of data words in one user transaction - meaning one time 
    // asserting trigger (both for read and write)
    parameter                           MAX_TOTAL_TRANSACTION_LENGTH    = 128,
    parameter                           REGISTER_DATA_STREAM            = 0
) (
    input                                   clk,
    input                                   rst_n,

    // OPERATION CONTROL
    output logic                            o_ready,
    input                                   i_trigger,
    input                                   i_direction,
    input logic [$clog2(MAX_TOTAL_TRANSACTION_LENGTH)-1:0]      i_num_data_words,

    // USER DATA CONNECTION
    ifc_data_stream_hs.slave                if_data_stream_write,
    ifc_data_stream_hs.master               if_data_stream_read,

    // AXI RELATED PORTS
    ifc_axi4.master                         if_axi,
    input axi4_status_fields_t              i_axi_status_fields,
    input   [AXI_ADDR_WIDTH-1:0]            i_base_address,

    // PARAMETERIZABLE AXI RELATED PORTS
    // that's a reserved signal of user-specifiable width, so it can't go in the 
    // axi status fields struct.
    input   [AXI_USER_WIDTH-1:0]            i_axi_user,
    // also has parameterizable width -> if you don't need the signal, just tie 
    // it to 0 (1 might work as well, tying to 1 is cheaper in hardware, but in 
    // a very unfortunate case could confuse an axi slave)
    input   [AXI_ID_WIDTH-1:0]              i_axi_id,

    output axi4_master_msgs_t               o_msgs,
    input logic                             i_clear_messages
);

    //----------------------------------------------------------
    // PARAMETER CHECKS
    //----------------------------------------------------------

    generate begin: gen_parameter_checks
        // USER_DATA_WIDTH < AXI_DATA_WIDTH
        // because otherwise you can't assign burst items to the axi data bus 
        // without splitting them up, but the user can take over the splitting 
        // up part, the axi bus is wide enough
        if (USER_DATA_WIDTH > AXI_DATA_WIDTH) begin: gen_check_user_data_width
            $error($sformatf(
                "USER_DATA_WIDTH (%0d) can not be larger than AXI_DATA_WIDTH (%0d)",
                USER_DATA_WIDTH, AXI_DATA_WIDTH));
        end

        // MAX_TOTAL_TRANSACTION_LENGTH >= 2
        // because 1. this is a burst-only parameter, so 1 doesn't make sense 
        // since you could just go FIXED, 2. it causes problems in the code with 
        // slicing if $clog2(MAX_TOTAL_TRANSACTION_LENGTH)<1, and this 
        // requirement prevents that without actually restricting anything
        if (MAX_TOTAL_TRANSACTION_LENGTH < 2) begin: gen_check_small_transaction_length
            $error($sformatf(
                "MAX_TOTAL_TRANSACTION_LENGTH (%0d) must be >= 2",
                MAX_TOTAL_TRANSACTION_LENGTH));
        end
        
        if (~(AXI_DATA_WIDTH inside {8, 16, 32, 64, 128, 256, 512, 1024}))
        begin: gen_check_axi_data_width_range
            $error($sformatf("Invalid (non-power of 2) AXI_DATA_WIDTH (%0d)", AXI_DATA_WIDTH));
        end
        if (~(USER_DATA_WIDTH inside {8, 16, 32, 64, 128, 256, 512, 1024}))
        begin: gen_check_user_data_width_range
            $error($sformatf("Invalid (non-power of 2) USER_DATA_WIDTH (%0d)", USER_DATA_WIDTH));
        end
    end
    endgenerate


    //----------------------------------------------------------
    // HELPERS
    //----------------------------------------------------------

    function automatic logic [AXI_ADDR_WIDTH-1:0] fun_burst_incr_axi_address (
        logic [AXI_ADDR_WIDTH-1:0] address, logic [2:0] burst_size);
        // note: technically you don't need the clog2 part, because 
        // AXI4_MAX_BURST_LEN is a power of 2. It's just implemented this way 
        // such that really no tool gets to the idea of inferring a DSP or mult 
        // circuit, while it's guaranteed to be a bit shift.
        return address + ((32'b1<<burst_size) << $clog2(AXI4_MAX_BURST_LEN));
    endfunction

    //----------------------------------------------------------
    // INTERNAL SIGNALS
    //----------------------------------------------------------

    localparam MAX_NUM_BURSTS = int'($ceil(MAX_TOTAL_TRANSACTION_LENGTH/AXI4_MAX_BURST_LEN));
    localparam AXI_DATA_BYTES = AXI_DATA_WIDTH/8;
    // length of last burst needs to have conditional width for slicing: 
    // According to axi specs, max width is 8 bits. But for the actual value, we 
    // mask the LSBs of i_num_data_words. Highly likely that some tool at some 
    // point righteously complains if the slicing is wider than the actual 
    // signal.
    localparam WIDTH_LEN_LAST_BURST =
        MAX_TOTAL_TRANSACTION_LENGTH >= AXI4_MAX_BURST_LEN ?
        8 : $clog2(MAX_TOTAL_TRANSACTION_LENGTH);

    st_axi4_master_t                        st_axi_master;
    st_axi4_master_t                        st_axi_master_next;
    st_axi4_master_addr_t                   st_axi_master_addr;
    st_axi4_master_data_t                   st_axi_master_data;

    // register parameters at transaction start
    axi4_status_fields_t                    reg_axi_status_fields;
    logic [AXI_USER_WIDTH-1:0]              reg_axi_user;
    logic [AXI_ID_WIDTH-1:0]                reg_axi_id;
    logic                                   reg_direction;
    logic [AXI_ADDR_WIDTH-1:0]              axi_address;

    // AXI HANDSHAKE MULTIPLEX
    // since the core does either read or write, you can multiplex the address 
    // channel.
    logic                                   axi_addr_ready;
    logic                                   axi_addr_valid;

    // TRANSACTION ADDR/BURST MANAGEMENT
    logic [$clog2(MAX_TOTAL_TRANSACTION_LENGTH)-1:0]    count_data_words;
    logic [$clog2(MAX_NUM_BURSTS)-1:0]      count_bursts;
    // why [7:0]? because at maximum this can be AXI4_MAX_BURST_LEN-1, which 
    // takes up exactly that
    logic [WIDTH_LEN_LAST_BURST-1:0]        len_last_burst;
    logic [$clog2(AXI_DATA_BYTES)-1:0]      burst_item_start_lane;
    logic [7:0]                             burst_len;

    // TRANSACTION DATA MANAGEMENT
    logic [$clog2(AXI4_MAX_BURST_LEN)-1:0]  count_burst_items;

    // INTERNAL OPERATION

    // pure helper signals to save typing
    logic                                   core_triggered;
    logic                                   data_busy;
    logic                                   core_busy;
    logic                                   axi_data_handshake;
    logic                                   in_data_handshake;
    logic [$clog2(AXI_DATA_WIDTH)-1:0]      burst_item_start_bit;

    // struct to signalize setting sticky messages, such that the requesting 
    // state machine can both issue the flag and adjust operation, buth that 
    // another state machine can handle set and reset for the flags
    axi4_master_msgs_t                      set_msgs;

    //----------------------------------------------------------
    // OPERATION
    //----------------------------------------------------------
    // coding style for the respective operation parts:
    // 1. comb/seq state machine for the ready/valid handshake state
    // 2. assignments based on current state
    // 3. sequential code based on current state and other signals

    assign core_triggered   =   st_axi_master == ST_AXI_MASTER_IDLE && i_trigger;
    assign core_busy        =   st_axi_master != ST_AXI_MASTER_IDLE;
    assign o_ready          =   st_axi_master == ST_AXI_MASTER_IDLE;

    always_ff @(posedge clk) begin: fsm_status_next
        if (~rst_n) begin
            st_axi_master <= ST_AXI_MASTER_IDLE;
        end else begin
            st_axi_master <= st_axi_master_next;
        end
    end

    always_comb begin: fsm_status
        case (st_axi_master)
            ST_AXI_MASTER_IDLE: begin
                st_axi_master_next = i_trigger ? ST_AXI_MASTER_BUSY : ST_AXI_MASTER_IDLE;
            end
            ST_AXI_MASTER_BUSY: begin
                // should be impossible here to immediately jump back to IDLE, 
                // because the data and addr FSMs by assignment trigger in the 
                // same cycle as this FSM
                if (st_axi_master_addr == ST_AXI_MASTER_ADDR_IDLE &&
                    st_axi_master_data == ST_AXI_MASTER_DATA_IDLE) begin
                    st_axi_master_next = ST_AXI_MASTER_IDLE;
                end else begin
                    st_axi_master_next = ST_AXI_MASTER_BUSY;
                end
            end
            default: begin
                st_axi_master_next = ST_AXI_MASTER_IDLE;
            end
        endcase
    end

    // REGISTER TRANSACTION PARAMETERS
    always_ff @(posedge clk) begin: proc_register_transaction_parameters
        if (~rst_n) begin
            reg_axi_status_fields       <= AXI4_STATUS_FIELDS_DEFAULTS;
            reg_axi_user                <= '0;
            reg_axi_id                  <= '0;
            reg_direction               <= AXI4_DIR_WRITE;
        end else begin
            if (core_triggered) begin
                reg_axi_status_fields       <= i_axi_status_fields;
                reg_axi_user                <= i_axi_user;
                reg_axi_id                  <= i_axi_id;
                reg_direction               <= i_direction;
            end
        end
    end

    // CONNECT AXI TRANSACTION PARAMETERS
    // (to be honest, I could've done the assigning to axi right away when 
    // registering the transaction parameters. Anyways...)
    assign if_axi.awsize            = reg_axi_status_fields.burst_size;
    assign if_axi.arsize            = reg_axi_status_fields.burst_size;
    assign if_axi.awburst           = reg_axi_status_fields.burst_type;
    assign if_axi.arburst           = reg_axi_status_fields.burst_type;
    assign if_axi.awcache           = reg_axi_status_fields.cache;
    assign if_axi.arcache           = reg_axi_status_fields.cache;
    assign if_axi.awprot            = reg_axi_status_fields.prot;
    assign if_axi.arprot            = reg_axi_status_fields.prot;
    assign if_axi.awqos             = reg_axi_status_fields.qos;
    assign if_axi.arqos             = reg_axi_status_fields.qos;
    assign if_axi.awregion          = reg_axi_status_fields.region;
    assign if_axi.arregion          = reg_axi_status_fields.region;
    assign if_axi.awuser            = reg_axi_user;
    assign if_axi.wuser             = reg_axi_user;
    assign if_axi.aruser            = reg_axi_user;
    assign if_axi.awid              = reg_axi_id;
    assign if_axi.wid               = reg_axi_id;
    assign if_axi.arid              = reg_axi_id;
    assign if_axi.awaddr            = axi_address;
    assign if_axi.araddr            = axi_address;

    // CONNECT DATA STREAM TO AXI INTERFACE
    // instead of assigning to both axi channels regardless of direction, here 
    // the check for direction is implemented. The idea is to keep in check the 
    // fanout of whatever is connected to the data stream, since there is the 
    // option of not registering the data stream.
    assign if_data_stream_read.strb    = '1;    // axi has no read strb
    generate begin: gen_connect_data_streams
    if (REGISTER_DATA_STREAM) begin: cond_register_data_stream

        // why intermediary registers? fsm_data_transmission has a response 
        // state in between of bursts, in which it doesn't count axi data words, 
        // so no axi words must happen while in that state. Easy, you just block 
        // wvalid. Problem 1: If you do that, you would always signalize a ready 
        // to the write data stream, but the register may already be valid.  
        // Problem 2: You would not allow the data stream to write a new data 
        // word into the register while fsm_data_transmission is in the response 
        // state, while that would be perfectly fine. And you introduce a cycle 
        // of latency, because of one cycle to go back from response to data 
        // transmission state, second cycle until data has propagated through 
        // the register.
        // read valid: similar story. You wouldn't allow the data stream to 
        // clear the register when the core is in response state, while that's 
        // totally fine. Even more so, the data interface could actually never 
        // fetch the last data word...
        logic                   write_reg_valid;
        logic                   read_reg_valid;

        // you need checks here in both directions that you can actually advance 
        // data. The checks actually indicate whether or not the axi master is 
        // "ready" to take a new data word, so you can just use them to express 
        // if_data_stream_*.ready, and then use that signal.
        // - If the receiver's valid is deasserted, you're good to go, 
        // because then it doesn't hold anything meaningful in its data 
        // register
        // - If the receiver has both valid and ready asserted, you're also 
        // good to go, because then the receiver's register will be cleared 
        // this next cycle
        // - In all other cases, the receiver holds valid data that still 
        // needs to be there next cycle, so don't advance

        // tool problem: multiple times the only thing here that questa doesn't 
        // interpret as a latch is an assignment. Tried with case statement,  
        // with "if-uncond. else", and with "standard case + if", all the same 
        // latch.  Don't know if it is because it's testing for an expression 
        // instead of a signal, or because if the target is an interface (or 
        // I overlook a reason).
        always_comb begin
            if_data_stream_write.ready = 1'b0;
            if (data_busy && (reg_direction == AXI4_DIR_WRITE)) begin
                if (count_burst_items != '0) begin
                    if_data_stream_write.ready = ~write_reg_valid | (if_axi.wvalid & if_axi.wready);
                end else begin
                    if_data_stream_write.ready = ~write_reg_valid;
                end
            end
        end
        assign if_axi.wvalid = data_busy ? write_reg_valid : 1'b0;
        assign if_axi.rready = data_busy ?
                (   ~if_data_stream_read.valid |
                    (if_data_stream_read.valid & if_data_stream_read.ready)) : 1'b0;
        assign if_data_stream_read.valid = read_reg_valid;

        always_ff @(posedge clk) begin
            if (~rst_n) begin
                write_reg_valid         <= 1'b0;
                read_reg_valid          <= 1'b0;
            end else begin
                // write channel
                if (if_data_stream_write.ready & if_data_stream_write.valid) begin
                    write_reg_valid             <= 1'b1;
                    if_axi.wdata                <= 
                            if_data_stream_write.data<<burst_item_start_bit;
                    if_axi.wstrb                <=
                        ((1<<(1<<reg_axi_status_fields.burst_size))-1)<<burst_item_start_lane;
                end else if (if_axi.wvalid & if_axi.wready) begin
                    write_reg_valid             <= 1'b0;
                end
                // read channel
                if (if_axi.rready & if_axi.rvalid) begin
                    if_data_stream_read.data    <= 
                            if_axi.rdata>>burst_item_start_bit;
                    read_reg_valid              <= 1'b1;
                end else if (if_data_stream_read.ready & if_data_stream_read.valid) begin
                    read_reg_valid              <= 1'b0;
                end
            end
        end
    end else begin: cond_no_register_data_stream
        // REGISTER_DATA_STREAM=0
        always_comb begin
            case (data_busy)
                1: begin
                    if_axi.wdata                = if_data_stream_write.data<<burst_item_start_bit;
                    if_axi.wvalid               = if_data_stream_write.valid;
                    if_axi.wstrb                =
                        ((1<<(1<<reg_axi_status_fields.burst_size))-1)<<burst_item_start_lane;
                    if_data_stream_write.ready  = if_axi.wready;
                    if_data_stream_read.data    = if_axi.rdata>>burst_item_start_bit;
                    if_data_stream_read.valid   = if_axi.rvalid;
                    if_axi.rready               = if_data_stream_read.ready;
                end
                0: begin
                    if_axi.wdata                = '0;
                    if_axi.wvalid               = 1'b0;
                    if_axi.wstrb                = '0;
                    if_data_stream_write.ready  = 1'b0;
                    if_data_stream_read.data    = '0;
                    if_data_stream_read.valid   = 1'b0;
                    if_axi.rready               = 1'b0;
                end
            endcase
        end
    end
    end
    endgenerate

    //----------------------------
    // ADDRESS HANDSHAKES
    //----------------------------
    
    // note to myself: count_bursts needs to be a register because of logical 
    // path length

    // should you get timing issues, MAYBE it helps to include this conditional 
    // in the fsm_axi_addr_burst state machine, using non-blocking assignments 
    // to burst_len alongside with the assignments to len_last_burst. But the 
    // logic depth is so minimal that it would surprise me if that changed 
    // anything.
    always_comb begin: proc_burst_len
        if (count_bursts == 0)
            // (note that 1<=WIDTH_LEN_LAST_BURST<=8 because of parameter checks, 
        // so this slicing will/should always result in something that is valid
            burst_len = {{(8-WIDTH_LEN_LAST_BURST){1'b0}}, len_last_burst};
        else
            burst_len = (AXI4_MAX_BURST_LEN-1);
    end

    always_comb begin: multiplex_axi_addr
        if_axi.awvalid  = 1'b0;
        if_axi.awlen    = '0;
        if_axi.arvalid  = 1'b0;
        if_axi.arlen    = '0;
        case (reg_direction)
            AXI4_DIR_READ: begin
                if_axi.arvalid  = axi_addr_valid;
                if_axi.arlen    = burst_len;
                axi_addr_ready  = if_axi.arready;
            end
            AXI4_DIR_WRITE: begin
                if_axi.awvalid  = axi_addr_valid;
                if_axi.awlen    = burst_len;
                axi_addr_ready  = if_axi.awready;
            end
        endcase
    end

    assign axi_addr_valid   =   st_axi_master_addr == ST_AXI_MASTER_ADDR_BUSY;

    always_ff @(posedge clk) begin: fsm_axi_addr_burst
        if (~rst_n) begin
            st_axi_master_addr      <= ST_AXI_MASTER_ADDR_IDLE;
            count_bursts            <= '0;
            len_last_burst          <= '0;
            axi_address             <= '0;
        end else begin

            case (st_axi_master_addr)

                ST_AXI_MASTER_ADDR_IDLE: begin
                    if (core_triggered) begin
                        st_axi_master_addr <= ST_AXI_MASTER_ADDR_BUSY;
                        axi_address         <= i_base_address;
                        /*
                        * what you basically want in this section: for 
                        * i_num_data_words, take it modulo AXI4_MAX_BURST_LEN 
                    * for the last burst length, and integer divide it by 
                    * AXI4_MAX_BURST_LEN for the number of bursts. Pitfalls:
                        * - You need a -1 to convert from "human" to "machine" 
                        *   counting
                        * - You need another -1 for len_last_burst, because axi 
                        *   adds 1 again for the actual number of bursts
                        * - you need to pay attention with the width for 
                    *   len_last_burst, because it may or may not be wider thon 
                *   i_num_data_words.
                        */
                        if (MAX_NUM_BURSTS == 1) begin
                            // TODO: this may stall the core if for whatever 
                            // reason you trigger with i_num_data_words=0.  
                            // Doesn't make sense to do that, but still the -1 
                            // would wraparound, and the core might start 
                            // assuming a last burst of 256 items.
                            len_last_burst <= i_num_data_words - 1;
                        end else begin
                            len_last_burst <=
                                (i_num_data_words-1) & ((1<<WIDTH_LEN_LAST_BURST)-1);
                        end
                        // theoretically you would have to do +1 in the end to 
                        // ceil, instead of floor. But that would be human 
                        // counting, not machine counting, and count_bursts=0 
                        // actually corresponds to the last burst. (the control 
                        // on whether or not a burst is issued at all does not 
                        // depend on count_bursts)
                        count_bursts <= ((i_num_data_words-1)>>WIDTH_LEN_LAST_BURST);
                    end
                end

                ST_AXI_MASTER_ADDR_BUSY: begin
                    // at every handshake, advance by one burst, until you are 
                    // done
                    if (axi_addr_valid & axi_addr_ready) begin
                        // case statements to help the tool with detecting 
                        // mutually exclusive cases
                        case (reg_axi_status_fields.burst_type)
                            AXI4_BURST_INCR: begin
                                case (count_bursts)
                                    '0: begin
                                        st_axi_master_addr <= ST_AXI_MASTER_ADDR_IDLE;
                                        count_bursts <= '0;
                                    end
                                    default: begin
                                        count_bursts <= count_bursts - 1;
                                        axi_address <= fun_burst_incr_axi_address(
                                                            axi_address,
                                                            reg_axi_status_fields.burst_size);
                                    end
                                endcase
                            end
                            AXI4_BURST_FIXED: begin
                                // for burst fixed, ignore count_bursts, it is 
                                // exactly one "burst" per definition
                                st_axi_master_addr <= ST_AXI_MASTER_ADDR_IDLE;
                                count_bursts <= '0;
                            end
                            default: begin
                                // TODO: cover wrap bursts
                                st_axi_master_addr <= ST_AXI_MASTER_ADDR_IDLE;
                                count_bursts <= '0;
                            end
                        endcase
                    end

                end

                default: begin
                    st_axi_master_addr <= ST_AXI_MASTER_ADDR_IDLE;
                end

            endcase
        end
    end

    //----------------------------
    // DATA TRANSMISSION
    //----------------------------

    // shorter version of state comparison
    assign data_busy            = (st_axi_master_data == ST_AXI_MASTER_DATA_BUSY);
    // (probably I wouldn't have to check for the direction, since the write 
    // channel is not active during reading anyway, but maybe that doesn't hurt, 
    // in case some slave for whatever reason gets confused otherwise)
    assign if_axi.wlast         = (count_burst_items == 0) && reg_direction == AXI4_DIR_WRITE;
    assign if_axi.bready        = (st_axi_master_data == ST_AXI_MASTER_DATA_RESP) &&
                                    reg_direction == AXI4_DIR_WRITE;
    // convert from byte to bit index
    assign burst_item_start_bit = burst_item_start_lane<<3;

    /*
    * in_data_handshake: handshake on whichever is the incoming data side 
    * (differs between read and write) - important for axi burst lane handling
    * (axi_data_handshake: handshake on the axi bus)
    */
    always_comb begin: proc_detect_data_handshake
        case (reg_direction)
            AXI4_DIR_READ: begin
                axi_data_handshake = if_axi.rvalid & if_axi.rready;
                in_data_handshake = axi_data_handshake;
            end
            AXI4_DIR_WRITE: begin
                axi_data_handshake = if_axi.wvalid & if_axi.wready;
                in_data_handshake = if_data_stream_write.valid & if_data_stream_write.ready;
            end
        endcase
    end

    // shouldn't need more status checks, because an in_data_handshake can only 
    // occur while the data connection is active (and actually can not overlap 
    // with a core_triggered, maybe we could implement it that way)
    always_ff @(posedge clk) begin: proc_burst_item_start_lane
        if (~rst_n) begin
            burst_item_start_lane   <= '0;
        end else begin
            if (core_triggered) begin
                burst_item_start_lane   <= i_base_address[$clog2(AXI_DATA_BYTES)-1:0];
            end else if (in_data_handshake) begin
                // if the user set address etc correctly, this automatically 
                // wraps around the way it should by means of the data width of 
                // burst_item_start_lane.
                case (reg_axi_status_fields.burst_type)
                    AXI4_BURST_INCR: begin
                        burst_item_start_lane <= 
                                burst_item_start_lane + (1<<reg_axi_status_fields.burst_size);
                    end
                    default: begin
                        // TODO: add the AXI4_BURST_WRAP case, once that is 
                        // implemented
                        burst_item_start_lane   <= burst_item_start_lane;
                    end
                endcase
            end
        end
    end

    always_ff @(posedge clk) begin: fsm_data_transmission
        if (~rst_n) begin
            st_axi_master_data      <= ST_AXI_MASTER_DATA_IDLE;
            count_data_words        <= '0;
            count_burst_items       <= '0;
            set_msgs.no_rlast       <= 1'b0;
        end else begin

            set_msgs.no_rlast <= 1'b0;

            case (st_axi_master_data)

                ST_AXI_MASTER_DATA_IDLE: begin
                    if (core_triggered) begin
                        count_data_words        <= i_num_data_words;
                        // (quick note: in theory, it can happen that 
                        // i_num_data_words is smaller than AXI4_MAX_BURST_LEN.  
                        // In questa looks like the tool pads/converts that 
                        // correctly as expected, just leaving a note in case 
                        // you ever see an error here with some tool)
                        if (i_num_data_words >= AXI4_MAX_BURST_LEN) begin
                            count_burst_items <= AXI4_MAX_BURST_LEN-1;
                        end else begin
                            count_burst_items <= i_num_data_words-1;
                        end
                        st_axi_master_data      <= ST_AXI_MASTER_DATA_BUSY;
                    end
                end // ST_AXI_MASTER_DATA_IDLE

                ST_AXI_MASTER_DATA_BUSY: begin
                    if (axi_data_handshake) begin
                        if (count_burst_items == '0) begin  // finish burst

                            if (reg_direction == AXI4_DIR_READ && ~if_axi.rlast) begin
                                // if during reading rlast is not set properly, 
                                // there is a slave error -> abort any further 
                                // transaction
                                set_msgs.no_rlast <= 1'b1;
                                st_axi_master_data <= ST_AXI_MASTER_DATA_IDLE;
                            end

                            st_axi_master_data <= ST_AXI_MASTER_DATA_RESP;

                            // prepare next burst
                            // (comparing with 2*AXI4_MAX_BURST_LEN, because 
                            // count_data_words still holds the pre-subtraction 
                            // value from the beginning of the current burst)

                            // by the way, why not just have count_data_words 
                            // running in parallel to count_burst_items?  
                            // I thought it might just save a tiny bit of 
                            // hardware if count_data_words has fewer fixed-size 
                            // subtractions and never actually actually is 
                            // a running counter. Might be bs though...
                            if (count_data_words >= AXI4_MAX_BURST_LEN) begin
                                count_data_words <= count_data_words - AXI4_MAX_BURST_LEN;
                            end else begin
                                count_data_words <= '0;
                            end
                            if (count_data_words >= AXI4_MAX_BURST_LEN<<1) begin
                                count_burst_items <= AXI4_MAX_BURST_LEN-1;
                            end else begin
                                count_burst_items <= count_data_words - AXI4_MAX_BURST_LEN - 1;
                            end

                        end else begin                      // next burst item
                            count_burst_items <= count_burst_items - 1;
                            // TODO: check for read slave error, if reading
                        end
                    end
                end // ST_AXI_MASTER_DATA_BUSY

                ST_AXI_MASTER_DATA_RESP: begin

                    // remember: when writing, you still need to handle the 
                    // write response
                    case (reg_direction)
                        AXI4_DIR_READ: begin
                            if (count_data_words == '0) begin
                                st_axi_master_data <= ST_AXI_MASTER_DATA_IDLE;
                            end else begin
                                st_axi_master_data <= ST_AXI_MASTER_DATA_BUSY;
                            end
                        end
                        AXI4_DIR_WRITE: begin
                            if (if_axi.bready & if_axi.bvalid) begin
                                if (if_axi.bresp == AXI4_RESP_OKAY) begin
                                    if (count_data_words == '0) begin
                                        st_axi_master_data <= ST_AXI_MASTER_DATA_IDLE;
                                    end else begin
                                        st_axi_master_data <= ST_AXI_MASTER_DATA_BUSY;
                                    end
                                end else begin
                                    st_axi_master_data <= ST_AXI_MASTER_DATA_IDLE;
                                end
                            end
                        end
                    endcase
                end // ST_AXI_MASTER_DATA_RESP

                default: begin
                    st_axi_master_data <= ST_AXI_MASTER_DATA_IDLE;
                end

            endcase
        end
    end

    assign set_msgs.wresp = '0;     // actually unneeded

    always_ff @(posedge clk) begin: proc_msg_no_rlast
        if (~rst_n) begin
            o_msgs.no_rlast             <= 1'b0;
            o_msgs.wresp                <= '0;
        end else begin
            if (set_msgs.no_rlast) begin
                o_msgs.no_rlast <= 1'b1;
            end else if (i_clear_messages) begin
                o_msgs.no_rlast <= 1'b0;
            end

            if (if_axi.bready & if_axi.bvalid) begin
                o_msgs.wresp <= if_axi.bresp;
            end else if (i_clear_messages) begin
                o_msgs.wresp <= '0;
            end
        end
    end

endmodule

