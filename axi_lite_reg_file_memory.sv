
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
* * INTERFACE:
*		[port name]		- [port description]
* * inputs:
* * outputs:
*/

module axi_lite_reg_file_memory #(
    parameter               DUMMY = 1
) (
    input                   clk,
    input                   rst_n,

    input                   val,
    input                   write_en,

    ifc_reg_file_memory.axi if_reg_file
);

    //----------------------------------------------------------
    // INTERNAL SIGNALS
    //----------------------------------------------------------


    //----------------------------------------------------------
    // OPERATION
    //----------------------------------------------------------

//     always_ff @(posedge clk) begin
//         if (write_en) begin
//             if_reg_file.write_axi(val);
//         end
//     end

    //----------------------------------------------------------
    // SUBMODULES
    //----------------------------------------------------------

endmodule

