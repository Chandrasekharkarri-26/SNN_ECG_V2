//-----------------------------------------------------
// Top FSM
//-----------------------------------------------------

`define TOP_IDLE       3'd0
`define TOP_INIT       3'd1
`define TOP_W_ACC      3'd2
`define TOP_V_CALCU    3'd3

//-----------------------------------------------------
// Neuron FSM
//-----------------------------------------------------

`define NFSM_IDLE        4'd0
`define NFSM_INF_LOAD    4'd1
`define NFSM_REG_UPDT    4'd2
`define NFSM_J_ACC       4'd3
`define NFSM_INF_SAVE    4'd4
`define NFSM_V_BIAS      4'd5
`define NFSM_SPIKE       4'd6
`define NFSM_V_LEAK      4'd7
