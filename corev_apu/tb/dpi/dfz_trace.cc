// Copyright 2026 DeepFlowFuzz contributors.
// SPDX-License-Identifier: Apache-2.0

#include "dfz_trace.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>

namespace {

constexpr unsigned int kSchemaVersion = 1;
constexpr unsigned long long kFlushInterval = 4096;

constexpr unsigned int kFlagFrontToken = 0x00000001U;
constexpr unsigned int kFlagSlot = 0x00000002U;
constexpr unsigned int kFlagPc = 0x00000004U;
constexpr unsigned int kFlagRawInstr = 0x00000008U;
constexpr unsigned int kFlagExpanded = 0x00000010U;
constexpr unsigned int kFlagFu = 0x00000020U;
constexpr unsigned int kFlagOp = 0x00000040U;
constexpr unsigned int kFlagException = 0x00000080U;
constexpr unsigned int kFlagDrop = 0x00000100U;
constexpr unsigned int kFlagRvc = 0x00000200U;

constexpr unsigned int kEvtIfIdAccept = 1;
constexpr unsigned int kEvtIdKill = 2;
constexpr unsigned int kEvtFuResponse = 4;
constexpr unsigned int kEvtCommit = 5;
constexpr unsigned int kEvtTrap = 6;
constexpr unsigned int kEvtFlushKill = 7;
constexpr unsigned int kEvtCensored = 8;
constexpr unsigned int kEvtCommitDrop = 9;
constexpr unsigned int kEvtPipelineFlush = 10;
constexpr unsigned int kEvtPipelineReset = 11;
constexpr unsigned int kActIssueToFu = 200;

std::mutex trace_mutex;
FILE *trace_file = nullptr;
std::string trace_filename;
unsigned long long trace_records = 0;
unsigned long long identity_errors = 0;
unsigned long long next_inst_uid = 1;
bool close_registered = false;

struct TokenKey {
  unsigned int core_id;
  unsigned long long token;

  bool operator==(const TokenKey &other) const {
    return core_id == other.core_id && token == other.token;
  }
};

struct TokenKeyHash {
  std::size_t operator()(const TokenKey &key) const {
    const auto a = std::hash<unsigned int>{}(key.core_id);
    const auto b = std::hash<unsigned long long>{}(key.token);
    return a ^ (b + 0x9e3779b9U + (a << 6) + (a >> 2));
  }
};

struct SlotKey {
  unsigned int core_id;
  unsigned int slot;

