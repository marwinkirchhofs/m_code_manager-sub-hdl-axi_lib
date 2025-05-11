
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
* in case of a write to the same register from both hardware and axi, hardware 
* takes precedence, the software write is ignored (motivated by situations where 
* a clear_on_read from software should be overwritten by hardware, which might 
* have an update to populate).
*
* * INTERFACE:
*		[port name]		- [port description]
* * inputs:
* * outputs:
*/

module axi_lite_reg_file_direct_access #(
    parameter                           AXI_ADDR_WIDTH          = 32,
    parameter                           AXI_DATA_WIDTH          = 32,
    parameter                           AXI_BASE_ADDR           = '0,
    parameter                           REGISTER_WIDTH          = 32,
    parameter                           NUM_REGISTERS           = 16
) (
    input                                   clk,
    input                                   rst_n,

    ifc_axi4_lite.slave                     if_axi_ctrl,
    ifc_reg_file_direct_access.slave        if_reg_file_hw,

    output logic    [NUM_REGISTERS-1:0]     o_axi_ctrl_trigger
);

    localparam                  NUM_REG_FILE_MASTERS = 2;

    //----------------------------------------------------------
    // INTERNAL SIGNALS
    //----------------------------------------------------------

    ifc_reg_file_direct_access #(
        .REGISTER_WIDTH         (REGISTER_WIDTH),
        .NUM_REGISTERS          (NUM_REGISTERS)
    ) if_reg_file_axi (clk);

    ifc_reg_file_direct_access #(
        .REGISTER_WIDTH         (REGISTER_WIDTH),
        .NUM_REGISTERS          (NUM_REGISTERS)
    ) ifs_reg_file_masters [NUM_REG_FILE_MASTERS](clk);


    //----------------------------------------------------------
    // OPERATION
    //----------------------------------------------------------

    // ugly way of "merging" the the hw and axi interfaces into 
    // ifs_reg_file_masters. But passing an actual array during the reg file 
    // instantiation is the only way of not getting any warning, and especially 
    // for verilator (linting) to not straight-up throw an error and abort.
    assign ifs_reg_file_masters[0].write_data   = if_reg_file_hw.write_data;
    assign ifs_reg_file_masters[0].write_mask   = if_reg_file_hw.write_mask;
    assign ifs_reg_file_masters[0].write_req    = if_reg_file_hw.write_req;
    assign if_reg_file_hw.read_data             = ifs_reg_file_masters[0].read_data;
    assign ifs_reg_file_masters[1].write_data   = if_reg_file_axi.write_data;
    assign ifs_reg_file_masters[1].write_mask   = if_reg_file_axi.write_mask;
    assign ifs_reg_file_masters[1].write_req    = if_reg_file_axi.write_req;
    assign if_reg_file_axi.read_data            = ifs_reg_file_masters[1].read_data;


    //----------------------------------------------------------
    // SUBMODULES
    //----------------------------------------------------------

    axi4_lite_reg_slave #(
        .ADDR_WIDTH                     (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH                 (AXI_DATA_WIDTH),
        .AXI_BASE_ADDR                  (AXI_BASE_ADDR),
        .REGISTER_WIDTH                 (REGISTER_WIDTH),
        .NUM_REGISTERS                  (NUM_REGISTERS)
    ) inst_axi4_lite_reg_slave (
        .clk                            (clk),
        .rst_n                          (rst_n),

        .if_axi                         (if_axi_ctrl),
        .if_reg_file                    (if_reg_file_axi),
        .o_write_trigger                (o_axi_ctrl_trigger)
    );

    reg_file_direct_access #(
        .REGISTER_WIDTH                 (REGISTER_WIDTH),
        .NUM_REGISTERS                  (NUM_REGISTERS),
        .NUM_MASTERS                    (NUM_REG_FILE_MASTERS)
    ) inst_reg_file_direct_access (
        .clk                            (clk),
        .rst_n                          (rst_n),
        .ifs_reg_file                   (ifs_reg_file_masters)
    );

endmodule

