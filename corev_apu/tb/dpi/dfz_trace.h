// Copyright 2026 DeepFlowFuzz contributors.
// SPDX-License-Identifier: Apache-2.0

#ifndef CVA6_DFZ_TRACE_H_
#define CVA6_DFZ_TRACE_H_

#include <cstdint>

extern "C" int v_dfz_trace_init(const char *path);
extern "C" void v_dfz_trace_emit(
    unsigned long long cycle,
    unsigned int core_id,
    unsigned int source_id,
    unsigned int node_id,
    unsigned int record_kind,
    unsigned int lifecycle,
    unsigned int flags,
    unsigned int lane,
    unsigned int slot,
    unsigned int generation,
    unsigned long long front_token,
    unsigned long long pc,
    unsigned int raw_instr,
    unsigned int expanded_instr,
    unsigned int fu,
    unsigned int op,
    unsigned long long data0,
    unsigned long long data1);

// Explicitly called after Verilator executes SystemVerilog final blocks.
// The atexit registration in dfz_trace.cc is a fallback for abnormal paths.
extern "C" void v_dfz_trace_close();

#endif  // CVA6_DFZ_TRACE_H_
