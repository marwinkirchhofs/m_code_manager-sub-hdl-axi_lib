
# DESCRIPTION

AXI4 master that exposes to handshake data interfaces (one for write, one for 
read) and a control interface to the parent core. Designed for high clock 
frequency operation - meaning that for example the core doesn't support address 
and data handshakes in the same cycle, nor does it receive a write response 
during the last write cycle, but only the cycle after.

# FEATURES

## AXI Protocol
* supports
    * incr and fixed bursts
    * narrow transfers
    * parameterizable axi user and id field width
    * abort read at a slave error response (more of a requirement than a feature 
      I guess)
* does not support
    * wrap bursts
    * simultaneous read and write
    * unaligned transfers
    * `rid, ruser, rresp` signal handling (roadmap)

## Other Features
* automatic splitting up of a transaction into separate axi bursts
    * parameterizable maximum total transaction length
* parameterizable data input and output registers
* limited messaging -> reporting transaction status and success

## Not Supported
* transaction parameter checking (e.g., triggering a transaction with 
  `i_num_data_words=0` is undefined behavior up to a stall - to be fixed)

# OPERATION

* all axi transaction parameters (`i_direction, i_num_data_words, 
  i_axi_status_fields, i_base_address, i_axi_user, i_axi_id`) are registered in 
  the trigger cycle (`o_ready & i_trigger`). Therefore any change to these 
  parameters during a transaction has no effect on the ongoing transaction (set 
  of bursts).
* transactions that are longer than the maximum burst length (256 for AXI4) are 
  splitted up in as many bursts as possible of maximum burst length, and then 
  a last shorter burst transmits the remaining data words.
* handshake data streams
    * the interfaces do have a strb lane, but the core currently ignores those. 
      The write axi strb field is determined from the burst parameters, the read 
      strb field is hard-wired to `'1`.
    * the interfaces basically expose the axi data lanes (if in/out registers 
      are deactivated, they directly do). That means that operating the 
      handshake signals needs to obey the axi protocol rules for control signal 
      dependencies. In practice, for the user that should only mean that any 
      ready signal can't wait for the respective valid signal to be asserted. 
      The core takes care of the rest.
    * the core-driven handshake control signals (`write.ready, read.valid`) are 
      handled in a robust way (hopefully) that abstracts from the axi 
      transaction. Therefore, whenever those are asserted, the core is ready to 
      process the respective data transaction regardless of the axi bus 
      operation state - the connected hardware can fully treat it as normal data 
      stream unaware of the backend.
* messaging
    * write response: The messaging struct only has one write response field.  
      this will always be the response of the last burst that has happened.
    * rlast: it is reported if during a read burst the rlast signal was not 
      asserted by the slave during what was expected to be the last data word
    * `i_clear_messages` clears all message fields

# TIPS

* burst type: If you are sure that you are only using one burst type, it might 
  be a good idea to clearly hard-wire the burst type status field input in order 
  to save a little hardware. Gives the tool the chance to optimize out any logic 
  that would apply to a different burst type, because it is unreachable.

# ROADMAP
* wrap bursts
* `rid, ruser, rresp` signal handling (roadmap)
