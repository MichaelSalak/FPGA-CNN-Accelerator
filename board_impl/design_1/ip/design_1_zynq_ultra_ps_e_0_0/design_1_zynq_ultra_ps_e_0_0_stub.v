// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
// Date        : Fri Nov 27 14:10:06 2026
// Host        : MichaelComputer running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub {c:/Users/moonl/OneDrive/Desktop/School Stuff/Semester 1
//               2026-2027/EC601/Project/FPGA-CNN-Accelerator/board_impl/design_1/ip/design_1_zynq_ultra_ps_e_0_0/design_1_zynq_ultra_ps_e_0_0_stub.v}
// Design      : design_1_zynq_ultra_ps_e_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "zynq_ultra_ps_e_v3_5_3_zynq_ultra_ps_e,Vivado 2024.1" *)
module design_1_zynq_ultra_ps_e_0_0(pl_resetn0, pl_clk0)
/* synthesis syn_black_box black_box_pad_pin="pl_resetn0" */
/* synthesis syn_force_seq_prim="pl_clk0" */;
  output pl_resetn0;
  output pl_clk0 /* synthesis syn_isclock = 1 */;
endmodule