  bool operator==(const SlotKey &other) const {
    return core_id == other.core_id && slot == other.slot;
  }
};

struct SlotKeyHash {
  std::size_t operator()(const SlotKey &key) const {
    return (static_cast<std::size_t>(key.core_id) << 16) ^ key.slot;
  }
};

struct SlotOwner {
  unsigned long long token;
  unsigned long long inst_uid;
  unsigned int generation;
};

std::unordered_map<TokenKey, unsigned long long, TokenKeyHash> uid_by_token;
std::unordered_set<TokenKey, TokenKeyHash> terminal_tokens;
std::unordered_map<SlotKey, SlotOwner, SlotKeyHash> owner_by_slot;
std::unordered_map<SlotKey, unsigned int, SlotKeyHash> last_generation;

struct IdentityResult {
  unsigned long long inst_uid = 0;
  std::string status = "OK";
};

void add_status(IdentityResult &result, const char *status) {
  if (result.status == "OK") {
    result.status = status;
  } else {
    result.status += "+";
    result.status += status;
  }
  identity_errors++;
}

bool has_flag(unsigned int flags, unsigned int flag) {
  return (flags & flag) != 0U;
}

bool is_slot_node(unsigned int node_id) {
  return node_id == kActIssueToFu ||
         (node_id >= 110U && node_id <= 112U) ||
         node_id == kEvtFuResponse || node_id == kEvtCommit ||
         node_id == kEvtTrap || node_id == kEvtFlushKill ||
         node_id == kEvtCommitDrop;
}

bool is_terminal_node(unsigned int node_id) {
  return node_id == kEvtIdKill || node_id == kEvtCommit ||
         node_id == kEvtTrap || node_id == kEvtFlushKill ||
         node_id == kEvtCommitDrop;
}

unsigned int semantic_rank(unsigned int node_id) {
  if (node_id == 99U || (node_id >= 100U && node_id <= 105U)) return 20;
  if (node_id == kActIssueToFu) return 30;
  if (node_id >= 110U && node_id <= 112U) return 40;
  if (node_id == kEvtFuResponse) return 50;
  if (node_id == kEvtCommit || node_id == kEvtCommitDrop) return 60;
  if (node_id == kEvtTrap) return 61;
  if (node_id == kEvtPipelineFlush) return 70;
  if (node_id == kEvtIdKill || node_id == kEvtFlushKill) return 71;
  if (node_id == kEvtPipelineReset) return 72;
  if (node_id == kEvtIfIdAccept) return 80;
  if (node_id == kEvtCensored) return 90;
  return 80;
}

const char *source_name(unsigned int source_id) {
  switch (source_id) {
    case 1: return "FRONTEND";
    case 2: return "ISSUE";
    case 3: return "SCOREBOARD";
    case 4: return "EXECUTE";
    case 5: return "COMMIT";
    case 6: return "CONTROL";
    default: return "UNKNOWN";
  }
}

const char *kind_name(unsigned int kind) {
  switch (kind) {
    case 1: return "EVENT";
    case 2: return "PL";
    case 3: return "ACTION";
    default: return "UNKNOWN";
  }
}

const char *lifecycle_name(unsigned int lifecycle) {
  switch (lifecycle) {
    case 1: return "POINT";
    case 2: return "VISIT";
    case 3: return "TERMINAL";
    case 4: return "CENSORED";
    default: return "UNKNOWN";
  }
}

const char *node_name(unsigned int node_id) {
  switch (node_id) {
    case 1: return "EVT_IF_ID_ACCEPT";
    case 2: return "EVT_ID_KILL";
    case 4: return "EVT_FU_RESPONSE";
    case 5: return "EVT_COMMIT";
    case 6: return "EVT_TRAP";
    case 7: return "EVT_FLUSH_KILL";
    case 8: return "EVT_CENSORED";
    case 9: return "EVT_COMMIT_DROP";
    case 10: return "EVT_PIPELINE_FLUSH";
    case 11: return "EVT_PIPELINE_RESET";
    case 99: return "PL_ID_RESIDENT";
    case 100: return "PL_ID_WAIT_SB_FULL";
    case 101: return "PL_ID_WAIT_FU";
    case 102: return "PL_ID_WAIT_RAW";
    case 103: return "PL_ID_WAIT_CVXIF";
    case 104: return "PL_ID_WAIT_ACCEL";
    case 105: return "PL_ID_WAIT_OTHER";
    case 110: return "PL_SB_WAIT_RESULT";
    case 111: return "PL_SB_WAIT_COMMIT";
    case 112: return "PL_SB_EXCEPTION_WAIT";
    case 200: return "ACT_ISSUE_TO_FU";
    default: return "UNKNOWN";
  }
}

unsigned long long resolve_token(
    unsigned int core_id,
    unsigned long long token,
    IdentityResult &result) {
  if (token == 0) {
    add_status(result, "ZERO_FRONT_TOKEN");
    return 0;
  }
  const auto it = uid_by_token.find(TokenKey{core_id, token});
  if (it == uid_by_token.end()) {
    add_status(result, "NO_FRONT_PARENT");
    return 0;
  }
  result.inst_uid = it->second;
  return result.inst_uid;
}

IdentityResult monitor_identity(
    unsigned int core_id,
    unsigned int node_id,
    unsigned int flags,
    unsigned int slot,
    unsigned int generation,
    unsigned long long front_token) {
  IdentityResult result;
  const TokenKey token_key{core_id, front_token};
  const SlotKey slot_key{core_id, slot};

  if (node_id == kEvtIfIdAccept) {
    if (!has_flag(flags, kFlagFrontToken) || front_token == 0) {
      add_status(result, "BIRTH_WITHOUT_TOKEN");
      return result;
    }
    const auto old = uid_by_token.find(token_key);
    if (old != uid_by_token.end()) {
      result.inst_uid = old->second;
      add_status(result, "DUP_FRONT_TOKEN");
    } else {
      result.inst_uid = next_inst_uid++;
      uid_by_token.emplace(token_key, result.inst_uid);
    }
    return result;
  }

  if (has_flag(flags, kFlagFrontToken)) {
    resolve_token(core_id, front_token, result);
  }

  if (node_id == kActIssueToFu) {
    bool install_owner = true;
    if (!has_flag(flags, kFlagFrontToken)) {
      add_status(result, "ISSUE_WITHOUT_FRONT_TOKEN");
      install_owner = false;
    } else if (result.inst_uid == 0) {
      install_owner = false;
    }
    if (!has_flag(flags, kFlagSlot)) {
      add_status(result, "ISSUE_WITHOUT_SLOT");
      return result;
    }
    if (owner_by_slot.count(slot_key) != 0) {
      add_status(result, "LIVE_SLOT_REUSE");
      install_owner = false;
    }
    const auto last = last_generation.find(slot_key);
    const unsigned int expected = last == last_generation.end() ? 1U : last->second + 1U;
    if (generation != expected) {
      add_status(result, "GENERATION_MISMATCH");
      install_owner = false;
    }
    if (terminal_tokens.count(token_key) != 0) {
      add_status(result, "ISSUE_AFTER_TERMINAL");
      install_owner = false;
    }
    if (install_owner) {
      owner_by_slot[slot_key] = SlotOwner{front_token, result.inst_uid, generation};
      last_generation[slot_key] = generation;
    }
    return result;
  }

  if ((is_slot_node(node_id) || (node_id == kEvtCensored && has_flag(flags, kFlagSlot))) && node_id != kActIssueToFu) {
    if (!has_flag(flags, kFlagSlot)) {
      add_status(result, "SLOT_EVENT_WITHOUT_SLOT");
      return result;
    }
    const auto owner = owner_by_slot.find(slot_key);
    if (owner == owner_by_slot.end()) {
      add_status(result, "NO_SLOT_OWNER");
    } else {
      result.inst_uid = owner->second.inst_uid;
      if (owner->second.generation != generation) {
        add_status(result, "STALE_SLOT_GENERATION");
      }
      if (has_flag(flags, kFlagFrontToken) && owner->second.token != front_token) {
        add_status(result, "SLOT_TOKEN_MISMATCH");
      }
    }
  }

  if (is_terminal_node(node_id) && has_flag(flags, kFlagFrontToken)) {
    if (terminal_tokens.count(token_key) != 0) {
      add_status(result, "DUP_TERMINAL");
    } else {
      terminal_tokens.insert(token_key);
    }
    if (has_flag(flags, kFlagSlot)) {
      owner_by_slot.erase(slot_key);
    }
  }

  return result;
}

void write_header() {
  std::fprintf(trace_file, "# DeepFlowFuzz CVA6 dynamic identity and G0/L1 trace (TSV)\n");
  std::fprintf(trace_file,
      "schema\tcycle\trank\tcore\tsource\tsource_name\tkind\tlifecycle\t"
      "node_id\tnode_name\tflags\tlane\tslot\tgeneration\tfront_token\t"
      "inst_uid\tpc\traw_instr\texpanded_instr\tis_rvc\tfu\top\tdata0\t"
      "data1\tmonitor_status\n");
}

void write_record(
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
    unsigned long long data1,
    const IdentityResult &identity) {
  const int lane_out = lane == 0xffffffffU ? -1 : static_cast<int>(lane);
  const int slot_out = has_flag(flags, kFlagSlot) ? static_cast<int>(slot) : -1;
  const int generation_out = has_flag(flags, kFlagSlot) ? static_cast<int>(generation) : -1;
  std::fprintf(trace_file,
      "%u\t%llu\t%u\t%u\t%u\t%s\t%s\t%s\t%u\t%s\t0x%08x\t%d\t%d\t%d\t"
      "%llu\t%llu\t0x%016llx\t0x%08x\t0x%08x\t%u\t%u\t%u\t0x%016llx\t"
      "0x%016llx\t%s\n",
      kSchemaVersion, cycle, semantic_rank(node_id), core_id, source_id,
      source_name(source_id), kind_name(record_kind), lifecycle_name(lifecycle),
      node_id, node_name(node_id), flags, lane_out, slot_out, generation_out,
      front_token, identity.inst_uid, pc, raw_instr, expanded_instr,
      has_flag(flags, kFlagRvc) ? 1U : 0U, fu, op, data0, data1,
      identity.status.c_str());
  trace_records++;
  if ((trace_records % kFlushInterval) == 0 || is_terminal_node(node_id)) {
    std::fflush(trace_file);
  }
}

}  // namespace

