
/*
* !!! The agent's `test` task relies on the register file be set up with the 
* parameter and register table headers in axi_lib/test !!!
*/
package axi_lite_reg_file_direct_access_sim_pkg;

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
    import axi_sim_pkg::*;

    class cls_agent_axi_lite_reg_file_direct_access #(
        parameter       REGISTER_WIDTH = 32,
        parameter       NUM_REGISTERS = 16
        );

        /*
        * contains an exemplary event setup for clk posedges and for changes on
        * a 4-button vector
        */

        virtual ifc_axi_lite_reg_file_direct_access #(
            .REGISTER_WIDTH             (REGISTER_WIDTH),
            .NUM_REGISTERS              (NUM_REGISTERS)
        ) if_axi_lite_reg_file_direct_access;

        cls_axi_traffic_gen_sim atg;

        event ev_clk;

        function new(
            virtual ifc_axi_lite_reg_file_direct_access #(
                .REGISTER_WIDTH (REGISTER_WIDTH),
                .NUM_REGISTERS  (NUM_REGISTERS)
            ) if_axi_lite_reg_file_direct_access
        );
            this.if_axi_lite_reg_file_direct_access = if_axi_lite_reg_file_direct_access;
            this.atg = new(if_axi_lite_reg_file_direct_access.if_axi_sim);

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
                @(posedge if_axi_lite_reg_file_direct_access.clk);
                ->ev_clk;
            end
        endtask

        //----------------------------
        // TEST OPERATION
        //----------------------------

        task run();
            init();
            test();
            $stop;
        endtask

        task init();
        endtask

        task write(string master, int value, logic [31:0] address=0);
            cls_test_data axi_data = new(.num_words(1), .bitwidth(32));
            cls_axi_transaction_stats ats = new();

            case (master)
                "hw": begin
                    if_axi_lite_reg_file_direct_access.if_reg_file_hw.write_req = 1;
                    if_axi_lite_reg_file_direct_access.if_reg_file_hw.write_data = value;
                    @(posedge if_axi_lite_reg_file_direct_access.clk);
                    if_axi_lite_reg_file_direct_access.if_reg_file_hw.write_req = 0;
                end
                "axi": begin
                    axi_data.data[0] = {<<{value}};
                    this.atg.write_words(address, axi_data, ats);
                end
                default: begin
                end
            endcase
            @(posedge if_axi_lite_reg_file_direct_access.clk);
        endtask

        task read(
            input string master,
            output logic [31:0] data,
            input logic [31:0] address=0
        );
            cls_test_data axi_data = new(.num_words(1), .bitwidth(32));
            cls_axi_transaction_stats ats = new();
            data = '0;
            case (master)
                "hw": begin
                end
                "axi": begin
                    this.atg.read_words(address, axi_data, ats);
                    data = {<<{axi_data.data[0]}};
                end
                default: begin
                end
            endcase
            @(posedge if_axi_lite_reg_file_direct_access.clk);
        endtask

        /*
        * !!!SEE WARNING ON TOP OF THE FILE FOR THE REQUIRED REGISTER FILE 
        * PARAMETERIZATION FILES FOR THIS TEST!!!
        */
        task test();
            int write_data = 0;
            int read_data = 0;

            // signals needed for synchronization of axi action and trigger 
            // monitoring at a trigger on write register
            logic axi_done = 0;
            logic trigger_asserted = 0;

            // TODO: hardcoded
            logic [7:0] address;

            int passed = 0;
            int failed = 0;

            @(posedge if_axi_lite_reg_file_direct_access.clk);

            wait_cycles_ev(this.ev_clk, 4);

            $display("running test accesses:");

            $display("\twrite hw");
            write_data = 5;
            this.write("hw", write_data);
            if (if_axi_lite_reg_file_direct_access.if_reg_file_hw.read_data == write_data)
                passed++;
            else
                failed++;
            wait_cycles_ev(this.ev_clk, 2);

            // concurrent write (has to go to address 8'h00, because the hw 
            // write is hard-wired to the first register)
            $display("\tsimultaneous write hw and axi");
            write_data = 6;
            address = 8'h00;
            fork
            begin
                wait_cycles_ev(this.ev_clk, 2);
                this.write("hw", write_data);
            end
            begin
                this.write("axi", write_data+1, address);
            end
            join
            if (if_axi_lite_reg_file_direct_access.if_reg_file_hw.read_data[0] == write_data)
                passed++;
            else begin
                $warning("simultaneos write hw and axi failed");
                failed++;
            end
            wait_cycles_ev(this.ev_clk, 4);

            // read from same address that the last write went to
            $display("\taxi clear on read");
            this.read("axi", read_data, address);
            // clear on read takes a cycle to take effect
            wait_cycles_ev(this.ev_clk, 2);
            if      ((write_data == read_data) &&
                    (if_axi_lite_reg_file_direct_access.if_reg_file_hw.read_data[0] == '0))
                passed++;
            else begin
                $warning("axi clear on read failed");
                failed++;
            end
            wait_cycles_ev(this.ev_clk, 2);

            $display("\twrite axi no memory map, but trigger on write");
            trigger_asserted = 1'b0;
            axi_done = 1'b0;
            write_data = 4;
            address = 8'h10;
            // why do we need forking for checking the trigger? The trigger 
            // happens right at the write, thus while thewrite task is still 
            // executing. So if we just look at the trigger after the task is 
            // done, we have missed it.
            fork begin  // guarding fork for `disable fork`
                fork
                begin
                    this.write("axi", write_data, address);
                    axi_done = 1'b1;
                end
                begin
                    wait(if_axi_lite_reg_file_direct_access.axi_ctrl_trigger[2]);
                    trigger_asserted = 1'b1;
                end
                join_none

                wait(axi_done);
                disable fork;
            end join

            if (trigger_asserted)
                passed++;
            else begin
                $warning("write axi no memory map, but trigger on write failed");
                failed++;
            end
            wait_cycles_ev(this.ev_clk, 1);
            // TODO: register width hard-coded, but at this point the whole 
            // testcase is hard-coded anyways...
            if (if_axi_lite_reg_file_direct_access.axi_ctrl_trigger != 4'b0) begin
                $warning("incorrect trigger deassertion");
                failed++;
            end
            wait_cycles_ev(this.ev_clk, 2);

            // should not cause a write because not mapped in the register 
            // address table
            $display("\twrite axi non-mapped address");
            write_data = 21;
            address = 8'h20;
            this.write("axi", write_data, address);
            // TODO: in theory, for testing that, you would have to register and 
            // then compary the entire register file interface
//             if (if_axi_lite_reg_file_direct_access.if_reg_file_hw.read_data == write_data)
//                 passed++;
//             else
//                 failed++;
            wait_cycles_ev(this.ev_clk, 2);

            $display("\tread axi non-mapped address");
            address = 8'h20;
            this.read("axi", read_data, address);
            if (read_data == 32'b0)
                passed++;
            else begin
                $warning("read axi non-mapped address failed");
                failed++;
            end
            wait_cycles_ev(this.ev_clk, 2);

            $display("\twrite axi memory mappend and trigger on write");
            write_data = 42;
            address = 8'h14;
            axi_done = 1'b0;
            trigger_asserted = 1'b0;
            fork begin  // guarding fork for `disable fork`
                fork
                begin
                    this.write("axi", write_data, address);
                    axi_done = 1'b1;
                end
                begin
                    wait(if_axi_lite_reg_file_direct_access.axi_ctrl_trigger[3]);
                    trigger_asserted = 1'b1;
                end
                join_none

                wait(axi_done);
                disable fork;
            end join

            if (trigger_asserted)
                passed++;
            else
                failed++;
            wait_cycles_ev(this.ev_clk, 1);
            if (if_axi_lite_reg_file_direct_access.axi_ctrl_trigger != 4'b0) begin
                $warning("incorrect trigger deassertion");
                failed++;
            end
            wait_cycles_ev(this.ev_clk, 2);

            $display("\tread axi previous write");
            this.read("axi", read_data, address);
            if (if_axi_lite_reg_file_direct_access.if_reg_file_hw.read_data[3] == write_data)
                passed++;
            else begin
                $warning("read axi previous write failed");
                failed++;
            end
            wait_cycles_ev(this.ev_clk, 2);

            $display("test finished");
//             print_test_result("functionality check", timed_out);
            print_tests_stats(passed, failed);
        endtask

    endclass

endpackage
