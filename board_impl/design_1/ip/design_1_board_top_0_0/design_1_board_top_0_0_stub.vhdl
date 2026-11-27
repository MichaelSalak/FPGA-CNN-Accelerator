-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
-- Date        : Fri Nov 27 14:16:46 2026
-- Host        : MichaelComputer running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub {c:/Users/moonl/OneDrive/Desktop/School Stuff/Semester 1
--               2026-2027/EC601/Project/FPGA-CNN-Accelerator/board_impl/design_1/ip/design_1_board_top_0_0/design_1_board_top_0_0_stub.vhdl}
-- Design      : design_1_board_top_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xck26-sfvc784-2LV-c
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity design_1_board_top_0_0 is
  Port ( 
    clk : in STD_LOGIC;
    rst : in STD_LOGIC;
    start : in STD_LOGIC;
    busy : out STD_LOGIC;
    loading : out STD_LOGIC;
    image_loaded : out STD_LOGIC;
    done : out STD_LOGIC;
    error : out STD_LOGIC;
    result : out STD_LOGIC_VECTOR ( 7 downto 0 )
  );

end design_1_board_top_0_0;

architecture stub of design_1_board_top_0_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk,rst,start,busy,loading,image_loaded,done,error,result[7:0]";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "board_top,Vivado 2024.1";
begin
end;
