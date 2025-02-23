
package data_stream_hs_buffered_pipeline_sim_pkg;

    import util_pkg::*;

    class cls_agent_data_stream_hs_buffered_pipeline #(
        parameter int DATA_WIDTH = 32
    );

        localparam int STRB_WIDTH = $ceil(DATA_WIDTH/8);

        /*
        * contains an exemplary event setup for clk posedges and for changes on
        * a 4-button vector
        */

        virtual ifc_data_stream_hs_buffered_pipeline #(DATA_WIDTH) if_dut;
        event ev_clk;

        function new(virtual ifc_data_stream_hs_buffered_pipeline #(DATA_WIDTH) if_dut);
            this.if_dut = if_dut;
            this.init();

            // SIGNAL -> EVENT
            fork
                this.clk_event();
            join_none

        endfunction

        function void init();
            if_dut.dut_in_data = '0;
            if_dut.dut_in_strb = '0;
            if_dut.dut_in_valid = 1'b0;
            if_dut.dut_out_ready = 1'b0;
        endfunction

        //----------------------------
        // SIGNAL -> EVENT
        //----------------------------
        // (necessary for older vivado/xsim versions which don't handle const 
        // ref properly)
        
        task clk_event();
            forever begin
                @(posedge if_dut.clk);
                ->ev_clk;
            end
        endtask

        //----------------------------
        // TEST OPERATION
        //----------------------------

        task run();
            test();
            $stop;
        endtask

        task test(int num_data_words = 10, real p_gap_valid = 0.1, p_gap_ready = 0.7);
            bit test_passed;
            int passed = 0;
            int failed = 0;

            // for testing strb and data have nothing to do with each other, 
            // just make sure that both pass through the pipeline correctyl, and 
            // stay in sync
            logic [DATA_WIDTH-1:0]  arr_data [];
            logic [STRB_WIDTH-1:0]  arr_strb [];
            logic [DATA_WIDTH-1:0]  arr_data_dut_recv [];
            logic [STRB_WIDTH-1:0]  arr_strb_dut_recv [];

            int count_data_dut_send = 0;
            int count_data_dut_recv = 0;
            bit data_send_done = 0;
            bit data_recv_done = 0;

            // ready/valid randomization
            typedef int unsigned uint;
            real random_num_dut_in_valid = 0;
            real random_num_dut_out_ready = 0;

            string test_name = "random_data_words";
            string test_desc = $sformatf("%0d data words", num_data_words);

            print_test_start(test_name, test_desc);

            // set up random data
            arr_data = new[num_data_words];
            arr_strb = new[num_data_words];
            arr_data_dut_recv = new[num_data_words];
            arr_strb_dut_recv = new[num_data_words];
            foreach (arr_data[i]) begin
                arr_data[i] = $urandom;
                arr_strb[i] = $urandom;
                arr_data_dut_recv[i] = '0;
                arr_strb_dut_recv[i] = '0;
            end

            // run test
            @(posedge if_dut.cb);
            if_dut.cb.dut_in_data <= arr_data[count_data_dut_send];
            if_dut.cb.dut_in_strb <= arr_strb[count_data_dut_send];
           
            fork

            begin: fork_send
                while (count_data_dut_send != num_data_words) begin
                    random_num_dut_in_valid = real'($urandom()) / real'(uint'(-1));

                    // SEND
                    if (~data_send_done) begin
                        // implemented such that at least a valid signal can't 
                        // deassert once it is asserted
                        if (~if_dut.cb.dut_in_valid) begin
                            if_dut.cb.dut_in_valid <=
                                    random_num_dut_in_valid < p_gap_valid ? 1'b0 : 1'b1;
                        end
                        if (if_dut.cb.dut_in_ready & if_dut.cb.dut_in_valid) begin
                            count_data_dut_send++;
                            if (count_data_dut_send < num_data_words) begin
                                if_dut.cb.dut_in_data <= arr_data[count_data_dut_send];
                                if_dut.cb.dut_in_strb <= arr_strb[count_data_dut_send];
                                if_dut.cb.dut_in_valid <=
                                        random_num_dut_in_valid < p_gap_valid ? 1'b0 : 1'b1;
                            end else begin
                                if_dut.cb.dut_in_valid <= 1'b0;
                                data_send_done = 1;
                            end
                        end
                    end

                    @(posedge if_dut.cb);
                end
            end // fork send

            begin: fork_recv
                while (count_data_dut_recv != num_data_words) begin
                    random_num_dut_out_ready = real'($urandom()) / real'(uint'(-1));

                    // RECV
                    if (~data_recv_done) begin
                        // implemented such that at least a valid signal can't 
                        // deassert once it is asserted
                        if (~if_dut.dut_out_ready) begin
                            if_dut.cb.dut_out_ready <=
                                    random_num_dut_out_ready < p_gap_ready ? 1'b0 : 1'b1;
                        end
                        if (if_dut.cb.dut_out_ready & if_dut.cb.dut_out_valid) begin
                            if (count_data_dut_recv < num_data_words) begin
                                arr_data_dut_recv[count_data_dut_recv] =
                                                                if_dut.cb.dut_out_data;
                                arr_strb_dut_recv[count_data_dut_recv] =
                                                                if_dut.cb.dut_out_strb;
                                count_data_dut_recv++;
                                if_dut.cb.dut_out_ready <=
                                        random_num_dut_out_ready < p_gap_ready ? 1'b0 : 1'b1;
                            end else begin
                                if_dut.cb.dut_out_ready <= 1'b0;
                                data_recv_done = 1;
                            end
                        end
                    end

                    @(posedge if_dut.cb);
                end 
            end // fork recv
            join

            // check results
            foreach (arr_data[i]) begin
                if (arr_data[i] == arr_data_dut_recv[i]) begin
                    passed++;
                end else begin
                    failed++;
                end
                if (arr_strb[i] == arr_strb_dut_recv[i]) begin
                    passed++;
                end else begin
                    failed++;
                end
            end

            test_passed = (failed == 0);

            print_test_result(test_name, test_passed);
            print_tests_stats(passed, failed);

        endtask

    endclass

endpackage
