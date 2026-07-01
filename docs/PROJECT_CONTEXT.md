# SNN_ECG_V2

## Project Overview

This project is a production-quality RTL implementation of the IEEE TBCAS 2022 paper:

"A Neuromorphic Processing System With Spike-Driven SNN Processor for Wearable ECG Classification"

Goal:

- Faithfully reproduce the processor architecture proposed in the paper.
- Improve RTL quality using production ASIC design practices.
- Do NOT modify the algorithm or processor behavior.
- Only improve architecture, readability, modularity and maintainability.

------------------------------------------------------------

## Development Philosophy

The implementation follows three principles.

1. Preserve the paper architecture.

Never change:

- Top_FSM
- Neuron_FSM
- Spike Merge
- Weight Decode
- Hierarchical Memory
- Spike-driven processing
- Three timestep execution
- rMLP architecture

2. Improve RTL quality.

Allowed improvements:

- Better module boundaries
- Better documentation
- Better signal naming
- Shared parameters
- Common state definitions
- Modular folder structure
- Verification improvements
- Cleaner FSM implementation

3. Maintain functional equivalence.

Every refactoring must preserve:

- Timing
- Latency
- Waveforms
- Testbench results

------------------------------------------------------------

## Repository Structure

SNN_ECG_V2/

docs/
Architecture.md
Paper_Mapping.md
Signal_Ownership.md
Timing_Diagrams.md

rtl/

common/
snn_parameters.vh
snn_states.vh
snn_constants.vh

control/
top_fsm.v
neuron_fsm.v

compute/
npu.v
spike_merge.v
spike_iterator.v
neuron_ptr_gen.v

memory/
weight_decode.v
neuron_state_sram.v
sram_1rw.v

io/
uart_rx.v
uart_tx.v
input_buffer.v
output_reader.v

classifier/
argmax5.v

top/
snn_ecg_top.v

tb/

tb_top.v
tb_top_fsm.v
tb_neuron_fsm.v
tb_npu.v
tb_weight_decode.v
tb_spike_merge.v
tb_uart.v

scripts/

compile.do
simulate.do
clean.do
run_all.do

sim/

mem/

README.md

LICENSE

------------------------------------------------------------

## Architecture

Processor Architecture

                snn_ecg_top
                      │
      ┌───────────────┼────────────────┐
      │               │                │
      ▼               ▼                ▼

IO             CONTROL          COMPUTE

UART RX        Top FSM          Spike Merge
UART TX        Neuron FSM       Spike Iterator
Input Buffer                    Neuron Ptr Gen
Output Reader                   NPU

                      │
                      ▼

                 MEMORY

          Weight Decode

      Weight Entrance SRAM

     Weight Connection SRAM

      Neuron State SRAM

                      │

                 Classifier

                 Argmax5

------------------------------------------------------------

## Ownership Rules

Top

- Instantiates modules only.
- Contains no algorithmic logic.

Top_FSM

Owns:

- Inference sequence
- Time step progression
- Mode selection

Neuron_FSM

Owns:

- Neuron execution pipeline

NPU

Owns:

- Arithmetic
- Membrane update
- Weight accumulation

Weight Decode

Owns:

- Sparse memory traversal

Neuron SRAM

Owns:

- Storage only

------------------------------------------------------------

## Coding Standard

Every RTL file contains:

1. Header
2. Includes
3. Parameters
4. Registers
5. Wires
6. Sequential Logic
7. Combinational Logic
8. Module Instantiations

Naming Convention

i_  -> input

o_  -> output

w_  -> wire

r_  -> register

c_  -> localparam

------------------------------------------------------------

## Refactoring Workflow

Every module follows:

Architecture Review

↓

Problems

↓

Refactoring Plan

↓

New RTL

↓

Simulation

↓

Waveform Comparison

↓

Git Commit

------------------------------------------------------------

## Refactoring Order

1. snn_ecg_top

2. top_fsm

3. neuron_fsm

4. npu

5. weight_decode

6. spike_merge

7. spike_iterator

8. neuron_ptr_gen

9. neuron_state_sram

10. io modules

11. classifier

------------------------------------------------------------

## Important Constraints

Never change:

- Algorithm
- Timing
- Pipeline
- Memory organization
- Processor architecture

Allowed:

- Better comments
- Better formatting
- Better modularity
- Cleaner interfaces
- Documentation
- Parameters
- Internal refactoring

------------------------------------------------------------

## Current Progress

Repository Created

Documentation Created

Folder Structure Completed

Parameters Created

States Created

Constants Created

Ready to begin RTL refactoring.

Current Module:

snn_ecg_top.v

Status:

Waiting for architecture review and production refactoring.

------------------------------------------------------------

## Long-Term Goal

Deliver an open-source production-quality RTL implementation of the paper suitable for:

- BTP
- GitHub portfolio
- ASIC interview discussions
- FPGA implementation
- Future ASIC synthesis

