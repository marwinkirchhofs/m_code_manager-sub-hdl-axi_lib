
package axi_lib_pkg;

    //----------------------------------------------------------
    // PARAMETERS
    //----------------------------------------------------------

    //----------------------------
    // PROTOCOL CONSTANTS
    //----------------------------
    // AXI4_BIT_* bit index in respective signal
    // AXI4_* - bit vector constant
    
    parameter                   AXI4_BURST_FIXED        = 2'b00;
    parameter                   AXI4_BURST_INCR         = 2'b01;
    parameter                   AXI4_BURST_WRAP         = 2'b10;

    parameter                   AXI4_RESP_OKAY          = 2'b00;
    parameter                   AXI4_RESP_EXOKAY        = 2'b01;
    parameter                   AXI4_RESP_SLVERR        = 2'b10;
    parameter                   AXI4_RESP_DECERR        = 2'b11;

    parameter                   AXI4_BIT_CACHE_BUFFER   = 0;
    parameter                   AXI4_BIT_CACHE_MODIFY   = 1;    // CACHE IN AXI3
    parameter                   AXI4_BIT_CACHE_READALLOC    = 2;
    parameter                   AXI4_BIT_CACHE_WRITEALLOC   = 3;

    parameter                   AXI4_BIT_PROT_PRIVIL    = 0;
    parameter                   AXI4_BIT_PROT_SECURE    = 1;
    parameter                   AXI4_BIT_PROT_DATA      = 2;

    localparam                  AXI4_MAX_BURST_LEN      = 256;
    localparam                  AXI3_MAX_BURST_LEN      = 16;

    //----------------------------
    // SIGNAL DEFAULTS
    //----------------------------
    // * some defaults can only be defined as single-bit here although they are 
    // multi-bit, because the signals have dynamic width
    // * *_size cannot be done here because it fully depends on the databus 
    // width

    parameter                   AXI4_DEFAULT_ID         = 1'b0;
    parameter                   AXI4_DEFAULT_REGION     = 4'b0;
    parameter                   AXI4_DEFAULT_LEN        = 8'b0;
    parameter                   AXI4_DEFAULT_BURST      = AXI4_BURST_INCR;
    parameter                   AXI4_DEFAULT_LOCK       = 1'b0;
    parameter                   AXI4_DEFAULT_CACHE      = 4'b0;
    parameter                   AXI4_DEFAULT_QOS        = 4'b0;
    parameter                   AXI4_DEFAULT_STRB       = 1'b1;
    parameter                   AXI4_DEFAULT_BRESP      = AXI4_RESP_OKAY;

    //----------------------------
    // NON-AXI BUS PARAMETERS
    //----------------------------

    parameter                   AXI4_DIR_READ           = 1'b0;
    parameter                   AXI4_DIR_WRITE          = 1'b1;


    //----------------------------------------------------------
    // TYPEDEF
    //----------------------------------------------------------

    // AXI LITE SLAVE

    typedef enum {
        ST_AXI_LITE_READ_READY,
        ST_AXI_LITE_READ_VALID
    } st_axi_lite_read_addr_t;

    typedef enum {
        ST_AXI_LITE_WRITE_READY,
        ST_AXI_LITE_WRITE_VALID,
        ST_AXI_LITE_WRITE_RESP
    } st_axi_lite_write_addr_t;

    // AXI4 MASTER

    typedef enum {
        ST_AXI_MASTER_IDLE,
        ST_AXI_MASTER_BUSY
    } st_axi4_master_t;

    typedef enum {
        ST_AXI_MASTER_ADDR_IDLE,
        ST_AXI_MASTER_ADDR_BUSY
    } st_axi4_master_addr_t;

    typedef enum {
        ST_AXI_MASTER_DATA_IDLE,
        ST_AXI_MASTER_DATA_BUSY,
        ST_AXI_MASTER_DATA_RESP
    } st_axi4_master_data_t;

    typedef struct packed {
        logic [2:0]             burst_size;
        logic [1:0]             burst_type;
        logic [3:0]             cache;
        logic [2:0]             prot;
        logic [3:0]             qos;
        logic [3:0]             region;
        logic                   lock;
    } axi4_status_fields_t;

    // provided for convenience to assign during reset
    // - standard item size in burst is 32 bits
    // - standard protocol information is "unprivileged - secure - data access"
    // - standard qos value is 0
    // - standard region value is 0
    const axi4_status_fields_t AXI4_STATUS_FIELDS_DEFAULTS = {
        3'b101,                 // burst size
        AXI4_DEFAULT_BURST,     // burst type
        AXI4_DEFAULT_CACHE,     // cache
        3'b0,                   // prot
        4'b0,                   // qos
        4'b0,                   // region
        AXI4_DEFAULT_LOCK       // lock
    };

    typedef struct packed {
        logic                   no_rlast;
        logic [1:0]             wresp;
    } axi4_master_msgs_t;

endpackage
