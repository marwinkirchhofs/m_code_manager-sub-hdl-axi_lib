# xips has to be a list of dictionaries describing xilinx IPs
set xips []

# BRAM
lappend xips [dict create                                                   \
    name                    "xip_bram_axi_test"                             \
    ip_name                 "axi_bram_ctrl"                                 \
    ip_vendor               "xilinx.com"                                    \
    ip_library              "ip"                                            \
    config [dict create                                                     \
        CONFIG.BMG_INSTANCE                     {INTERNAL}                  \
        ]                                                                   \
    ]

