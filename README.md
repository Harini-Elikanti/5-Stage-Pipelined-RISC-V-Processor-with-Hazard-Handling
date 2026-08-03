# 5-Stage Pipelined RISC-V Processor with Hazard Handling

## Overview

This project implements a 32-bit RISC-V processor using a classic 5-stage instruction pipeline in Verilog.

The processor divides instruction execution into five stages:

1. Instruction Fetch (IF)
2. Instruction Decode (ID)
3. Execute (EX)
4. Memory Access (MEM)
5. Writeback (WB)

The design focuses on understanding pipelined processor architecture and handling common pipeline hazards using forwarding, stalling, and branch flushing.

---

## Processor Architecture

The processor follows the classic 5-stage RISC-V pipeline:

```text
        ┌──────────────┐
        │     IF       │
        │   Fetch      │
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │     ID       │
        │   Decode     │
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │     EX       │
        │   Execute    │
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │    MEM       │
        │ Memory Access│
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │     WB       │
        │  Writeback   │
        └──────────────┘
