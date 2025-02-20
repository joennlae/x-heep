// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

`include "common_cells/assertions.svh"

module soc_ctrl #(
    parameter type reg_req_t = logic,
    parameter type reg_rsp_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // Bus Interface
    input  reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,

    input  logic boot_select_i,
    input  logic execute_from_flash_i,
    output logic use_spimemio_o,

    output logic        exit_valid_o,
    output logic [31:0] exit_value_o
);

  import soc_ctrl_reg_pkg::*;

  soc_ctrl_reg2hw_t reg2hw;
  soc_ctrl_hw2reg_t hw2reg;

  logic testbench_set_exit_loop[1];
  //forced by simlation for preloading, do not touch
  //only arrays can be "forced" in verilator, thus array of 1 element is done
  //At synthesis time this signal will get removed
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_
    if (~rst_ni) begin
      testbench_set_exit_loop[0] <= '0;
    end
  end

  assign hw2reg.boot_select.de = 1'b1;
  assign hw2reg.boot_select.d = boot_select_i;

  assign hw2reg.use_spimemio.de = 1'b1;
  assign hw2reg.use_spimemio.d = execute_from_flash_i;

  assign hw2reg.boot_exit_loop.d = testbench_set_exit_loop[0];
  assign hw2reg.boot_exit_loop.de = testbench_set_exit_loop[0];

  soc_ctrl_reg_top #(
      .reg_req_t(reg_req_t),
      .reg_rsp_t(reg_rsp_t)
  ) soc_ctrl_reg_top_i (
      .clk_i,
      .rst_ni,
      .reg_req_i,
      .reg_rsp_o,
      .reg2hw,
      .hw2reg,
      .devmode_i(1'b1)
  );

  assign exit_valid_o   = reg2hw.exit_valid.q;
  assign exit_value_o   = reg2hw.exit_value.q;
  assign use_spimemio_o = reg2hw.use_spimemio.q;

endmodule : soc_ctrl
