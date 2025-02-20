// Copyright 2022 EPFL
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// DMA assume a read request is not granted before previous request rvalid is asserted

module dma #(
    parameter type reg_req_t  = logic,
    parameter type reg_rsp_t  = logic,
    parameter type obi_req_t  = logic,
    parameter type obi_resp_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    input  reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,

    output obi_req_t  dma_master0_ch0_req_o,
    input  obi_resp_t dma_master0_ch0_resp_i,

    output obi_req_t  dma_master1_ch0_req_o,
    input  obi_resp_t dma_master1_ch0_resp_i,

    output dma_intr_o
);

  import dma_reg_pkg::*;

  dma_reg2hw_t        reg2hw;
  dma_hw2reg_t        hw2reg;

  logic        [31:0] read_ptr_reg;
  logic        [31:0] write_ptr_reg;
  logic        [31:0] dma_cnt;
  logic               dma_start;
  logic               dma_done;

  logic               data_in_req;
  logic               data_in_we;
  logic        [ 3:0] data_in_be;
  logic        [31:0] data_in_addr;
  logic               data_in_gnt;
  logic               data_in_rvalid;
  logic        [31:0] data_in_rdata;

  logic               data_out_req;
  logic               data_out_we;
  logic        [ 3:0] data_out_be;
  logic        [31:0] data_out_addr;
  logic        [31:0] data_out_wdata;
  logic               data_out_gnt;
  logic               data_out_rvalid;
  logic        [31:0] data_out_rdata;

  logic               fifo_flush;
  logic               fifo_full;
  logic               fifo_empty;

  enum logic {
    DMA_READ_FSM_IDLE,
    DMA_READ_FSM_ON
  }
      dma_read_fsm_state, dma_read_fsm_n_state;

  enum logic {
    DMA_WRITE_FSM_IDLE,
    DMA_WRITE_FSM_ON
  }
      dma_write_fsm_state, dma_write_fsm_n_state;

  assign dma_master0_ch0_req_o.req = data_in_req;
  assign dma_master0_ch0_req_o.we = data_in_we;
  assign dma_master0_ch0_req_o.be = data_in_be;
  assign dma_master0_ch0_req_o.addr = data_in_addr;
  assign dma_master0_ch0_req_o.wdata = 32'h0;

  assign data_in_gnt = dma_master0_ch0_resp_i.gnt;
  assign data_in_rvalid = dma_master0_ch0_resp_i.rvalid;
  assign data_in_rdata = dma_master0_ch0_resp_i.rdata;

  assign dma_master1_ch0_req_o.req = data_out_req;
  assign dma_master1_ch0_req_o.we = data_out_we;
  assign dma_master1_ch0_req_o.be = data_out_be;
  assign dma_master1_ch0_req_o.addr = data_out_addr;
  assign dma_master1_ch0_req_o.wdata = data_out_wdata;

  assign data_out_gnt = dma_master1_ch0_resp_i.gnt;
  assign data_out_rvalid = dma_master1_ch0_resp_i.rvalid;
  assign data_out_rdata = dma_master1_ch0_resp_i.rdata;

  assign dma_intr_o = dma_done;

  assign hw2reg.done.de = dma_done | dma_start;
  assign hw2reg.done.d = dma_done == 1'b1 ? 1'b1 : 1'b0;

  assign hw2reg.dma_start.de = dma_start;
  assign hw2reg.dma_start.d = 32'h0;

  // DMA pulse start when dma_start register is written
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_dma_start
    if (~rst_ni) begin
      dma_start <= 1'b0;
    end else begin
      if (dma_start == 1'b1) begin
        dma_start <= 1'b0;
      end else begin
        dma_start <= |reg2hw.dma_start.q;
      end
    end
  end

  // Store input data pointer and increment everytime read request is granted
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_ptr_in_reg
    if (~rst_ni) begin
      read_ptr_reg <= '0;
    end else begin
      if (dma_start == 1'b1) begin
        read_ptr_reg <= reg2hw.ptr_in.q;
      end else if (data_in_gnt == 1'b1) begin
        read_ptr_reg <= read_ptr_reg + 32'h4;
      end
    end
  end

  // Store output data pointer and increment everytime write request is granted
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_ptr_out_reg
    if (~rst_ni) begin
      write_ptr_reg <= '0;
    end else begin
      if (dma_start == 1'b1) begin
        write_ptr_reg <= reg2hw.ptr_out.q;
      end else if (data_out_gnt == 1'b1) begin
        write_ptr_reg <= write_ptr_reg + 32'h4;
      end
    end
  end

  // Store dma transfer size and decrement it everytime input data rvalid is asserted
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_dma_cnt_reg
    if (~rst_ni) begin
      dma_cnt <= '0;
    end else begin
      if (dma_start == 1'b1) begin
        dma_cnt <= reg2hw.dma_start.q;
      end else if (data_in_gnt == 1'b1) begin
        dma_cnt <= dma_cnt - 32'h1;
      end
    end
  end

  // FSM state update
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_fsm_state
    if (~rst_ni) begin
      dma_read_fsm_state  <= DMA_READ_FSM_IDLE;
      dma_write_fsm_state <= DMA_WRITE_FSM_IDLE;
    end else begin
      dma_read_fsm_state  <= dma_read_fsm_n_state;
      dma_write_fsm_state <= dma_write_fsm_n_state;
    end
  end

  // Read master FSM
  always_comb begin : proc_dma_read_fsm_logic

    dma_read_fsm_n_state = DMA_READ_FSM_IDLE;

    data_in_req = '0;
    data_in_we = '0;
    data_in_be = '0;
    data_in_addr = '0;

    fifo_flush = 1'b0;

    unique case (dma_read_fsm_state)

      DMA_READ_FSM_IDLE: begin
        // Wait for start signal
        if (dma_start == 1'b1) begin
          dma_read_fsm_n_state = DMA_READ_FSM_ON;
          fifo_flush = 1'b1;
        end else begin
          dma_read_fsm_n_state = DMA_READ_FSM_IDLE;
        end
      end
      // Read one word
      DMA_READ_FSM_ON: begin
        // If all input data read exit
        if (|dma_cnt == 1'b0) begin
          dma_read_fsm_n_state = DMA_READ_FSM_IDLE;
        end else begin
          dma_read_fsm_n_state = DMA_READ_FSM_ON;
          // Wait if fifo is full and
          if (fifo_full == 1'b0) begin
            data_in_req  = 1'b1;
            data_in_we   = 1'b0;
            data_in_be   = 4'b1111;
            data_in_addr = read_ptr_reg;
          end
        end
      end
    endcase
  end

  // Write master FSM
  always_comb begin : proc_dma_write_fsm_logic

    dma_write_fsm_n_state = DMA_WRITE_FSM_IDLE;
    dma_done = 1'b0;

    data_out_req = '0;
    data_out_we = '0;
    data_out_be = '0;
    data_out_addr = '0;

    unique case (dma_write_fsm_state)

      DMA_WRITE_FSM_IDLE: begin
        // Wait for start signal
        if (dma_start == 1'b1) begin
          dma_write_fsm_n_state = DMA_WRITE_FSM_ON;
        end else begin
          dma_write_fsm_n_state = DMA_WRITE_FSM_IDLE;
        end
      end
      // Read one word
      DMA_WRITE_FSM_ON: begin
        // If all input data read exit
        if (fifo_empty == 1'b1 && dma_read_fsm_state == DMA_READ_FSM_IDLE) begin
          dma_write_fsm_n_state = DMA_WRITE_FSM_IDLE;
          dma_done = 1'b1;
        end else begin
          dma_write_fsm_n_state = DMA_WRITE_FSM_ON;
          // Wait if fifo is full and
          if (fifo_empty == 1'b0) begin
            data_out_req  = 1'b1;
            data_out_we   = 1'b1;
            data_out_be   = 4'b1111;
            data_out_addr = write_ptr_reg;
          end
        end
      end
    endcase
  end

  fifo_v3 #(
      .DEPTH(4)
  ) dma_fifo_i (
      .clk_i,
      .rst_ni,
      .flush_i(fifo_flush),
      .testmode_i(1'b0),
      // status flags
      .full_o(fifo_full),
      .empty_o(fifo_empty),
      .usage_o(),
      // as long as the queue is not full we can push new data
      .data_i(data_in_rdata),
      .push_i(data_in_rvalid),
      // as long as the queue is not empty we can pop new elements
      .data_o(data_out_wdata),
      .pop_i(data_out_gnt)
  );

  dma_reg_top #(
      .reg_req_t(reg_req_t),
      .reg_rsp_t(reg_rsp_t)
  ) dma_reg_top_i (
      .clk_i,
      .rst_ni,
      .reg_req_i,
      .reg_rsp_o,
      .reg2hw,
      .hw2reg,
      .devmode_i(1'b1)
  );

endmodule : dma
