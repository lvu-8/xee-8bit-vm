module Main where

import Data.Word (Word8, Word16)
import Data.Bits ((.&.), (.|.), shiftL, shiftR, xor, complement)
import Data.Char (chr, ord)

import System.IO

-- 8 bit system
wordSize :: Int
wordSize = 8

-- 8 registers
registersCount :: Int
registersCount = 8

-- 16 bits program counter
-- 16 address
-- 2 ^ 16 addresses in memory
addressSize :: Int
addressSize = 16

toWord16 :: Word8 -> Word8 -> Word16
toWord16 high low =
    (fromIntegral high `shiftL` 8) .|. fromIntegral low

data Instruction
    = Nop
    | Halt
    | Mov
    | MovI -- imm
    | Load
    | Str
    | Push
    | Pop
    | Add
    | AddI -- imm
    | Sub
    | SubI -- imm
    | Mul
    | MulI -- imm
    | Div
    | DivI -- imm
    | Mod
    | ModI -- imm
    | And
    | Or
    | Xor
    | Not
    | Cmp
    | Jmp
    | Je
    | Jnz
    | Jg
    | Jl
    | Call
    | Ret
    | PutChar -- ~ io
    | GetChar -- ~ io
    deriving (Enum, Show, Eq)

getRegister :: Word8 -> Word8
getRegister byte = byte .&. 0x07

getOpcode :: Word8 -> Word8
getOpcode byte = byte `shiftR` 3

decodeOpcode :: Word8 -> Instruction
decodeOpcode opcode =
    toEnum (fromIntegral opcode) :: Instruction

encodeOpcode :: Instruction -> Word8
encodeOpcode instruction =
    fromIntegral (fromEnum instruction)

encodeInstruction :: Instruction -> Word8 -> Word8
encodeInstruction instruction r1 =
    (encodeOpcode instruction `shiftL` 3) .|. r1


data Flags = Flags
    { zero     :: Bool
    , carry    :: Bool
    , negative :: Bool
    }

setAt :: Int -> a -> [a] -> [a]
setAt index value list =
    take index list ++ [value] ++ drop (index + 1) list

data VM = VM
    { registers :: [Word8]
    , memory    :: [Word8]
    , pc        :: Word16
    , sp        :: Word16
    , flags     :: Flags
    , running   :: Bool
    , input     :: [Word8]
    , output    :: [Word8]
    }

initialVM :: VM
initialVM = VM
    { registers = replicate (registersCount) 0
    , memory    = replicate (2 ^ addressSize) 0
    , pc        = 0
    , sp        = 0
    , flags     = Flags False False False
    , running   = True
    , input     = []
    , output    = []
    }

-- ================================
-- Helpers

incrementPC :: VM -> VM
incrementPC vm =
    vm { pc = pc vm + 1 }

writeRegister :: VM -> Int -> Word8 -> VM
writeRegister vm register value =
    vm {
        registers = setAt register value (registers vm)
    }

readRegister :: VM -> Int -> Word8
readRegister vm register =
    (registers vm) !! register

writeMemory :: VM -> Int -> Word8 -> VM
writeMemory vm address value =
    vm {
        memory = setAt address value (memory vm)
    }

readMemory :: VM -> Int -> Word8
readMemory vm address =
    (memory vm) !! address

currentInstruction :: VM -> Word8
currentInstruction vm =
    memory vm !! fromIntegral (pc vm)

nextByte :: VM -> (Word8, VM)
nextByte vm =
    let newVm = incrementPC vm
    in  ( readMemory newVm (fromIntegral (pc newVm))
        , newVm
        )

nextWord16 :: VM -> (Word16, VM)
nextWord16 vm =
    let (high, vm1) = nextByte vm
        (low,  vm2) = nextByte vm1
    in  (toWord16 high low, vm2)

fetch :: VM -> Instruction
fetch vm =
    decodeOpcode (getOpcode (currentInstruction vm)) :: Instruction

-- ================================
-- Operation Helpers

move :: VM -> Word8 -> Word8 -> VM
move vm r1 value =
    incrementPC (writeRegister vm (fromIntegral r1) value)

-- ===================================
-- < Arithmetics >
math_operation :: VM -> Word8 -> Word8 -> (Word8 -> Word8 -> Word8) -> (Word8 -> Word8 -> Bool) -> VM
math_operation vm r1 value function carryOf =
    let r1_index = fromIntegral r1
        r1_value = readRegister vm r1_index
        result   = function r1_value value
        newFlags = Flags
            { zero     = result == 0
            , carry    = carryOf r1_value value
            , negative = result .&. 0x80 /= 0
            }
        vm1 = writeRegister vm r1_index result
    in incrementPC (vm1 { flags = newFlags })

-- For operations where a transfer makes no sense
noCarry :: Word8 -> Word8 -> Bool
noCarry _ _ = False

