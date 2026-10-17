# 8-bit VM in Haskell

A small 8-bit virtual machine written in Haskell. It has 8 registers, 64 KiB of memory, a stack, status flags, subroutine calls and character I/O. The whole machine is a pure state transition (`VM -> VM`); only the interactive runner touches `IO`.

## Architecture

| Component | Description |
|-----------|-------------|
| Word size | 8 bits |
| Registers | 8 general-purpose registers, `r0`..`r7` (8 bits each) |
| Memory | 65536 bytes (16-bit addresses) |
| `pc` | 16-bit program counter, starts at `0` |
| `sp` | 16-bit stack pointer, starts at `0`; the stack grows downwards, so the first push goes to `0xFFFF` |
| Flags | `zero`, `carry`, `negative` |

Programs are loaded at address `0`.

## Instruction encoding

The first byte of every instruction has the layout:

```
 7 6 5 4 3   2 1 0
+-----------+-------+
|  opcode   |  r1   |
+-----------+-------+
```

- Upper 5 bits: opcode (0..31).
- Lower 3 bits: the first register operand `r1`.

Operands follow in the next bytes:

| Form | Bytes | Layout |
|------|-------|--------|
| No operand | 1 | `[op\|r1]` |
| Register, register | 2 | `[op\|r1] [r2]` (`r2` in the low 3 bits of the second byte) |
| Register, immediate | 2 | `[op\|r1] [imm8]` |
| Register, address | 3 | `[op\|r1] [addr high] [addr low]` |
| Address (jumps, call) | 3 | `[op] [addr high] [addr low]` |

Addresses are big-endian and absolute. Example: `MovI r3, 5` is `0x1B 0x05`, because `(3 << 3) | 3 = 0x1B`.

## Instruction set

| Opcode | Mnemonic | Bytes | Operation | Flags |
|-------:|----------|------:|-----------|:-----:|
| 0 | `Nop` | 1 | do nothing | |
| 1 | `Halt` | 1 | stop the machine | |
| 2 | `Mov r1, r2` | 2 | `r1 = r2` | |
| 3 | `MovI r1, imm` | 2 | `r1 = imm` | |
| 4 | `Load r1, addr` | 3 | `r1 = memory[addr]` | |
| 5 | `Str r1, addr` | 3 | `memory[addr] = r1` | |
| 6 | `Push r1` | 1 | `sp -= 1; memory[sp] = r1` | |
| 7 | `Pop r1` | 1 | `r1 = memory[sp]; sp += 1` | |
| 8 | `Add r1, r2` | 2 | `r1 += r2` | ✔ |
| 9 | `AddI r1, imm` | 2 | `r1 += imm` | ✔ |
| 10 | `Sub r1, r2` | 2 | `r1 -= r2` | ✔ |
| 11 | `SubI r1, imm` | 2 | `r1 -= imm` | ✔ |
| 12 | `Mul r1, r2` | 2 | `r1 *= r2` | ✔ |
| 13 | `MulI r1, imm` | 2 | `r1 *= imm` | ✔ |
| 14 | `Div r1, r2` | 2 | `r1 /= r2` (halts on zero) | ✔ |
| 15 | `DivI r1, imm` | 2 | `r1 /= imm` (halts on zero) | ✔ |
| 16 | `Mod r1, r2` | 2 | `r1 %= r2` (halts on zero) | ✔ |
| 17 | `ModI r1, imm` | 2 | `r1 %= imm` (halts on zero) | ✔ |
| 18 | `And r1, r2` | 2 | `r1 &= r2` | ✔ |
| 19 | `Or r1, r2` | 2 | `r1 \|= r2` | ✔ |
| 20 | `Xor r1, r2` | 2 | `r1 ^= r2` | ✔ |
| 21 | `Not r1` | 1 | `r1 = ~r1` | |
| 22 | `Cmp r1, r2` | 2 | set flags from `r1 - r2`, registers unchanged | ✔ |
| 23 | `Jmp addr` | 3 | `pc = addr` | |
| 24 | `Je addr` | 3 | jump if `zero` | |
| 25 | `Jnz addr` | 3 | jump if not `zero` | |
| 26 | `Jg addr` | 3 | jump if greater (unsigned): `!zero && !carry` | |
| 27 | `Jl addr` | 3 | jump if less (unsigned): `carry` | |
| 28 | `Call addr` | 3 | push return address (2 bytes), `pc = addr` | |
| 29 | `Ret` | 1 | pop return address into `pc` | |
| 30 | `PutChar r1` | 1 | write byte `r1` to output | |
| 31 | `GetChar r1` | 1 | `r1 =` next input byte (`0` at end of input) | |

### Flags

Arithmetic and logic instructions, and `Cmp`, set the flags:

- `zero`: the result is `0` (for `Cmp`: operands are equal).
- `negative`: bit 7 of the result is set.
- `carry`: unsigned overflow for `Add`/`Mul`, borrow (`a < b`) for `Sub`/`Cmp`. Always `false` for `Div`, `Mod`, `And`, `Or`, `Xor`.

`Mov`, `MovI`, `Load`, `Str`, `Push`, `Pop` and `Not` leave the flags unchanged.

### Calls and the stack

`Call` pushes the 16-bit return address (high byte first, then low byte), so the low byte ends up on top. `Ret` pops it back. Calls can be nested freely. The stack is not bounds-checked.

## Building and running

Requires GHC and cabal.

```bash
cabal build
cabal run
```

`main` loads a built-in echo program: it reads characters from stdin and prints them back until the end of input (Ctrl-D).

## Example program

Echo, as written in `main`:

```haskell
[ encodeInstruction MovI    1, 0 -- 0:  r1 = 0
, encodeInstruction GetChar 0    -- 2:  @loop: r0 = getchar
, encodeInstruction Cmp     0, 1 -- 3:  cmp r0, r1
, encodeInstruction Je      0    -- 5:  if equal goto @end
,                   0x00
,                   0x0C
, encodeInstruction PutChar 0    -- 8:  putchar r0
, encodeInstruction Jmp     0    -- 9:  goto @loop
,                   0x00
,                   0x02
, encodeInstruction Halt    0    -- 12: @end: halt
]
```

## Execution model

- `fetch` decodes the opcode at `pc`; `execute :: Instruction -> VM -> VM` implements each instruction's semantics as a pure function.
- `runIO` is the interactive loop: it handles `PutChar` and `GetChar` with real `IO` and delegates everything else to `execute`.
- After an instruction runs, `pc` points at the next instruction (or at the jump target).

## Limitations

- Memory is a Haskell list, so every access is O(n). Fine for small programs; use `Data.Array.Unboxed` or `Data.Vector.Unboxed` for speed.
- There are no stack overflow/underflow checks, and the stack can overwrite program code.
- Division or modulo by zero silently halts the machine.
- Memory is not protected: programs can overwrite their own code.
- There is no assembler yet; programs are written as lists of bytes.

## License

MIT (add a `LICENSE` file before publishing).