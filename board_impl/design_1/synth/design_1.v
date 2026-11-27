//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
//Date        : Fri Nov 27 16:04:33 2026
//Host        : MichaelComputer running 64-bit major release  (build 9200)
//Command     : generate_target design_1.bd
//Design      : design_1
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "design_1,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=design_1,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=6,numReposBlks=6,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=1,numPkgbdBlks=0,bdsource=USER,synth_mode=Hierarchical}" *) (* HW_HANDOFF = "design_1.hwdef" *) 
module design_1
   ();

  wire board_top_0_busy;
  wire board_top_0_done;
  wire board_top_0_error;
  wire board_top_0_image_loaded;
  wire board_top_0_loading;
  wire [7:0]board_top_0_result;
  wire clk_wiz_0_clk_out1;
  wire clk_wiz_0_locked;
  wire [0:0]proc_sys_reset_0_peripheral_reset;
  wire [0:0]vio_0_probe_out0;
  wire [0:0]vio_0_probe_out1;
  wire [0:0]xlconstant_0_dout;
  wire zynq_ultra_ps_e_0_pl_clk0;
  wire zynq_ultra_ps_e_0_pl_resetn0;

  design_1_board_top_0_0 board_top_0
       (.busy(board_top_0_busy),
        .clk(clk_wiz_0_clk_out1),
        .done(board_top_0_done),
        .error(board_top_0_error),
        .image_loaded(board_top_0_image_loaded),
        .loading(board_top_0_loading),
        .result(board_top_0_result),
        .rst(proc_sys_reset_0_peripheral_reset),
        .start(vio_0_probe_out1));
  design_1_clk_wiz_0_0 clk_wiz_0
       (.clk_in1(zynq_ultra_ps_e_0_pl_clk0),
        .clk_out1(clk_wiz_0_clk_out1),
        .locked(clk_wiz_0_locked),
        .resetn(zynq_ultra_ps_e_0_pl_resetn0));
  design_1_proc_sys_reset_0_0 proc_sys_reset_0
       (.aux_reset_in(vio_0_probe_out0),
        .dcm_locked(clk_wiz_0_locked),
        .ext_reset_in(zynq_ultra_ps_e_0_pl_resetn0),
        .mb_debug_sys_rst(xlconstant_0_dout),
        .peripheral_reset(proc_sys_reset_0_peripheral_reset),
        .slowest_sync_clk(clk_wiz_0_clk_out1));
  design_1_vio_0_0 vio_0
       (.clk(clk_wiz_0_clk_out1),
        .probe_in0(board_top_0_busy),
        .probe_in1(board_top_0_loading),
        .probe_in2(board_top_0_image_loaded),
        .probe_in3(board_top_0_done),
        .probe_in4(board_top_0_error),
        .probe_in5(board_top_0_result),
        .probe_out0(vio_0_probe_out0),
        .probe_out1(vio_0_probe_out1));
  design_1_xlconstant_0_0 xlconstant_0
       (.dout(xlconstant_0_dout));
  design_1_zynq_ultra_ps_e_0_0 zynq_ultra_ps_e_0
       (.pl_clk0(zynq_ultra_ps_e_0_pl_clk0),
        .pl_resetn0(zynq_ultra_ps_e_0_pl_resetn0));
endmodule