add :: VM -> Word8 -> Word8 -> VM
add vm r1 value =
    math_operation vm r1 value (+)
        (\a b -> fromIntegral a + fromIntegral b > (255 :: Int))

sub :: VM -> Word8 -> Word8 -> VM
sub vm r1 value =
    math_operation vm r1 value (-) (<) -- like cmp

mul :: VM -> Word8 -> Word8 -> VM
mul vm r1 value =
    math_operation vm r1 value (*)
        (\a b -> fromIntegral a * fromIntegral b > (255 :: Int))

divide :: VM -> Word8 -> Word8 -> VM
divide vm r1 value
    | value == 0 = vm { running = False }
    | otherwise  = math_operation vm r1 value div noCarry

modulo :: VM -> Word8 -> Word8 -> VM
modulo vm r1 value
    | value == 0 = vm { running = False }
    | otherwise  = math_operation vm r1 value mod noCarry

-- jumps
jumpIf :: (Flags -> Bool) -> VM -> VM
jumpIf condition vm =
    let (addr, newVm) = nextWord16 vm
    in  if condition (flags newVm)
            then newVm { pc = addr }
            else incrementPC newVm

compareValues :: VM -> Word8 -> Word8 -> VM
compareValues vm a b =
    incrementPC vm
        { flags = Flags
            { zero     = a == b
            , carry    = a < b
            , negative = (a - b) .&. 0x80 /= 0
            }
        }

push8 :: VM -> Word8 -> VM
push8 vm value =
    let newSp = sp vm - 1
    in  (writeMemory vm (fromIntegral newSp) value) { sp = newSp }

pop8 :: VM -> (Word8, VM)
pop8 vm =
    ( readMemory vm (fromIntegral (sp vm))
    , vm { sp = sp vm + 1 }
    )

-- The most significant byte is pushed first, followed by the least significant byte,
-- so the least significant byte resides at a lower address in memory (at the top).
push16 :: VM -> Word16 -> VM
push16 vm value =
    push8 (push8 vm (fromIntegral (value `shiftR` 8)))
          (fromIntegral (value .&. 0xFF))

pop16 :: VM -> (Word16, VM)
pop16 vm =
    let (low,  vm1) = pop8 vm
        (high, vm2) = pop8 vm1
    in  (toWord16 high low, vm2)

-- ===================================
-- Patterns

patternR1R2 :: VM -> (VM, Word8, Word8)
patternR1R2 vm =
    let r1 = getRegister(currentInstruction vm)
        (byte, newVm) = nextByte vm
        value = readRegister newVm (fromIntegral(getRegister(byte)))
    in
    ( newVm, r1, value )

patternR1Imm :: VM -> (VM, Word8, Word8)
patternR1Imm vm =
    let r1 = getRegister(currentInstruction vm)
        (value, newVm) = nextByte vm
    in
    ( newVm, r1, value )

patternR1Addr :: VM -> (VM, Word8, Int)
patternR1Addr vm =
    let r1 = getRegister (currentInstruction vm)
        (addr, newVm) = nextWord16 vm
    in  ( newVm, r1, fromIntegral addr )

-- ================================
-- Execute. All semantics of instructions

execute :: Instruction -> VM -> VM

-- Nop
-- No operation
execute Nop vm =
    incrementPC vm

-- Halt
-- Stop the program
execute Halt vm =
    vm { running = False }

-- Move (r1, r2) or Move(r1, imm)
-- Writing to r1
execute Mov vm =
    let (newVm, r1, value) = patternR1R2 vm
    in move newVm r1 value

execute MovI vm =
    let (newVm, r1, value) = patternR1Imm vm
    in move newVm r1 value

-- Add (r1, r2) or Add (r1 imm)
-- Adding to r1
execute Add vm =
    let (newVm, r1, value) = patternR1R2 vm
    in add newVm r1 value

execute AddI vm =
    let (newVm, r1, value) = patternR1Imm vm
    in add newVm r1 value

-- ...
execute Sub vm =
    let (newVm, r1, value) = patternR1R2 vm
    in sub newVm r1 value

execute SubI vm =
    let (newVm, r1, value) = patternR1Imm vm
    in sub newVm r1 value

execute Mul vm =
    let (newVm, r1, value) = patternR1R2 vm
    in mul newVm r1 value

execute MulI vm =
    let (newVm, r1, value) = patternR1Imm vm
    in mul newVm r1 value

execute Div vm =
    let (newVm, r1, value) = patternR1R2 vm
    in divide newVm r1 value

execute DivI vm =
    let (newVm, r1, value) = patternR1Imm vm
    in divide newVm r1 value

execute Mod vm =
    let (newVm, r1, value) = patternR1R2 vm
    in modulo newVm r1 value

execute ModI vm =
    let (newVm, r1, value) = patternR1Imm vm
    in modulo newVm r1 value

-- End math

