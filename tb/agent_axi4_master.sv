

package axi4_master_sim_pkg;

    import util_pkg::wait_cycles_ev;
    import util_pkg::wait_cycles_sig;
    import util_pkg::wait_timeout_ev;
    import util_pkg::wait_timeout_sig;
    import util_pkg::wait_timeout_cycles_ev;
    import util_pkg::wait_timeout_cycles_sig;
    import util_pkg::print_test_start;
    import util_pkg::print_test_result;
    import util_pkg::print_tests_stats;
    import util_pkg::cls_test_data;
    import axi_lib_pkg::*;

    //----------------------------
    // VERBOSITY LEVELS
    //----------------------------

    localparam              VERBOSITY_OPERATION     = 1;
    localparam              VERBOSITY_DATA          = 2;
    localparam              VERBOSITY_PROTOCOL      = 3;

    class cls_agent_axi4_master #(
        parameter               USER_DATA_WIDTH = 32,
        parameter               AXI_ADDR_WIDTH = 32,
        parameter               AXI_DATA_WIDTH = 32,
        parameter               AXI_USER_WIDTH = 0,
        parameter               AXI_ID_WIDTH = 0,
        parameter               MAX_TOTAL_TRANSACTION_LENGTH = 128,
        parameter real          T_SETUP = 1,
        parameter real          T_CTOQ = 2
    );

        localparam STRB_WIDTH = USER_DATA_WIDTH/8;

        /*
        * contains an exemplary event setup for clk posedges and for changes on
        * a 4-button vector
        */

        virtual ifc_axi4_master #(
            .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH),
            .AXI_USER_WIDTH     (AXI_USER_WIDTH),
            .AXI_ID_WIDTH       (AXI_ID_WIDTH),
            .USER_DATA_WIDTH    (USER_DATA_WIDTH),
            .MAX_TOTAL_TRANSACTION_LENGTH   (MAX_TOTAL_TRANSACTION_LENGTH),
            .T_SETUP            (T_SETUP),
            .T_CTOQ             (T_CTOQ)
        ) if_axi4_master;
        event ev_clk;

        function new(
            virtual ifc_axi4_master #(
                .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH),
                .AXI_USER_WIDTH     (AXI_USER_WIDTH),
                .AXI_ID_WIDTH       (AXI_ID_WIDTH),
                .USER_DATA_WIDTH    (USER_DATA_WIDTH),
                .MAX_TOTAL_TRANSACTION_LENGTH   (MAX_TOTAL_TRANSACTION_LENGTH),
                .T_SETUP            (T_SETUP),
                .T_CTOQ             (T_CTOQ)
            ) if_axi4_master
        );
            this.if_axi4_master = if_axi4_master;

            // SIGNAL -> EVENT
            fork
                this.clk_event();
            join_none

        endfunction

        //----------------------------
        // SIGNAL -> EVENT
        //----------------------------
        // (necessary for older vivado/xsim versions which don't handle const 
        // ref properly)
        
        task clk_event();
            forever begin
                @(posedge if_axi4_master.clk);
                ->ev_clk;
            end
        endtask

        //----------------------------
        // TEST OPERATION
        //----------------------------

        task run(bit stop = 1);
            init();
            // TODO: test with something that is more than one burst
            test_burst_incr_write_read_back(32'h00000010, 300);
            test_burst_fixed_write_read_back(32'h00001000, 3);
            if (stop) $stop;
        endtask

        task init();
            if_axi4_master.cb.trigger           <= 1'b0;
            if_axi4_master.cb.direction         <= AXI4_DIR_READ;
            if_axi4_master.cb.base_address      <= '0;
            if_axi4_master.cb.axi_user          <= '0;
            if_axi4_master.cb.axi_id            <= '0;
            if_axi4_master.cb.clear_messages    <= 1'b0;
            if_axi4_master.cb.write_data        <= '0;
            if_axi4_master.cb.write_strb        <= '0;
            if_axi4_master.cb.write_valid       <= 1'b0;
            if_axi4_master.cb.read_ready        <= 1'b0;
            if_axi4_master.cb.axi_status_fields <= AXI4_STATUS_FIELDS_DEFAULTS;
            @(posedge if_axi4_master.cb);
            if_axi4_master.cb.axi_status_fields.burst_size <= $clog2(USER_DATA_WIDTH/8);
            @(posedge if_axi4_master.cb);
        endtask

        /*
        * write one data item to the data handshake interface
        * !!! only operates the data stream interface, thus it needs to be 
        * embedded into a larger task that does the transaction setup and 
        * control !!!
        */
        task write_item (
            logic [USER_DATA_WIDTH-1:0] data_item,
            logic [STRB_WIDTH-1:0]      strb = '0
        );
            if_axi4_master.cb.write_data <= data_item;
            if_axi4_master.cb.write_strb <= strb;
            if_axi4_master.cb.write_valid <= 1'b1;
            @(posedge if_axi4_master.cb);
            wait(if_axi4_master.cb.write_ready);
            if_axi4_master.cb.write_valid <= 1'b0;
        endtask

        /*
        * read one data item to the data handshake interface
        * !!! only operates the data stream interface, thus it needs to be 
        * embedded into a larger task that does the transaction setup and 
        * control !!!
        */
        task read_item (
            output logic [USER_DATA_WIDTH-1:0]  data_item,
            output logic [STRB_WIDTH-1:0]       strb
        );
            if_axi4_master.cb.read_ready <= 1'b1;
            @(posedge if_axi4_master.cb);
            wait(if_axi4_master.cb.read_valid);
            data_item = if_axi4_master.cb.read_data;
            strb = if_axi4_master.cb.read_strb;
            if_axi4_master.cb.read_ready <= 1'b0;
        endtask

        /*
        * generate a set of randomized data items of USER_DATA_WIDTH, write them 
        * in an incr burst beginning at address, and read them back in two 
        * chunks of half the total transfer size. Then check write and read data 
        * for integrity.
        */
        task test_burst_incr_write_read_back(
            logic [AXI_ADDR_WIDTH-1:0] address,
            int num_data_words);

            string                          test_name = "test_burst_incr_write_read_back";
            bit                             test_passed;

            cls_test_data                   data_write;
            bit     [USER_DATA_WIDTH-1:0]   data_write_packed [];
            cls_test_data                   data_read;
            bit     [USER_DATA_WIDTH-1:0]   read_item_packed;
            logic   [STRB_WIDTH-1:0]        read_data_strb;

            int                             num_words_read [2] = '{0, 0};

            data_write = new(num_data_words, USER_DATA_WIDTH, 1);
            case (USER_DATA_WIDTH)
                32: begin
//                     data_write.pack32(data_write_packed);
                end
                8: begin
                    data_write.pack8(data_write_packed);
                end
                default: begin
                    $error($sformatf("Unsupported USER_DATA_WIDTH: %0d", USER_DATA_WIDTH));
                end
            endcase
            data_read = new(num_data_words, USER_DATA_WIDTH);

            @(posedge if_axi4_master.cb);

            // WRITE
            wait(if_axi4_master.cb.ready);
            if_axi4_master.cb.num_data_words <= num_data_words;
            if_axi4_master.cb.axi_status_fields.burst_type <= AXI4_BURST_INCR;
            if_axi4_master.cb.direction <= AXI4_DIR_WRITE;
            if_axi4_master.cb.base_address <= address;
            if_axi4_master.cb.axi_user <= '0;
            if_axi4_master.cb.axi_id <= '0;
            if_axi4_master.cb.clear_messages <= 1'b0;
            
            fork
            begin
                if_axi4_master.cb.trigger <= 1'b1;
                @(posedge if_axi4_master.cb);
                if_axi4_master.cb.trigger <= 1'b0;
            end
            begin
                foreach (data_write_packed[i]) begin
                    if (`VERBOSITY >= VERBOSITY_PROTOCOL) begin
                        $display(
                            "[%0t] writing data beat %0d: %0x",
                            $time, i, data_write_packed[i]);
                    end
                    this.write_item(data_write_packed[i], {(USER_DATA_WIDTH/8){1'b1}});
                end
            end
            join

            // READ

            // make sure that you have uneven numbers of data to transfer (such 
            // that the second transfer will start with an unaligned address), 
            // to actually test the burst lane system (integer-divide 
            // num_data_words by 2, and add 1)
            num_words_read[0] = (num_data_words>>1)+1;
            num_words_read[1] = num_data_words - num_words_read[0];

            // first half
            wait(if_axi4_master.cb.ready);
            if_axi4_master.cb.num_data_words <= num_words_read[0];
            if_axi4_master.cb.direction <= AXI4_DIR_READ;
            if_axi4_master.cb.base_address <= address;
            if_axi4_master.cb.axi_user <= '0;
            if_axi4_master.cb.axi_id <= '0;
            if_axi4_master.cb.clear_messages <= 1'b0;

            fork
            begin
                if_axi4_master.cb.trigger <= 1'b1;
                @(posedge if_axi4_master.cb);
                if_axi4_master.cb.trigger <= 1'b0;
            end
            begin
                for (int i=0; i<num_words_read[0]; i++) begin
                    this.read_item(read_item_packed, read_data_strb);
                    case (USER_DATA_WIDTH)
                        32: begin
//                             data_read.unpack32_item(read_item_packed, i);
                        end
                        8: begin
                            data_read.unpack8_item(read_item_packed, i);
                        end
                        default: begin
                            $error($sformatf("Unsupported USER_DATA_WIDTH: %0d", USER_DATA_WIDTH));
                        end
                    endcase
                    if (`VERBOSITY >= VERBOSITY_PROTOCOL) begin
                        $display(
                            "[%0t] read data beat %0d: %0x",
                            $time, i, read_item_packed);
                    end
                end
            end
            join

            // second half
            wait(if_axi4_master.cb.ready);
            if_axi4_master.cb.num_data_words <= num_words_read[1];
            if_axi4_master.cb.direction <= AXI4_DIR_READ;
            if_axi4_master.cb.base_address <=
                    address + num_words_read[0] * (USER_DATA_WIDTH/8);
            if_axi4_master.cb.axi_user <= '0;
            if_axi4_master.cb.axi_id <= '0;
            if_axi4_master.cb.clear_messages <= 1'b0;

            fork
            begin
                if_axi4_master.cb.trigger <= 1'b1;
                @(posedge if_axi4_master.cb);
                if_axi4_master.cb.trigger <= 1'b0;
            end
            begin
                for (int i=num_words_read[0]; i<num_data_words; i++) begin
                    this.read_item(read_item_packed, read_data_strb);
                    case (USER_DATA_WIDTH)
                        32: begin
//                             data_read.unpack32_item(read_item_packed, i);
                        end
                        8: begin
                            data_read.unpack8_item(read_item_packed, i);
                        end
                        default: begin
                            $error($sformatf("Unsupported USER_DATA_WIDTH: %0d", USER_DATA_WIDTH));
                        end
                    endcase
                    if (`VERBOSITY >= VERBOSITY_PROTOCOL) begin
                        $display(
                            "[%0t] read data beat %0d: %0x",
                            $time, i, read_item_packed);
                    end
                end
            end
            join

            if (`VERBOSITY >= VERBOSITY_DATA) begin
                $display("********** WRITE DATA: **********");
                data_write.print64();
                $display("********** READ DATA: **********");
                data_read.print64();
            end
            test_passed = data_write.equals(data_read);
            print_test_result(test_name, test_passed);

        endtask // test_burst_incr_write_read_back

        /*
        * Generate a number of data words and write them in fixed bursts. The 
        * addresses for subsequent bursts are incremented by the number of axi 
        * data bytes + the user data width, to make sure that first data doesn't 
    * collide, and second for user data that doesn't fill the entire axi width, 
        * the correct strb/lane etc is used.
        * data is read back in reverse order from writing (probably doesn't 
        * serve any purpose).
        */
        task test_burst_fixed_write_read_back (
            logic [AXI_ADDR_WIDTH-1:0] address,
            int num_data_words);

            string                          test_name = "test_burst_fixed_write_read_back";
            bit                             test_passed;

            cls_test_data                   data_write;
            bit     [USER_DATA_WIDTH-1:0]   data_write_packed [];
            cls_test_data                   data_read;
            bit     [USER_DATA_WIDTH-1:0]   read_item_packed;
            logic   [STRB_WIDTH-1:0]        read_data_strb;

            data_write = new(num_data_words, USER_DATA_WIDTH, 1);
            case (USER_DATA_WIDTH)
                32: begin
//                     data_write.pack32(data_write_packed);
                end
                8: begin
                    data_write.pack8(data_write_packed);
                end
                default: begin
                    $error($sformatf("Unsupported USER_DATA_WIDTH: %0d", USER_DATA_WIDTH));
                end
            endcase
            data_read = new(num_data_words, USER_DATA_WIDTH);

            @(posedge if_axi4_master.cb);

            // WRITE
            if_axi4_master.cb.num_data_words <= 1;
            if_axi4_master.cb.axi_status_fields.burst_type <= AXI4_BURST_FIXED;
            if_axi4_master.cb.direction <= AXI4_DIR_WRITE;
            if_axi4_master.cb.axi_user <= '0;
            if_axi4_master.cb.axi_id <= '0;
            if_axi4_master.cb.clear_messages <= 1'b0;

            foreach (data_write_packed[i]) begin
                wait(if_axi4_master.cb.ready);
                if_axi4_master.cb.base_address <= address + i*(AXI_DATA_WIDTH/8 + USER_DATA_WIDTH);
            
                fork
                begin
                    if_axi4_master.cb.trigger <= 1'b1;
                    @(posedge if_axi4_master.cb);
                    if_axi4_master.cb.trigger <= 1'b0;
                end
                begin
                    if (`VERBOSITY >= VERBOSITY_PROTOCOL) begin
                        $display(
                            "[%0t] writing data beat %0d: %0x",
                            $time, i, data_write_packed[i]);
                    end
                    this.write_item(data_write_packed[i], {(USER_DATA_WIDTH/8){1'b1}});
                end
                join
            end

            // READ
            if_axi4_master.cb.direction <= AXI4_DIR_READ;
            if_axi4_master.cb.axi_user <= '0;
            if_axi4_master.cb.axi_id <= '0;
            if_axi4_master.cb.clear_messages <= 1'b0;

            for (int i=num_data_words-1; i>=0; i--) begin
                wait(if_axi4_master.cb.ready);
                if_axi4_master.cb.base_address <= address + i*(AXI_DATA_WIDTH/8 + USER_DATA_WIDTH);

                fork
                begin
                    if_axi4_master.cb.trigger <= 1'b1;
                    @(posedge if_axi4_master.cb);
                    if_axi4_master.cb.trigger <= 1'b0;
                end
                begin
                    this.read_item(read_item_packed, read_data_strb);
                    case (USER_DATA_WIDTH)
                        32: begin
//                             data_read.unpack32_item(read_item_packed, i);
                        end
                        8: begin
                            data_read.unpack8_item(read_item_packed, i);
                        end
                        default: begin
                            $error($sformatf("Unsupported USER_DATA_WIDTH: %0d", USER_DATA_WIDTH));
                        end
                    endcase
                    if (`VERBOSITY >= VERBOSITY_PROTOCOL) begin
                        $display(
                            "[%0t] read data beat %0d: %0x",
                            $time, i, read_item_packed);
                    end
                end
                join
            end

            if (`VERBOSITY >= VERBOSITY_DATA) begin
                $display("********** WRITE DATA: **********");
                data_write.print64();
                $display("********** READ DATA: **********");
                data_read.print64();
            end
            test_passed = data_write.equals(data_read);
            print_test_result(test_name, test_passed);

        endtask // test_burst_fixed_write_read_back

    endclass

endpackage
