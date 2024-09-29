# DESCRIPTION

Collection of hardware-accessible register files with triggering capabilities 
that expose an additional axi lite interface (thus two access interfaces, one 
for hardware, axi lite presumably for software).  There are two versions: 
*direct_access* and *memory*.  *Direct access* is a set of parallel registers 
that are all readable by the hardware at the same time.  *Memory* is a register 
file that is mapped to a memory, thus every access requires a one-cycle memory 
access and the registers can not be accessed in parallel.  Better for timing 
closure and hardware utilization, because it allows implementation in BRAM, but 
with the obvious access drawback.
Designed for high clock frequency operation (no same-cycle address and data 
handshakes and these kind of things).

**!!! The memory register file is not implemented yet!!!**

Consists of two modules: `axi4_lite_reg_slave` and `reg_file_*` from the 
`mcm_rtl_lib` repository (which `reg_file_*` depends on the register file type).  
For details on these that don't affect the combination of them into an 
axi-driven register file see their respective documentations. The register file 
table definition is documented here.

# FEATURES

* full register file configuration via header files (no necessity to touch the 
  module code)
    * number of registers
    * per register
        * address
        * trigger on write - if a write triggers the respective trigger signal 
          in `o_axi_ctrl_trigger`. always regardless of the value
        * memory-mapped - if a register is actually memory-mapped (refer to 
          *trigger on write*, this way an address can be trigger-only when it 
          does not actually need a register
        * clear on read - if the register is cleared at any read (can be useful 
          for message registers, to know that messages in a subsequent read is 
          new with respect to the information that was just read)
* dual access registers (hardware and software (via axi lite))
* parameterizable multicycle data path from register file to axi read data for 
  clock frequency optimization - see below under operation

## Not Supported

* multiple (different) register files - the reason lies in the configuration via 
  systemverilog header files, see below. The headers are included in the 
  `reg_file_pkg`, which also holds other generic definitions for the register 
  file modules. Thus one would have to somehow duplicate that package, on whose 
  content a great part of the cores relies, or make the header include multiple 
  different register file definitions, name them distinctively, and then handle 
  act on the respective definitions in the different module instances. Possible, 
  in the current state the code is not equipped for that.

# OPERATION

## CONFIGURATION

The configuration requires the user to specify two headers, for which there are 
templates in the `mcm_rtl_lib` repo's `misc` directory. These templates can act 
as a starting point, but in that case the files are to be copied into 
a project's include directory, not to be edited in-place or symlinked.
Formally, the following needs to be present:
* a header file `axi_reg_file_param.svh` which defines the following **compiler 
  macros**:
    * `AXI_LITE_REG_FILE_NUM_REGISTERS` - the number of registers in the 
      register file
    * `AXI_LITE_REG_FILE_AXI_ADDR_WIDTH` - the bitwidth of the register file 
      address space
* a header file `axi_reg_file_table.svh` which describes the register by setting 
  the following parameter:
    * `localparam reg_map_t AXI_LITE_REG_MAP_TABLE = '{...}`
        * `reg_map_t` is defined in `reg_file_pkg.sv` in the `mcm_rtl_lib` repo
        * the file can hold other parameters - it is for example useful to first 
          define the register addresses as local parameters, and afterwards use 
          them in the definition of `AXI_LITE_REG_MAP_TABLE`
        * note that the register addresses that you specify here are offsets to 
          the core's base address. The base address is a simple module 
          parameter.

**Important information on where/how to use those header files**:
* `axi_reg_file_param.svh` is a normal include in `reg_file_pkg.sv`, outside of 
  the package body. Thus you *can* use the header in other places, provided that 
  it has include guards. However, that is discouraged for code consistency. The 
  two macros from the header are assigned to parameters in the package:
  ``localparam <name> = `AXI_LITE_<name>;``. Thus, if for example you want to 
  use `` `AXI_LITE_REG_FILE_NUM_REGISTERS`` in your code, the recommended way is 
  to instead import `REG_FILE_NUM_REGISTERS` from `reg_file_pkg`.
* `axi_reg_file_table.svh` is included **in the package body** of 
  `reg_file_pkg.sv`. Thus it is **highly** encouraged to not include that header 
  anywhere else. Any parameter defined in the header is effectively part of 
  `reg_file_pkg`. Instead of manually including the header, import (from) that 
  package.

## CLOCK FREQUENCY OPTIMIZATION/READ LATENCY

The core has an inherent read latency of two processing cycles between address 
handshake and data valid (first cycle registering address, second cycle fetch 
data from register file). The data fetch path proved to be a critical path in 
clock frequency optimization. The lookup complexity probably also depends on the 
register file size and/or address bitwidth. The second cycle can be extended by 
the parameter `ADD_READ_LATENCY`, which purely delays the read valid signal, but 
but does not touch issuing the data fetch - which allows for a multicycle path 
from register file to axi data of `1+ADD_READ_LATENCY` clock cycles. The 
parameter thus really only denotes the **additional** latency, not the 
1 mandatory cycle of fetching data.

## PARAMETERS

* The core still does have parameters that are set by the register file 
  configuration headers, and thus ultimately by `reg_file_pkg`, like 
  `NUM_REGISTERS`. This is done for flexibility, it is recommended to import 
  `reg_file_pkg` and use the parameters from there to assign to the module 
  instantiation.
* `AXI_ADDR_WIDTH` - actual address width of the axi bus, does not have anything 
  to do with the register file address space size
* `AXI_BASE_ADDR` - (as mentioned earlier) the core's base address on the axi 
  bus, to which the offsets specified in `axi_reg_file_table.svh` are applied

# TIPS


# ROADMAP

* *memory* register file type
* support for multiple register files
