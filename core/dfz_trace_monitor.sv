// Copyright 2026 DeepFlowFuzz contributors.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Simulation-only dynamic-instruction identity and coarse performing-location
// monitor for CVA6.  This module is compiled only when +define+DFZ_TRACE is
// supplied.  It observes pipeline handshakes and never drives functional RTL.

`ifdef DFZ_TRACE
module dfz_trace_monitor #(
    parameter int unsigned VLEN = 64,
    parameter int unsigned XLEN = 64,
    parameter int unsigned NR_SB_ENTRIES = 8,
    parameter int unsigned NR_WB_PORTS = 5,
    parameter int unsigned NR_COMMIT_PORTS = 2,
    parameter int unsigned TRANS_ID_BITS = 3
) (
    input logic clk_i,
    input logic rst_ni,
    input logic [XLEN-1:0] hart_id_i,

    // Frontend materialization at the realigned IF/ID boundary.
    input logic if_accept_i,
    input logic [VLEN-1:0] if_pc_i,
    input logic [31:0] if_raw_instr_i,
    input logic [31:0] if_expanded_instr_i,
    input logic if_is_rvc_i,
    input logic if_exception_i,

    // Scalar ID resident and scoreboard allocation handshake.
    input logic id_valid_i,
    input logic [3:0] id_fu_i,
    input logic [7:0] id_op_i,
    input logic id_exception_i,
    input logic id_issue_i,
    input logic [TRANS_ID_BITS-1:0] issue_slot_i,
    input logic sb_full_i,
    input logic id_fu_busy_i,
    input logic id_stall_raw_i,
    input logic [2:0] id_operand_stall_i,
    input logic id_accel_stall_i,
    input logic id_cvxif_wait_i,

    // Writeback ports.  A writeback is authoritative only while its slot is
    // still issued; the monitor applies the same guard as scoreboard.sv.
    input logic [NR_WB_PORTS-1:0] wb_valid_i,
    input logic [NR_WB_PORTS-1:0][TRANS_ID_BITS-1:0] wb_slot_i,
    input logic [NR_WB_PORTS-1:0][XLEN-1:0] wb_data_i,
    input logic [NR_WB_PORTS-1:0] wb_exception_i,
    input logic [NR_WB_PORTS-1:0] wb_exception_timing_i,
    input logic [NR_WB_PORTS-1:0][XLEN-1:0] wb_cause_i,

    // Coarse SynthLC-compatible scoreboard performing locations.
    input logic [NR_SB_ENTRIES-1:0] slot_issued_i,
    input logic [NR_SB_ENTRIES-1:0] slot_result_valid_i,
    input logic [NR_SB_ENTRIES-1:0] slot_exception_i,
    input logic [NR_SB_ENTRIES-1:0][VLEN-1:0] slot_pc_i,
    input logic [NR_SB_ENTRIES-1:0][3:0] slot_fu_i,
    input logic [NR_SB_ENTRIES-1:0][7:0] slot_op_i,

    // Scoreboard retirement, trap, and flush termination witnesses.
    input logic [NR_COMMIT_PORTS-1:0] commit_ack_i,
    input logic [NR_COMMIT_PORTS-1:0] commit_drop_i,
    input logic [NR_COMMIT_PORTS-1:0][TRANS_ID_BITS-1:0] commit_slot_i,
    input logic [NR_COMMIT_PORTS-1:0][VLEN-1:0] commit_pc_i,
    input logic [NR_COMMIT_PORTS-1:0][XLEN-1:0] commit_data_i,
    input logic trap_valid_i,
    input logic [TRANS_ID_BITS-1:0] trap_slot_i,
    input logic [VLEN-1:0] trap_pc_i,
    input logic [XLEN-1:0] trap_cause_i,
    input logic [XLEN-1:0] trap_tval_i,
    input logic flush_if_i,
    input logic flush_unissued_i,
    input logic flush_sb_i,
    input logic [31:0] flush_reason_i
);

  // Fixed DPI ABI shared by all CVA6 G0/L1 events.
  import "DPI-C" function int v_dfz_trace_init(input string path);
  import "DPI-C" function void v_dfz_trace_emit(
      input longint unsigned cycle,
      input int unsigned core_id,
      input int unsigned source_id,
      input int unsigned node_id,
      input int unsigned record_kind,
      input int unsigned lifecycle,
      input int unsigned flags,
      input int unsigned lane,
      input int unsigned slot,
      input int unsigned generation,
      input longint unsigned front_token,
      input longint unsigned pc,
      input int unsigned raw_instr,
      input int unsigned expanded_instr,
      input int unsigned fu,
      input int unsigned op,
      input longint unsigned data0,
      input longint unsigned data1
  );

  // Sources.
  localparam int unsigned SRC_FRONTEND  = 1;
  localparam int unsigned SRC_ISSUE     = 2;
  localparam int unsigned SRC_SCOREBOARD = 3;
  localparam int unsigned SRC_EXECUTE   = 4;
  localparam int unsigned SRC_COMMIT    = 5;
  localparam int unsigned SRC_CONTROL   = 6;

  // Record kinds and lifecycle semantics.
  localparam int unsigned KIND_EVENT  = 1;
  localparam int unsigned KIND_PL     = 2;
  localparam int unsigned KIND_ACTION = 3;
  localparam int unsigned LIFE_POINT    = 1;
  localparam int unsigned LIFE_VISIT    = 2;
  localparam int unsigned LIFE_TERMINAL = 3;
  localparam int unsigned LIFE_CENSORED = 4;

  // Event/action nodes.
  localparam int unsigned EVT_IF_ID_ACCEPT    = 1;
  localparam int unsigned EVT_ID_KILL         = 2;
  localparam int unsigned EVT_FU_RESPONSE     = 4;
  localparam int unsigned EVT_COMMIT          = 5;
  localparam int unsigned EVT_TRAP            = 6;
  localparam int unsigned EVT_FLUSH_KILL      = 7;
  localparam int unsigned EVT_CENSORED        = 8;
  localparam int unsigned EVT_COMMIT_DROP     = 9;
  localparam int unsigned EVT_PIPELINE_FLUSH  = 10;
  localparam int unsigned EVT_PIPELINE_RESET  = 11;
  localparam int unsigned ACT_ISSUE_TO_FU     = 200;

  // Coarse performing locations.  The scoreboard states directly preserve
  // the original SynthLC split on issued/result-valid/exception-valid.
  localparam int unsigned PL_ID_RESIDENT      = 99;
  localparam int unsigned PL_ID_WAIT_SB_FULL  = 100;
  localparam int unsigned PL_ID_WAIT_FU       = 101;
  localparam int unsigned PL_ID_WAIT_RAW      = 102;
  localparam int unsigned PL_ID_WAIT_CVXIF    = 103;
  localparam int unsigned PL_ID_WAIT_ACCEL    = 104;
  localparam int unsigned PL_ID_WAIT_OTHER    = 105;
  localparam int unsigned PL_SB_WAIT_RESULT   = 110;
  localparam int unsigned PL_SB_WAIT_COMMIT   = 111;
  localparam int unsigned PL_SB_EXCEPTION_WAIT = 112;

  // Optional-field validity flags.  Values are authoritative only when the
  // corresponding bit is set, even if a field happens to be non-zero.
  localparam int unsigned FLAG_FRONT_TOKEN = 32'h0000_0001;
  localparam int unsigned FLAG_SLOT        = 32'h0000_0002;
  localparam int unsigned FLAG_PC          = 32'h0000_0004;
  localparam int unsigned FLAG_RAW_INSTR   = 32'h0000_0008;
  localparam int unsigned FLAG_EXPANDED    = 32'h0000_0010;
  localparam int unsigned FLAG_FU          = 32'h0000_0020;
  localparam int unsigned FLAG_OP          = 32'h0000_0040;
  localparam int unsigned FLAG_EXCEPTION   = 32'h0000_0080;
  localparam int unsigned FLAG_DROP        = 32'h0000_0100;
  localparam int unsigned FLAG_RVC         = 32'h0000_0200;

  localparam int unsigned NO_LANE = 32'hffff_ffff;
  localparam int unsigned NO_SLOT = 32'hffff_ffff;
  localparam logic [31:0] RESET_REASON = 32'h8000_0000;

  bit trace_enabled;
  bit identity_initialized;
  bit reset_episode_reported;
  string trace_path;

  logic [63:0] cycle_q;
  logic [63:0] next_front_token_q;

  // Trace-only identity state for the scalar ID resident.
  logic [63:0] id_token_q;
  logic [VLEN-1:0] id_pc_q;
  logic [31:0] id_raw_q;
  logic [31:0] id_expanded_q;
  logic id_rvc_q;

  // Trace-only backend lineage.  generation never resets on a pipeline flush;
  // it increments on every physical scoreboard-slot lifetime.
  logic [NR_SB_ENTRIES-1:0][63:0] slot_token_q;
  logic [NR_SB_ENTRIES-1:0][31:0] slot_generation_q;
  logic [NR_SB_ENTRIES-1:0][31:0] slot_raw_q;
  logic [NR_SB_ENTRIES-1:0][31:0] slot_expanded_q;
  logic [NR_SB_ENTRIES-1:0] slot_rvc_q;

  function automatic logic [63:0] pc64(input logic [VLEN-1:0] pc);
    pc64 = $unsigned(pc);
  endfunction

  function automatic logic [63:0] xlen64(input logic [XLEN-1:0] value);
    xlen64 = $unsigned(value);
  endfunction

  function automatic logic slot_committed_this_edge(
      input logic [TRANS_ID_BITS-1:0] slot
  );
    slot_committed_this_edge = 1'b0;
    for (int unsigned c = 0; c < NR_COMMIT_PORTS; c++) begin
      slot_committed_this_edge |= commit_ack_i[c] && (commit_slot_i[c] == slot);
    end
  endfunction

  task automatic emit_record(
      input int unsigned source_id,
      input int unsigned node_id,
      input int unsigned record_kind,
      input int unsigned lifecycle,
      input int unsigned flags,
      input int unsigned lane,
      input int unsigned slot,
      input int unsigned generation,
      input logic [63:0] front_token,
      input logic [63:0] pc,
      input logic [31:0] raw_instr,
      input logic [31:0] expanded_instr,
      input int unsigned fu,
      input int unsigned op,
      input logic [63:0] data0,
      input logic [63:0] data1
  );
    if (trace_enabled) begin
      v_dfz_trace_emit(
          cycle_q, hart_id_i[31:0], source_id, node_id, record_kind, lifecycle,
          flags, lane, slot, generation, front_token, pc, raw_instr,
          expanded_instr, fu, op, data0, data1
      );
    end
  endtask

  initial begin
    trace_enabled = 1'b0;
    if ($value$plusargs("dfz_trace_file=%s", trace_path)) begin
      trace_enabled = (v_dfz_trace_init(trace_path) != 0);
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_dfz_trace
    if (!rst_ni) begin
      // A later episode reset must close all visible lifetimes before their
      // trace-only resident state is cleared.  Token and generation counters
      // intentionally remain monotonic across those resets.
      if (!reset_episode_reported && identity_initialized && trace_enabled) begin
        if (id_token_q != 0) begin
          emit_record(
              SRC_CONTROL, EVT_ID_KILL, KIND_EVENT, LIFE_TERMINAL,
              FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                  FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0),
              0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
              id_expanded_q, id_fu_i, id_op_i, RESET_REASON, 0
          );
        end
        for (int unsigned s = 0; s < NR_SB_ENTRIES; s++) begin
          if (slot_token_q[s] != 0) begin
            emit_record(
                SRC_CONTROL, EVT_FLUSH_KILL, KIND_EVENT, LIFE_TERMINAL,
                FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                    FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                    (slot_rvc_q[s] ? FLAG_RVC : 0),
                NO_LANE, s, slot_generation_q[s], slot_token_q[s],
                pc64(slot_pc_i[s]), slot_raw_q[s], slot_expanded_q[s],
                slot_fu_i[s], slot_op_i[s], RESET_REASON, 0
            );
          end
        end
        emit_record(
            SRC_CONTROL, EVT_PIPELINE_RESET, KIND_EVENT, LIFE_POINT,
            0, NO_LANE, NO_SLOT, 0, 0, 0, 0, 0, 0, 0, RESET_REASON, 0
        );
      end
      reset_episode_reported <= 1'b1;
      if (!identity_initialized) begin
        cycle_q             <= '0;
        next_front_token_q  <= 64'd1;
        slot_generation_q   <= '0;
        identity_initialized <= 1'b1;
      end
      id_token_q         <= '0;
      id_pc_q            <= '0;
      id_raw_q           <= '0;
      id_expanded_q      <= '0;
      id_rvc_q           <= 1'b0;
      slot_token_q       <= '0;
      slot_raw_q         <= '0;
      slot_expanded_q    <= '0;
      slot_rvc_q         <= '0;
    end else begin
      reset_episode_reported <= 1'b0;

      // The scalar ID resident emits one coarse residency visit, zero or more
      // concurrent wait witnesses, and at most one action/terminal per cycle.
      if (id_valid_i && id_token_q != 0) begin
        // Coarse frontend PL: every ID resident gets one visit per cycle.
        // data0[4:0]={cvxif,accelerator,raw,fu_busy,sb_full};
        // data0[7:5]={rs3,rs2,rs1}.
        emit_record(
            SRC_ISSUE, PL_ID_RESIDENT, KIND_PL, LIFE_VISIT,
            FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0) |
                (id_exception_i ? FLAG_EXCEPTION : 0),
            0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
            id_expanded_q, id_fu_i, id_op_i,
            {
              56'b0, id_operand_stall_i, id_cvxif_wait_i, id_accel_stall_i,
              (id_stall_raw_i && !id_accel_stall_i), id_fu_busy_i, sb_full_i
            },
            0
        );
        if (flush_if_i || flush_unissued_i) begin
          emit_record(
              SRC_FRONTEND, EVT_ID_KILL, KIND_EVENT, LIFE_TERMINAL,
              FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                  FLAG_FU | FLAG_OP |
                  (id_rvc_q ? FLAG_RVC : 0) |
                  (id_exception_i ? FLAG_EXCEPTION : 0),
              0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
              id_expanded_q, id_fu_i, id_op_i, flush_reason_i, 0
          );
        end else if (id_issue_i) begin
          emit_record(
              SRC_ISSUE, ACT_ISSUE_TO_FU, KIND_ACTION, LIFE_POINT,
              FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                  FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                  (id_rvc_q ? FLAG_RVC : 0) |
                  (id_exception_i ? FLAG_EXCEPTION : 0),
              0, issue_slot_i, slot_generation_q[issue_slot_i] + 1,
              id_token_q, pc64(id_pc_q), id_raw_q, id_expanded_q,
              id_fu_i, id_op_i, 0, 0
          );
        end else begin
          if (sb_full_i) begin
            emit_record(
                SRC_ISSUE, PL_ID_WAIT_SB_FULL, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                    FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0),
                0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
                id_expanded_q, id_fu_i, id_op_i, 0, 0
            );
          end
          if (id_fu_busy_i) begin
            emit_record(
                SRC_ISSUE, PL_ID_WAIT_FU, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                    FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0),
                0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
                id_expanded_q, id_fu_i, id_op_i, 0, 0
            );
          end
          if (id_accel_stall_i) begin
            emit_record(
                SRC_ISSUE, PL_ID_WAIT_ACCEL, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                    FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0),
                0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
                id_expanded_q, id_fu_i, id_op_i, 0, 0
            );
          end
          if (id_stall_raw_i && !id_accel_stall_i) begin
            emit_record(
                SRC_ISSUE, PL_ID_WAIT_RAW, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                    FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0),
                0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
                id_expanded_q, id_fu_i, id_op_i,
                {61'b0, id_operand_stall_i}, 0
            );
          end
          if (id_cvxif_wait_i) begin
            emit_record(
                SRC_ISSUE, PL_ID_WAIT_CVXIF, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                    FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0),
                0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
                id_expanded_q, id_fu_i, id_op_i, 0, 0
            );
          end
          if (!(sb_full_i || id_fu_busy_i || id_accel_stall_i ||
                (id_stall_raw_i && !id_accel_stall_i) || id_cvxif_wait_i)) begin
            emit_record(
                SRC_ISSUE, PL_ID_WAIT_OTHER, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                    FLAG_FU | FLAG_OP | (id_rvc_q ? FLAG_RVC : 0),
                0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
                id_expanded_q, id_fu_i, id_op_i, 0, 0
            );
          end
        end
      end
      if (id_issue_i && id_token_q == 0) begin
        $error("DFZ identity invariant: scoreboard allocation without frontend token");
      end

      // Per-cycle backend performing locations, using the same three state
      // predicates as the original SynthLC scoreboard annotations.
      for (int unsigned s = 0; s < NR_SB_ENTRIES; s++) begin
        if (slot_issued_i[s] && slot_token_q[s] != 0) begin
          if (!slot_result_valid_i[s]) begin
            emit_record(
                SRC_SCOREBOARD, PL_SB_WAIT_RESULT, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                    FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                    (slot_rvc_q[s] ? FLAG_RVC : 0),
                NO_LANE, s, slot_generation_q[s], slot_token_q[s],
                pc64(slot_pc_i[s]), slot_raw_q[s], slot_expanded_q[s],
                slot_fu_i[s], slot_op_i[s], 0, 0
            );
          end else if (slot_exception_i[s]) begin
            emit_record(
                SRC_SCOREBOARD, PL_SB_EXCEPTION_WAIT, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                    FLAG_EXPANDED | FLAG_FU | FLAG_OP | FLAG_EXCEPTION |
                    (slot_rvc_q[s] ? FLAG_RVC : 0),
                NO_LANE, s, slot_generation_q[s], slot_token_q[s],
                pc64(slot_pc_i[s]), slot_raw_q[s], slot_expanded_q[s],
                slot_fu_i[s], slot_op_i[s], 0, 0
            );
          end else begin
            emit_record(
                SRC_SCOREBOARD, PL_SB_WAIT_COMMIT, KIND_PL, LIFE_VISIT,
                FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                    FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                    (slot_rvc_q[s] ? FLAG_RVC : 0),
                NO_LANE, s, slot_generation_q[s], slot_token_q[s],
                pc64(slot_pc_i[s]), slot_raw_q[s], slot_expanded_q[s],
                slot_fu_i[s], slot_op_i[s], 0, 0
            );
          end
        end
      end

      // Functional-unit completion.  Ignore stale responses after a flush.
      for (int unsigned w = 0; w < NR_WB_PORTS; w++) begin
        if (wb_valid_i[w] && slot_issued_i[wb_slot_i[w]] &&
            slot_token_q[wb_slot_i[w]] != 0) begin
          emit_record(
              SRC_EXECUTE, EVT_FU_RESPONSE, KIND_EVENT, LIFE_POINT,
              FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                  FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                  (slot_rvc_q[wb_slot_i[w]] ? FLAG_RVC : 0) |
                  ((wb_exception_i[w] || wb_exception_timing_i[w]) ?
                      FLAG_EXCEPTION : 0),
              w, wb_slot_i[w], slot_generation_q[wb_slot_i[w]],
              slot_token_q[wb_slot_i[w]], pc64(slot_pc_i[wb_slot_i[w]]),
              slot_raw_q[wb_slot_i[w]], slot_expanded_q[wb_slot_i[w]],
              slot_fu_i[wb_slot_i[w]], slot_op_i[wb_slot_i[w]],
              xlen64(wb_data_i[w]), xlen64(wb_cause_i[w])
          );
        end
      end

      // Retirement/drop terminals.  commit_ack_i is the actual scoreboard
      // acknowledge, not the RVFI-filtered top-level commit pulse.
      for (int unsigned c = 0; c < NR_COMMIT_PORTS; c++) begin
        if (commit_ack_i[c] && slot_token_q[commit_slot_i[c]] != 0) begin
          emit_record(
              SRC_COMMIT, commit_drop_i[c] ? EVT_COMMIT_DROP : EVT_COMMIT,
              KIND_EVENT, LIFE_TERMINAL,
              FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                  FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                  (slot_rvc_q[commit_slot_i[c]] ? FLAG_RVC : 0) |
                  (commit_drop_i[c] ? FLAG_DROP : 0),
              c, commit_slot_i[c], slot_generation_q[commit_slot_i[c]],
              slot_token_q[commit_slot_i[c]], pc64(commit_pc_i[c]),
              slot_raw_q[commit_slot_i[c]], slot_expanded_q[commit_slot_i[c]],
              slot_fu_i[commit_slot_i[c]], slot_op_i[commit_slot_i[c]],
              xlen64(commit_data_i[c]), 0
          );
        end
      end

      // A synchronous exception normally has no commit acknowledge.  The
      // exception owner therefore needs its own terminal before full flush.
      if (trap_valid_i && !slot_committed_this_edge(trap_slot_i) &&
          slot_token_q[trap_slot_i] != 0) begin
        emit_record(
            SRC_COMMIT, EVT_TRAP, KIND_EVENT, LIFE_TERMINAL,
            FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                FLAG_EXPANDED | FLAG_FU | FLAG_OP | FLAG_EXCEPTION |
                (slot_rvc_q[trap_slot_i] ? FLAG_RVC : 0),
            0, trap_slot_i, slot_generation_q[trap_slot_i],
            slot_token_q[trap_slot_i], pc64(trap_pc_i),
            slot_raw_q[trap_slot_i], slot_expanded_q[trap_slot_i],
            slot_fu_i[trap_slot_i], slot_op_i[trap_slot_i],
            xlen64(trap_cause_i), xlen64(trap_tval_i)
        );
      end

      if (flush_if_i || flush_unissued_i || flush_sb_i) begin
        emit_record(
            SRC_CONTROL, EVT_PIPELINE_FLUSH, KIND_EVENT, LIFE_POINT,
            0, NO_LANE, NO_SLOT, 0, 0, 0, 0, 0, 0, 0,
            flush_reason_i, {61'b0, flush_sb_i, flush_unissued_i, flush_if_i}
        );
      end

      // Full-scoreboard flush kills every old active owner except an owner
      // already terminated by commit/drop or trap on this edge.
      if (flush_sb_i) begin
        for (int unsigned s = 0; s < NR_SB_ENTRIES; s++) begin
          logic committed_this_edge;
          committed_this_edge = 1'b0;
          for (int unsigned c = 0; c < NR_COMMIT_PORTS; c++) begin
            committed_this_edge |= commit_ack_i[c] && (commit_slot_i[c] == s);
          end
          if (slot_issued_i[s] && slot_token_q[s] != 0 &&
              !committed_this_edge && !(trap_valid_i && trap_slot_i == s)) begin
            emit_record(
                SRC_CONTROL, EVT_FLUSH_KILL, KIND_EVENT, LIFE_TERMINAL,
                FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                    FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                    (slot_rvc_q[s] ? FLAG_RVC : 0),
                NO_LANE, s, slot_generation_q[s], slot_token_q[s],
                pc64(slot_pc_i[s]), slot_raw_q[s], slot_expanded_q[s],
                slot_fu_i[s], slot_op_i[s], flush_reason_i, 0
            );
          end
        end
      end

      // The new frontend token is born last semantically on a fall-through
      // edge where the old ID resident issues and a new instruction arrives.
      if (if_accept_i) begin
        emit_record(
            SRC_FRONTEND, EVT_IF_ID_ACCEPT, KIND_EVENT, LIFE_POINT,
            FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                (if_is_rvc_i ? FLAG_RVC : 0) |
                (if_exception_i ? FLAG_EXCEPTION : 0),
            0, NO_SLOT, 0, next_front_token_q, pc64(if_pc_i),
            if_raw_instr_i, if_expanded_instr_i, 0, 0, 0, 0
        );
      end

      // Trace-only identity state update.  Ordering mirrors ID/scoreboard:
      // allocation, terminal retirement, then full flush (last assignment wins).
      if (flush_if_i || flush_unissued_i) begin
        id_token_q <= '0;
      end else begin
        if (id_issue_i) id_token_q <= '0;
        if (if_accept_i) begin
          id_token_q    <= next_front_token_q;
          id_pc_q       <= if_pc_i;
          id_raw_q      <= if_raw_instr_i;
          id_expanded_q <= if_expanded_instr_i;
          id_rvc_q      <= if_is_rvc_i;
        end
      end

      if (if_accept_i) next_front_token_q <= next_front_token_q + 1;

      if (id_issue_i && id_token_q != 0) begin
        slot_token_q[issue_slot_i]      <= id_token_q;
        slot_generation_q[issue_slot_i] <= slot_generation_q[issue_slot_i] + 1;
        slot_raw_q[issue_slot_i]        <= id_raw_q;
        slot_expanded_q[issue_slot_i]   <= id_expanded_q;
        slot_rvc_q[issue_slot_i]        <= id_rvc_q;
      end
      for (int unsigned c = 0; c < NR_COMMIT_PORTS; c++) begin
        if (commit_ack_i[c]) slot_token_q[commit_slot_i[c]] <= '0;
      end
      if (trap_valid_i && !slot_committed_this_edge(trap_slot_i))
        slot_token_q[trap_slot_i] <= '0;
      if (flush_sb_i) slot_token_q <= '0;

      cycle_q <= cycle_q + 1;
    end
  end

  // Positive end-of-observation evidence: an unfinished resident is
  // CENSORED, not guessed to be killed or committed by the host writer.
  final begin : p_dfz_final
    if (trace_enabled) begin
      if (id_valid_i && id_token_q != 0) begin
        emit_record(
            SRC_FRONTEND, EVT_CENSORED, KIND_EVENT, LIFE_CENSORED,
            FLAG_FRONT_TOKEN | FLAG_PC | FLAG_RAW_INSTR | FLAG_EXPANDED |
                FLAG_FU | FLAG_OP |
                (id_rvc_q ? FLAG_RVC : 0),
            0, NO_SLOT, 0, id_token_q, pc64(id_pc_q), id_raw_q,
            id_expanded_q, id_fu_i, id_op_i, 0, 0
        );
      end
      for (int unsigned s = 0; s < NR_SB_ENTRIES; s++) begin
        if (slot_issued_i[s] && slot_token_q[s] != 0) begin
          emit_record(
              SRC_SCOREBOARD, EVT_CENSORED, KIND_EVENT, LIFE_CENSORED,
              FLAG_FRONT_TOKEN | FLAG_SLOT | FLAG_PC | FLAG_RAW_INSTR |
                  FLAG_EXPANDED | FLAG_FU | FLAG_OP |
                  (slot_rvc_q[s] ? FLAG_RVC : 0),
              NO_LANE, s, slot_generation_q[s], slot_token_q[s],
              pc64(slot_pc_i[s]), slot_raw_q[s], slot_expanded_q[s],
              slot_fu_i[s], slot_op_i[s], 0, 0
          );
        end
      end
    end
  end

endmodule
`endif  // DFZ_TRACE
