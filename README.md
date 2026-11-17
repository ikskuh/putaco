# 🌮 Putaco 🌮 - The *Pu*nch *Ta*pe *Co*mputer, an 8 bit CPU

## Overview

- 8-bit harvard architecture
- 256 bytes data memory
- no program counter
- uses a punch tape as program memory
- 128 branch targets

## Why should we ever use this?

1. You want to specify your performance in
   - computation speed: km/h
   - program size: m²
   - run length: km
2. You want to write a compiler which needs to consider the aerodynamic and mechanic properties of a program.

## Concept

> to be done

## Encoding

Putaco uses an 8-bit instruction bus encoding, which alternates between instruction and operand,
and allows arbitrary label codes interleaved.

### Instruction Encoding

| Bit Range | Name        | Description                                         |
| --------- | ----------- | --------------------------------------------------- |
| `[7]`     | `label`     | If set, the byte is a label and not an opcode.      |
| `[6]`     | *reserved*  | Reserved and must be zero.                          |
| `[5]`     | `operand_h` | The 7th bit of the operand.                         |
| `[4]`     | `indirect`  | If set, the CPU fetches the operand from memory.    |
| `[3:0]`   | `opcode`    | Defines the operation that is performed by the CPU. |

### Operand Encoding

| Bit Range | Name        | Description                                    |
| --------- | ----------- | ---------------------------------------------- |
| `[7]`     | `label`     | If set, the byte is a label and not an opcode. |
| `[6:0]`   | `operand_l` | Bits 0 to 6 of the operand.                    |

### Label Encoding

| Bit Range | Name        | Description                                    |
| --------- | ----------- | ---------------------------------------------- |
| `[7]`     | `label`     | If set, the byte is a label and not an opcode. |
| `[6:0]`   | `branch_id` | The 7-bit branch ID.                           |

## Opcodes

The CPU implements 16 different operations, 8 of which are arithmetic operations, two memory access and 4 branching.

| Opcode | Name   | Operation              | Description                                                                               |
| ------ | ------ | ---------------------- | ----------------------------------------------------------------------------------------- |
| 0      | `halt` |                        | Stops the tape reader.                                                                    |
| 1      | `set`  | A = op                 | Sets the accumulator to the operand.                                                      |
| 2      | `ld`   | A = mem[op]            | Loads a byte from memory in the accumulator. Operand is the address.                      |
| 3      | `st`   | mem[op] = A            | Stores the accumulator to memory. Operand is the address.                                 |
| 4      | `jmp`  | seek(op)               | Branches to the label given in the operand.                                               |
| 5      | `jz`   | if(!A) seek(op)        | Branches to the label given in the operand when accumulator is zero.                      |
| 6      | `jnz`  | if(A) seek(op)         | Branches to the label given in the operand when accumulator is non-zero.                  |
| 7      | `djnz` | A -= 1; if(A) seek(op) | Decrements the accumulator and branches to the given label when accumulator reaches zero. |
| 8      | `add`  | A += op                | Adds the operand to the accumulator.                                                      |
| 9      | `sub`  | A -= op                | Subtracts the operand to the accumulator.                                                 |
| A      | `and`  | A &= op                | Performs boolean and between accumulator and operand.                                     |
| B      | `xor`  | A ^= op                | Performs boolean xor between accumulator and operand.                                     |
| C      | `shl`  | A << op                | Shifts the accumulator left by operand bits Fills in zeroes.                              |
| D      | `shr`  | A >> op                | Shifts the accumulator right by operand bits. Fills in zeroes.                            |
| E      | `asr`  | A >>> op               | Shifts the accumulator right by operand bits. Fills in the MSB.                           |
| F      | `neg`  | A = op - A             | Subtracts the accumulator from the operand.                                               |

## CPU Logic

```py
while True:
  instr = wait_next()
  reg;
  op = wait_next()
  reg;
  if instr[4]:
    op = mem[op]
    reg;
  if instr[3]:
    acc = alu[instr&7, op, acc]
  motor_on = !instr[3:0]
  if instr[3:0] == 1:
    acc = op
  if instr[3:0] == 2:
    acc = mem[op]
  if instr[3:0] == 3:
    mem[op] = acc
  if instr[3:0] == 7:
    acc = alu[9,1,acc]
  if instr[3:2]==1 & { 1, A == 0, A !=0, A==1}[instr[1:0]]:
    seek(op)
  reg;
```

## Memory Map

Putaco uses an 8-bit wide address space, split into 4 different memory banks:

| Begin | End | Size | Description                 |
| ----- | --- | ---- | --------------------------- |
| 0     | 15  | 16   | Memory mapped I/O registers |
| 16    | 127 | 112  | Fixed 112 bytes of RAM.     |
| 128   | 191 | 64   | Flexible memory bank 0.     |
| 192   | 255 | 64   | Flexible memory bank 1.     |

The putaco exposes a total of 16 kB of RAM to the programmer. This RAM is organized in memory pages of 64 bytes each.

### Memory Mapped I/O Registers

The system interacts with its outer world by using a memory-mapped I/O scheme. This means that the CPU does not have specialized I/O instructions but uses
regular load/store operations to perform I/O.

| Register | Description              | Read Operation          | Write Operation                  |
| -------- | ------------------------ | ----------------------- | -------------------------------- |
| 0        | FT232H Data Register     | Read Data Pipe          | Write Data Pip                   |
| 1        | FT232H Status Register   | Read Status             | Send Immediate                   |
| 2        | Physical Status Register | Read 8 switch status    | Write 8 LED status (1=on, 0=off) |
| 3        | 7-Segment Display        | Read current BCD number | Set current 2-digit BCD number.  |
| 4        | Bank 0 MSBs              | Read Bank 0 MSBs        | Write Bank 0 MSBs                |
| 5        | Bank 1 MSBs              | Read Bank 1 MSBs        | Write Bank 1 MSBs                |
| 6-15     | *reserved*               |                         |                                  |

### Fixed Memory Bank

The fixed memory bank always provides access into the lowest 128 bytes of RAM, excluding the lowest 16 bytes.

This provides a guaranteed reliable memory window for the programmer.

### Flexible Memory Bank 0, 1

Flexible Memory Bank 0 and 1 provide a remappable view for an an arbitrary memory page. The final address for a banked address is computed as such:

The low 6 bits of the memory address are taken verbatim from the LSBs of the 8-bit bus address. The upper 8 bit of the memory address are taken from the Bank 0 or Bank 1 MSB register:

```
ram_address = { bank_reg[mem_addr[6]][7:0], mem_addr[5:0] }
```

By allowing access to two memory banks, it's possible to perform arbitrary memory copy operations without having to double-buffer the data into the fixed memory bank.
