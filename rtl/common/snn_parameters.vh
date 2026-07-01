`ifndef SNN_PARAMETERS_VH
`define SNN_PARAMETERS_VH

//---------------------------------------------------------
// Network
//---------------------------------------------------------

`define INPUT_NEURONS        96
`define RECURRENT_NEURONS   120
`define FC_NEURONS           50
`define OUTPUT_NEURONS        5

`define MAX_NEURONS       1024

//---------------------------------------------------------
// Data widths
//---------------------------------------------------------

`define MEM_WIDTH           15
`define WEIGHT_WIDTH         6
`define BIAS_WIDTH           6

`define ADDR_WIDTH          10

//---------------------------------------------------------
// Threshold
//---------------------------------------------------------

`define MEM_THRESHOLD      127

//---------------------------------------------------------
// Time
//---------------------------------------------------------

`define TIME_STEPS           3

`endif
