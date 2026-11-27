// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
// Date        : Fri Nov 27 14:16:46 2026
// Host        : MichaelComputer running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub {c:/Users/moonl/OneDrive/Desktop/School Stuff/Semester 1
//               2026-2027/EC601/Project/FPGA-CNN-Accelerator/board_impl/design_1/ip/design_1_board_top_0_0/design_1_board_top_0_0_stub.v}
// Design      : design_1_board_top_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "board_top,Vivado 2024.1" *)
module design_1_board_top_0_0(clk, rst, start, busy, loading, image_loaded, done, 
  error, result)
/* synthesis syn_black_box black_box_pad_pin="rst,start,busy,loading,image_loaded,done,error,result[7:0]" */
/* synthesis syn_force_seq_prim="clk" */;
  input clk /* synthesis syn_isclock = 1 */;
  input rst;
  input start;
  output busy;
  output loading;
  output image_loaded;
  output done;
  output error;
  output [7:0]result;
endmodule
