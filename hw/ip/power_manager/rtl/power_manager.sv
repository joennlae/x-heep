// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

`include "common_cells/assertions.svh"

module power_manager #(
    parameter type reg_req_t = logic,
    parameter type reg_rsp_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // Bus Interface
    input  reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,

    // Power gate signal
    input  logic rv_timer_irq_i,
    input  logic core_sleep_i,
    output logic cpu_subsystem_powergate_switch_o,
    output logic cpu_subsystem_rst_no
);

  import power_manager_reg_pkg::*;

  power_manager_reg2hw_t reg2hw;
  power_manager_hw2reg_t hw2reg;

  assign hw2reg.intr_state.d  = rv_timer_irq_i;
  assign hw2reg.intr_state.de = 1'b1;


  power_manager_reg_top #(
      .reg_req_t(reg_req_t),
      .reg_rsp_t(reg_rsp_t)
  ) power_manager_reg_top_i (
      .clk_i,
      .rst_ni,
      .reg_req_i,
      .reg_rsp_o,
      .reg2hw,
      .hw2reg,
      .devmode_i(1'b1)
  );


  logic cpu_reset_counter_start_switch_off, cpu_reset_counter_expired_switch_off;
  logic cpu_reset_counter_start_switch_on, cpu_reset_counter_expired_switch_on;

  reg_to_counter #(
      .DW(32),
      .ExpireValue('0)
  ) reg_to_counter_cpu_reset_assert_i (
      .clk_i,
      .rst_ni,

      .stop_i (reg2hw.cpu_counters_stop.cpu_reset_assert_stop_bit_counter.q),
      .start_i(cpu_reset_counter_start_switch_off),
      .done_o (cpu_reset_counter_expired_switch_off),

      .hw2reg_d_o (hw2reg.cpu_reset_assert_counter.d),
      .hw2reg_de_o(hw2reg.cpu_reset_assert_counter.de),

      .hw2reg_q_i(reg2hw.cpu_reset_assert_counter.q)

  );

  reg_to_counter #(
      .DW(32),
      .ExpireValue('0)
  ) reg_to_counter_cpu_reset_deassert_i (
      .clk_i,
      .rst_ni,

      .stop_i (reg2hw.cpu_counters_stop.cpu_reset_deassert_stop_bit_counter.q),
      .start_i(cpu_reset_counter_start_switch_on),
      .done_o (cpu_reset_counter_expired_switch_on),

      .hw2reg_d_o (hw2reg.cpu_reset_deassert_counter.d),
      .hw2reg_de_o(hw2reg.cpu_reset_deassert_counter.de),

      .hw2reg_q_i(reg2hw.cpu_reset_deassert_counter.q)

  );

  power_manager_counter_sequence #(
      .ONOFF_AT_RESET(0)
  ) power_manager_counter_sequence_cpu_reset_i (
      .clk_i,
      .rst_ni,

      // trigger to start the sequence
      .start_off_sequence_i(reg2hw.power_gate_core.q && core_sleep_i),
      .start_on_sequence_i (reg2hw.en_wait_for_intr.q && reg2hw.intr_state.q),

      // counter to switch on and off signals
      .counter_expired_switch_off_i(cpu_reset_counter_expired_switch_off),
      .counter_expired_switch_on_i (cpu_reset_counter_expired_switch_on),

      .counter_start_switch_off_o(cpu_reset_counter_start_switch_off),
      .counter_start_switch_on_o (cpu_reset_counter_start_switch_on),

      // switch on and off signal, 1 means on
      .switch_onoff_signal_o(cpu_subsystem_rst_no)
  );


  logic cpu_powergate_counter_start_switch_off, cpu_powergate_counter_expired_switch_off;
  logic cpu_powergate_counter_start_switch_on, cpu_powergate_counter_expired_switch_on;

  reg_to_counter #(
      .DW(32),
      .ExpireValue('0)
  ) reg_to_counter_cpu_powergate_switch_off_i (
      .clk_i,
      .rst_ni,

      .stop_i (reg2hw.cpu_counters_stop.cpu_switch_off_stop_bit_counter.q),
      .start_i(cpu_powergate_counter_start_switch_off),
      .done_o (cpu_powergate_counter_expired_switch_off),

      .hw2reg_d_o (hw2reg.cpu_switch_off_counter.d),
      .hw2reg_de_o(hw2reg.cpu_switch_off_counter.de),

      .hw2reg_q_i(reg2hw.cpu_switch_off_counter.q)

  );

  reg_to_counter #(
      .DW(32),
      .ExpireValue('0)
  ) reg_to_counter_cpu_powergate_switch_on_i (
      .clk_i,
      .rst_ni,

      .stop_i (reg2hw.cpu_counters_stop.cpu_switch_on_stop_bit_counter.q),
      .start_i(cpu_powergate_counter_start_switch_on),
      .done_o (cpu_powergate_counter_expired_switch_on),

      .hw2reg_d_o (hw2reg.cpu_switch_on_counter.d),
      .hw2reg_de_o(hw2reg.cpu_switch_on_counter.de),

      .hw2reg_q_i(reg2hw.cpu_switch_on_counter.q)

  );

  power_manager_counter_sequence power_manager_counter_sequence_cpu_powergate_i (
      .clk_i,
      .rst_ni,

      // trigger to start the sequence
      .start_off_sequence_i(reg2hw.power_gate_core.q && core_sleep_i),
      .start_on_sequence_i (reg2hw.en_wait_for_intr.q && reg2hw.intr_state.q),

      // counter to switch on and off signals
      .counter_expired_switch_off_i(cpu_powergate_counter_expired_switch_off),
      .counter_expired_switch_on_i (cpu_powergate_counter_expired_switch_on),

      .counter_start_switch_off_o(cpu_powergate_counter_start_switch_off),
      .counter_start_switch_on_o (cpu_powergate_counter_start_switch_on),

      // switch on and off signal, 1 means on
      .switch_onoff_signal_o(cpu_subsystem_powergate_switch_o)
  );


endmodule : power_manager