-- Load (r1, addr)
-- r1 = memory[addr]
execute Load vm =
    let (newVm, r1, addr) = patternR1Addr vm
        value = readMemory newVm addr
    in move newVm r1 value

-- Str (r1, addr)
-- memory[addr] = r1
execute Str vm =
    let (newVm, r1, addr) = patternR1Addr vm
        value = readRegister newVm (fromIntegral r1)
    in incrementPC (writeMemory newVm addr value)

-- Steak

-- Push (r1)
-- sp = sp - 1; memory[sp] = r1
execute Push vm =
    let r1 = getRegister (currentInstruction vm)
        value = readRegister vm (fromIntegral r1)
    in incrementPC (push8 vm value)

-- Pop (r1)
-- r1 = memory[sp]; sp = sp + 1
execute Pop vm =
    let r1 = getRegister (currentInstruction vm)
        (value, vm1) = pop8 vm
    in move vm1 r1 value

-- Jumps

-- Cmp (r1, r2)
-- Sets flags based on r1 - r2; does not modify registers.
execute Cmp vm =
    let (newVm, r1, value) = patternR1R2 vm
        a = readRegister newVm (fromIntegral r1)
    in compareValues newVm a value

-- Jmp addr: unconditional jump
execute Jmp vm = jumpIf (const True) vm

-- Je addr: jump if zero
execute Je vm = jumpIf zero vm

-- Jnz addr: jump if not equal (not zero)
execute Jnz vm = jumpIf (not . zero) vm

-- Jg addr: jump if r1 > r2 (unsigned)
execute Jg vm = jumpIf (\f -> not (zero f) && not (carry f)) vm

-- Jl addr: jump if r1 < r2 (unsigned)
execute Jl vm = jumpIf carry vm

-- Subs

-- Call addr
-- Pushes the return address (the next instruction) and jumps to addr
execute Call vm =
    let (addr, newVm) = nextWord16 vm
        returnAddr = pc newVm + 1
    in  (push16 newVm returnAddr) { pc = addr }

-- Ret
-- Pops the return address from the stack into the pc
execute Ret vm =
    let (addr, newVm) = pop16 vm
    in  newVm { pc = addr }

-- Logic
-- And / Or / Xor (r1, r2): r1 = r1 op r2
execute And vm =
    let (newVm, r1, value) = patternR1R2 vm
    in math_operation newVm r1 value (.&.) noCarry

execute Or vm =
    let (newVm, r1, value) = patternR1R2 vm
    in math_operation newVm r1 value (.|.) noCarry

execute Xor vm =
    let (newVm, r1, value) = patternR1R2 vm
    in math_operation newVm r1 value xor noCarry

-- Not (r1)
execute Not vm =
    let r1 = getRegister (currentInstruction vm)
        value = readRegister vm (fromIntegral r1)
    in move vm r1 (complement value)

-- PutChar (r1): write r1 in output
execute PutChar vm =
    let r1 = getRegister (currentInstruction vm)
        value = readRegister vm (fromIntegral r1)
    in incrementPC (vm { output = value : output vm })

-- GetChar (r1): r1 = next byte of input (0 - end of input)
execute GetChar vm =
    let r1 = getRegister (currentInstruction vm)
    in case input vm of
        []     -> move vm r1 0
        (x:xs) -> move (vm { input = xs }) r1 x


-- ================================

loadProgram :: [Word8] -> VM -> VM
loadProgram program vm =
    vm { memory = program ++ drop (length program) (memory vm) }

step :: VM -> VM
step vm =
    let instruction = fetch vm
    in execute instruction vm

runIO :: VM -> IO VM
runIO vm
    | not (running vm) = return vm
    | otherwise =
        case fetch vm of
            PutChar -> do
                let r1    = getRegister (currentInstruction vm)
                    value = readRegister vm (fromIntegral r1)
                putChar (chr (fromIntegral value))
                runIO (incrementPC vm)

            GetChar -> do
                let r1 = getRegister (currentInstruction vm)
                eof <- isEOF
                byte <- if eof
                    then return 0
                    else fromIntegral . ord <$> getChar
                runIO (move vm r1 byte)

            instruction ->
                runIO (execute instruction vm)

main :: IO ()
main = do
    hSetBuffering stdout NoBuffering

    let program =
            [ encodeInstruction MovI    1, 0 -- 0:  mov-i r1, 0
            , encodeInstruction GetChar 0    -- 2:  @loop: get-char r0
            , encodeInstruction Cmp     0, 1 -- 3:  cmp r0, r1
            , encodeInstruction Je      0    -- 5:  je @end
            ,                   0x00
            ,                   0x0C
            , encodeInstruction PutChar 0    -- 8:  put-char r0
            , encodeInstruction Jmp     0    -- 9:  goto @loop
            ,                   0x00
            ,                   0x02
            , encodeInstruction Halt    0    -- 12: @end: halt
            ]

    _ <- runIO (loadProgram program initialVM)
    return ()