// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

module power_manager_counter_sequence #(
    parameter logic ONOFF_AT_RESET = 1
) (
    input logic clk_i,
    input logic rst_ni,

    // trigger to start the sequence
    input logic start_off_sequence_i,
    input logic start_on_sequence_i,

    // counter to switch on and off signals
    input logic counter_expired_switch_off_i,
    input logic counter_expired_switch_on_i,

    output logic counter_start_switch_off_o,
    output logic counter_start_switch_on_o,

    // switch on and off signal, 1 means on
    output logic switch_onoff_signal_o

);

  typedef enum logic [2:0] {
    RESET,
    IDLE,
    WAIT_SWITCH_OFF_COUNTER,
    SWITCH_OFF,
    WAIT_SWITCH_ON_COUNTER,
    SWITCH_ON
  } sequence_fsm_state;

  sequence_fsm_state sequence_curr_state, sequence_next_state;

  // FSM seq logic
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_
    if (~rst_ni) begin
      sequence_curr_state <= RESET;
    end else begin
      sequence_curr_state <= sequence_next_state;
    end
  end

  // FSM comb logic
  always_comb begin : power_manager_counter_sequence_fsm

    sequence_next_state = sequence_curr_state;
    counter_start_switch_off_o = 1'b0;
    counter_start_switch_on_o = 1'b0;
    switch_onoff_signal_o = ONOFF_AT_RESET;

    unique case (sequence_curr_state)

      RESET: begin
        switch_onoff_signal_o = ONOFF_AT_RESET;
        sequence_next_state   = IDLE;
      end

      IDLE: begin
        switch_onoff_signal_o = 1'b1;
        if (start_off_sequence_i) begin
          counter_start_switch_off_o = 1'b1;
          sequence_next_state = WAIT_SWITCH_OFF_COUNTER;
        end
      end

      WAIT_SWITCH_OFF_COUNTER: begin
        switch_onoff_signal_o = 1'b1;
        sequence_next_state   = counter_expired_switch_off_i ? SWITCH_OFF : WAIT_SWITCH_OFF_COUNTER;
      end

      SWITCH_OFF: begin
        switch_onoff_signal_o = 1'b0;
        if (start_on_sequence_i) begin
          counter_start_switch_on_o = 1'b1;
          sequence_next_state = WAIT_SWITCH_ON_COUNTER;
        end
      end

      WAIT_SWITCH_ON_COUNTER: begin
        switch_onoff_signal_o = 1'b0;
        sequence_next_state   = counter_expired_switch_on_i ? SWITCH_ON : WAIT_SWITCH_ON_COUNTER;
      end

      SWITCH_ON: begin
        switch_onoff_signal_o = 1'b1;
        sequence_next_state   = IDLE;
      end


      default: begin
        sequence_next_state = IDLE;
      end

    endcase

  end

endmodule