extern "C" int v_dfz_trace_init(const char *path) {
  std::lock_guard<std::mutex> guard(trace_mutex);
  if (trace_file != nullptr) return 1;
  if (path == nullptr || path[0] == '\0') return 0;

  trace_filename = path;
  const std::filesystem::path output_path(trace_filename);
  if (!output_path.parent_path().empty()) {
    std::error_code error;
    std::filesystem::create_directories(output_path.parent_path(), error);
    if (error) {
      std::fprintf(stderr, "[DFZ ERROR] cannot create %s: %s\n",
                   output_path.parent_path().c_str(), error.message().c_str());
      return 0;
    }
  }

  trace_file = std::fopen(trace_filename.c_str(), "w");
  if (trace_file == nullptr) {
    std::fprintf(stderr, "[DFZ ERROR] cannot open %s: %s\n",
                 trace_filename.c_str(), std::strerror(errno));
    return 0;
  }

  std::setvbuf(trace_file, nullptr, _IOFBF, 4 * 1024 * 1024);
  trace_records = 0;
  identity_errors = 0;
  next_inst_uid = 1;
  uid_by_token.clear();
  terminal_tokens.clear();
  owner_by_slot.clear();
  last_generation.clear();
  write_header();

  if (!close_registered) {
    std::atexit(v_dfz_trace_close);
    close_registered = true;
  }
  std::printf("[DFZ] CVA6 TRACE: %s\n", trace_filename.c_str());
  return 1;
}

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
    unsigned long long data1) {
  std::lock_guard<std::mutex> guard(trace_mutex);
  if (trace_file == nullptr) return;

  IdentityResult identity = monitor_identity(
      core_id, node_id, flags, slot, generation, front_token);
  write_record(cycle, core_id, source_id, node_id, record_kind, lifecycle,
               flags, lane, slot, generation, front_token, pc, raw_instr,
               expanded_instr, fu, op, data0, data1, identity);
}

extern "C" void v_dfz_trace_close() {
  std::lock_guard<std::mutex> guard(trace_mutex);
  if (trace_file == nullptr) return;

  std::fprintf(trace_file,
      "# records=%llu identity_errors=%llu inst_uids=%llu live_slots=%zu "
      "terminal_uids=%zu\n",
      trace_records, identity_errors, next_inst_uid - 1,
      owner_by_slot.size(), terminal_tokens.size());
  std::fflush(trace_file);
  std::fclose(trace_file);
  trace_file = nullptr;
}
