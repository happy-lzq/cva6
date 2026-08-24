# CVA6 DeepFlowFuzz G0/L1 TRACE

`make trace` compiles the Verilator model with `DFZ_TRACE`, runs Spike and
CVA6, and writes the structured RTL trace to both an archived run path and a
stable per-test path:

```text
<test>/build/runs/<run-id>/TRACE/<test>.l1.tsv
<test>/build/TRACE/<test>.l1.tsv
```

A normal `make run` or `make rtl` does not enable this monitor.

## Dynamic identity

The first implementation targets `cv64a6_imafdc_sv39` (scalar issue, no
ZCMP/ZCMT macro expansion):

```text
IF/ID realigned instruction accept
  front_token -> host inst_uid
                    |
scoreboard allocate trans_id slot
  (trans_id, generation, front_token)
                    |
writeback / commit / trap / flush resolve the same inst_uid
```

`pc` is an instruction attribute, never its identity.  `trans_id` is a
reusable physical slot, so every lifetime includes `generation`. Frontend
tokens and slot generations remain monotonic across later episode resets; reset
first emits terminal evidence for every resident identity.

## Coarse nodes

| Node | Kind | Meaning |
|---|---|---|
| `EVT_IF_ID_ACCEPT` | Event | One realigned instruction is accepted by ID and receives a frontend token. |
| `PL_ID_RESIDENT` | PL | Coarse frontend/ID residency. `data0` carries all simultaneous wait facts. |
| `PL_ID_WAIT_SB_FULL` | PL | The ID resident waits for a free scoreboard slot. |
| `PL_ID_WAIT_FU` | PL | The selected functional unit is structurally busy. |
| `PL_ID_WAIT_RAW` | PL | At least one source operand is not yet available. `data0[2:0]` is `{rs3,rs2,rs1}`. |
| `PL_ID_WAIT_CVXIF` | PL | A CVXIF protocol transaction has not completed its issue handshake. |
| `PL_ID_WAIT_ACCEL` | PL | The optional accelerator dispatcher stalls issue. |
| `PL_ID_WAIT_OTHER` | PL | Valid ID resident with no currently classified acknowledge. |
| `ACT_ISSUE_TO_FU` | Action | The instruction is allocated into `(slot,generation)` and dispatched. |
| `PL_SB_WAIT_RESULT` | PL | `issued && !sbe.valid`; execution has not produced a result. |
| `PL_SB_WAIT_COMMIT` | PL | `issued && sbe.valid && !sbe.ex.valid`; result waits for in-order commit. |
| `PL_SB_EXCEPTION_WAIT` | PL | `issued && sbe.valid && sbe.ex.valid`; exception waits at the head path. |
| `EVT_FU_RESPONSE` | Event | An FU response is observed; `data0=result`, `data1=cause`. A same-edge full flush may still discard it. |
| `EVT_COMMIT` | Event | Architectural retirement; `data0=result`. |
| `EVT_COMMIT_DROP` | Event | A cancelled scoreboard owner is removed without architectural retirement. |
| `EVT_TRAP` | Event | Exception owner terminal; `data0=cause`, `data1=tval`. |
| `EVT_ID_KILL` | Event | An unissued frontend identity is killed by redirect/flush. |
| `EVT_FLUSH_KILL` | Event | An active scoreboard identity is killed by full flush. |
| `EVT_PIPELINE_FLUSH` | Event | Flush witness without an instruction identity; `data0` is the reason mask. |
| `EVT_PIPELINE_RESET` | Event | Later episode reset witness; reset-terminated identities are emitted first. |
| `EVT_CENSORED` | Event | Positive evidence that an identity is still resident when observation ends. |

PL rows use `lifecycle=VISIT`: one row is emitted for each cycle of residency.
Actions/events are point or terminal witnesses.

`PL_ID_RESIDENT.data0` is a concurrent fact bitmap, not a priority encoding:
bit 0 scoreboard full, bit 1 FU busy, bit 2 RAW, bit 3 accelerator stall,
bit 4 CVXIF wait, and bits 7:5 are `{rs3,rs2,rs1}`.  The more specific ID
wait PL rows may therefore coexist in one cycle.

For a compressed instruction, `raw_instr` is normalized to a zero-extended
16-bit encoding; `expanded_instr` remains the decoded 32-bit instruction.

## Flush reason bits

`data0` on flush and kill rows is a bit mask:

| Bit | Cause |
|---:|---|
| 0 | branch mispredict |
| 1 | committed exception/trap |
| 2 | `eret` |
| 3 | enter debug PC |
| 4 | CSR-requested flush |
| 5 | commit-stage flush |
| 6 | `fence.i` |
| 7 | `fence` |
| 8 | `sfence.vma` |
| 9 | `hfence.vvma` |
| 10 | `hfence.gvma` |
| 11 | accelerator-requested flush |
| 31 | episode reset |

## Validity and consistency

Optional columns are authoritative only when their `flags` bit is set.  The
host monitor checks token birth, live-slot reuse, generation continuity,
slot/token agreement, and duplicate terminals.  Every row reports the result
in `monitor_status`; a correct run ends with `identity_errors=0` in the footer.
