//
//  olc6502.swift
//  nes
//
//  Created by mike on 7/27/25.
//

import Foundation

// MARK: Bus Connectivity
protocol Bus: AnyObject {
    // Reads an 8-bit byte from the bus, located at the 16 bit address
    func read(address: UInt16) -> UInt8
    // Writes a byte to the specified address
    func write(address: UInt16, data: UInt8)

}

class OLC6502 {
    var a: UInt8 = 0x00
    var x: UInt8 = 0x00
    var y: UInt8 = 0x00
    var stkp: UInt8 = 0x00 // Stack pointer
    var pc: UInt16 = 0x0000 // Program counter
    var status: UInt8 = 0x00
    
    private var fetched: UInt8 = 0x00
    private var temp: UInt16 = 0x0000
    private var addr_abs: UInt16 = 0x0000
    private var addr_rel: UInt16 = 0x00
    private var opcode: UInt8 = 0x00
    private var cycles: UInt8 = 0
    private var clock_count: UInt32 = 0
    
    private weak var bus: Bus?
    
    #if LOGMODE
    private var logfile: FileHandle?
    #endif
    
    enum FLAGS6502: UInt8 {
        case C = 0b00000001 // Carry
        case Z = 0b00000010 // Is Zero
        case I = 0b00000100 // Interrupt Disable
        case D = 0b00001000 // Decimal mode (disabled)
        case B = 0b00010000 // Unused
        case U = 0b00100000 // Unused
        case V = 0b01000000 // Overflow
        case N = 0b10000000 // Negative
    }
    
    enum AddressingMode {
        case IMP, IMM, ZP0, ZPX, ZPY, REL, ABS, ABX, ABY, IND, IZX, IZY
        
        func execute(on cpu: OLC6502) -> UInt8 {
            switch self {
            case .IMP: return cpu.IMP()
            case .IMM: return cpu.IMM()
            case .ZP0: return cpu.ZP0()
            case .ZPX: return cpu.ZPX()
            case .ZPY: return cpu.ZPY()
            case .REL: return cpu.REL()
            case .ABS: return cpu.ABS()
            case .ABX: return cpu.ABX()
            case .ABY: return cpu.ABY()
            case .IND: return cpu.IND()
            case .IZX: return cpu.IZX()
            case .IZY: return cpu.IZY()
            }
        }
    }
    
    struct Instruction {
        let name: String
        let operate: (() -> UInt8)?
        let addressingMode: AddressingMode
        let cycles: UInt8
    }
    
    private var lookup: [Instruction] = []
    
    init() {
        setupInstructionTable()
    }
    
    // MARK: External Inputs
    // Forces the 6502 into a known state. This is hard-wired inside the CPU. The
    // registers are set to 0x00, the status register is cleared except for unused
    // bit which remains at 1. An absolute address is read from location 0xFFFC
    // which contains a second address that the program counter is set to. This
    // allows the programmer to jump to a known and programmable location in the
    // memory to start executing from. Typically the programmer would set the value
    // at location 0xFFFC at compile time.
    func reset() {
        // Get address to set program counter to
        addr_abs = 0xFFFC
        let lo = UInt16(read(addr_abs + 0))
        let hi = UInt16(read(addr_abs + 1))
        
        // Set it
        pc = (hi << 8) | lo
        
        // Reset internal registers
        a = 0
        x = 0
        y = 0
        stkp = 0xFD
        status = 0x00 | FLAGS6502.U.rawValue
        
        // Clear internal helper variables
        addr_rel = 0x0000
        addr_abs = 0x0000
        fetched = 0x00
        
        cycles = 8
    }
    
    // Interrupt requests are a complex operation and only happen if the
    // "disable interrupt" flag is 0. IRQs can happen at any time, but
    // you dont want them to be destructive to the operation of the running
    // program. Therefore the current instruction is allowed to finish
    // (which I facilitate by doing the whole thing when cycles == 0) and
    // then the current program counter is stored on the stack. Then the
    // current status register is stored on the stack. When the routine
    // that services the interrupt has finished, the status register
    // and program counter can be restored to how they where before it
    // occurred. This is impemented by the "RTI" instruction. Once the IRQ
    // has happened, in a similar way to a reset, a programmable address
    // is read form hard coded location 0xFFFE, which is subsequently
    // set to the program counter.
    func irq() {
        //If interupts are allowed
        if getFlag(.I) == 0 {
            // Push the program counter to the stack. It's 16-bits dont
            // forget so that takes two pushes
            write(0x0100 + UInt16(stkp), UInt8((pc >> 8) & 0x00FF))
            stkp -= 1
            write(0x0100 + UInt16(stkp), UInt8(pc & 0x00FF))
            stkp -= 1
            
            // Then Push the status register to the stack
            setFlag(.B, false)
            setFlag(.U, true)
            setFlag(.I, true)
            write(0x0100 + UInt16(stkp), status)
            stkp -= 1
            
            // Read new program counter location from fixed address
            addr_abs = 0xFFFE
            let lo = UInt16(read(addr_abs + 0))
            let hi = UInt16(read(addr_abs + 1))
            pc = (hi << 8) | lo
            
            // IRQs take time
            cycles = 7
        }
    }
    
    // A Non-Maskable Interrupt cannot be ignored. It behaves in exactly the
    // same way as a regular IRQ, but reads the new program counter address
    // form location 0xFFFA.
    func nmi() {
        write(0x0100 + UInt16(stkp), UInt8((pc >> 8) & 0x00FF))
        stkp -= 1
        write(0x0100 + UInt16(stkp), UInt8(pc & 0x00FF))
        stkp -= 1
        
        setFlag(.B, false)
        setFlag(.U, true)
        setFlag(.I, true)
        write(0x0100 + UInt16(stkp), status)
        stkp -= 1
        
        addr_abs = 0xFFFA
        let lo = UInt16(read(addr_abs + 0))
        let hi = UInt16(read(addr_abs + 1))
        pc = (hi << 8) | lo
        
        cycles = 8
    }
    
    func clock() {
        // Each instruction requires a variable number of clock cycles to execute.
        // In my emulation, I only care about the final result and so I perform
        // the entire computation in one hit. In hardware, each clock cycle would
        // perform "microcode" style transformations of the CPUs state.
        //
        // To remain compliant with connected devices, it's important that the
        // emulation also takes "time" in order to execute instructions, so I
        // implement that delay by simply counting down the cycles required by
        // the instruction. When it reaches 0, the instruction is complete, and
        // the next one is ready to be executed.
        if cycles == 0 {
            // Read next instruction byte. This 8-bit value is used to index
            // the translation table to get the relevant information about
            // how to implement the instruction
            opcode = read(pc)
            
            #if LOGMODE
            let log_pc = pc
            #endif
            
            // Always set the unused status flag bit to 1
            setFlag(.U, true)

            // Increment program counter, we read the opcode byte
            pc += 1
            
            
            let instruction = lookup[Int(opcode)]
            cycles = instruction.cycles
            
            // Perform fetch of intermmediate data using the
            // required addressing mode
            let additional_cycle1 = instruction.addressingMode.execute(on: self)
            let additional_cycle2 = instruction.operate?() ?? 0
            
            // The addressmode and opcode may have altered the number
            // of cycles this instruction requires before its completed
            cycles += (additional_cycle1 & additional_cycle2)

            // Always set the unused status flag bit to 1
            setFlag(.U, true)
            
            #if LOGMODE
            // Logging implementation would go here
            #endif
        }
        
        clock_count += 1
        cycles -= 1
    }
    
    func complete() -> Bool {
        return cycles == 0
    }
    
    func connectBus(_ n: Bus) {
        bus = n
    }
    
    func disassemble(nStart: UInt16, nStop: UInt16) -> [UInt16: String] {
        var addr = UInt32(nStart)
        var value: UInt8 = 0x00
        var lo: UInt8 = 0x00
        var hi: UInt8 = 0x00
        var mapLines: [UInt16: String] = [:]
        var line_addr: UInt16 = 0
        
        func hex(_ n: UInt32, _ d: Int) -> String {
            let format = String(format: "%%0%dX", d)
            return String(format: format, n)
        }
        
        while addr <= UInt32(nStop) {
            line_addr = UInt16(addr)
            
            var sInst = "$" + hex(addr, 4) + ": "
            
            let opcode = bus?.read(address: UInt16(addr)) ?? 0
            addr += 1
            sInst += lookup[Int(opcode)].name + " "
            
            let instruction = lookup[Int(opcode)]
            
            if instruction.addressingMode == .IMP {
                sInst += " {IMP}"
            } else if instruction.addressingMode == .IMM {
                value = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                sInst += "#$" + hex(UInt32(value), 2) + " {IMM}"
            } else if instruction.addressingMode == .ZP0 {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = 0x00
                sInst += "$" + hex(UInt32(lo), 2) + " {ZP0}"
            } else if instruction.addressingMode == .ZPX {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = 0x00
                sInst += "$" + hex(UInt32(lo), 2) + ", X {ZPX}"
            } else if instruction.addressingMode == .ZPY {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = 0x00
                sInst += "$" + hex(UInt32(lo), 2) + ", Y {ZPY}"
            } else if instruction.addressingMode == .IZX {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = 0x00
                sInst += "($" + hex(UInt32(lo), 2) + ", X) {IZX}"
            } else if instruction.addressingMode == .IZY {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = 0x00
                sInst += "($" + hex(UInt32(lo), 2) + "), Y {IZY}"
            } else if instruction.addressingMode == .ABS {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                sInst += "$" + hex(UInt32((UInt16(hi) << 8) | UInt16(lo)), 4) + " {ABS}"
            } else if instruction.addressingMode == .ABX {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                sInst += "$" + hex(UInt32((UInt16(hi) << 8) | UInt16(lo)), 4) + ", X {ABX}"
            } else if instruction.addressingMode == .ABY {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                sInst += "$" + hex(UInt32((UInt16(hi) << 8) | UInt16(lo)), 4) + ", Y {ABY}"
            } else if instruction.addressingMode == .IND {
                lo = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                hi = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                sInst += "($" + hex(UInt32((UInt16(hi) << 8) | UInt16(lo)), 4) + ") {IND}"
            } else if instruction.addressingMode == .REL {
                value = bus?.read(address: UInt16(addr)) ?? 0
                addr += 1
                sInst += "$" + hex(UInt32(value), 2) + " [$" + hex(addr + UInt32(value), 4) + "] {REL}"
            }
            
            mapLines[line_addr] = sInst
        }
        
        return mapLines
    }
    
    private func getFlag(_ f: FLAGS6502) -> UInt8 {
        return (status & f.rawValue) > 0 ? 1 : 0
    }
    
    private func setFlag(_ f: FLAGS6502, _ v: Bool) {
        // If ⁠FLAGS6502.N (Negative flag) has ⁠rawValue = 0b10000000:
        //     setFlag(.N, true)   -> sets the Negative bit in ⁠status
        // ⁠    setFlag(.N, false)  -> clears the Negative bit in ⁠status
        if v {
            status |= f.rawValue
        } else {
            // bitwise NOT
            status &= ~f.rawValue
        }
    }
    
    private func read(_ a: UInt16) -> UInt8 {
        return bus?.read(address: a) ?? 0x00
    }
    
    private func write(_ a: UInt16, _ d: UInt8) {
        bus?.write(address: a, data: d)
    }
    
    private func fetch() -> UInt8 {
        if !(lookup[Int(opcode)].addressingMode == .IMP) {
            fetched = read(addr_abs)
        }
        return fetched
    }
    
    // MARK: Addressing Modes
    // Implied addressing
    private func IMP() -> UInt8 {
        fetched = a
        return 0
    }

    // Immediate addressing
    private func IMM() -> UInt8 {
        addr_abs = pc
        pc += 1
        return 0
    }

    // Zero Page addressing
    private func ZP0() -> UInt8 {
        addr_abs = UInt16(read(pc))
        pc += 1
        addr_abs &= 0x00FF
        return 0
    }

    // Zero Page,X addressing
    private func ZPX() -> UInt8 {
        addr_abs = UInt16(read(pc) &+ x)
        pc += 1
        addr_abs &= 0x00FF
        return 0
    }

    // Zero Page,Y addressing
    private func ZPY() -> UInt8 {
        addr_abs = UInt16(read(pc) &+ y)
        pc += 1
        addr_abs &= 0x00FF
        return 0
    }

    // Relative addressing
    private func REL() -> UInt8 {
        addr_rel = UInt16(read(pc))
        pc += 1
        if (addr_rel & 0x80) != 0 {
            addr_rel |= 0xFF00
        }
        return 0
    }

    // Absolute addressing
    private func ABS() -> UInt8 {
        let lo = UInt16(read(pc))
        pc += 1
        let hi = UInt16(read(pc))
        pc += 1
        addr_abs = (hi << 8) | lo
        return 0
    }

    // Absolute,X addressing
    private func ABX() -> UInt8 {
        let lo = UInt16(read(pc))
        pc += 1
        let hi = UInt16(read(pc))
        pc += 1
        addr_abs = (hi << 8) | lo
        addr_abs &+= UInt16(x)
        if (addr_abs & 0xFF00) != (hi << 8) {
            return 1
        } else {
            return 0
        }
    }

    // Absolute,Y addressing
    private func ABY() -> UInt8 {
        let lo = UInt16(read(pc))
        pc += 1
        let hi = UInt16(read(pc))
        pc += 1
        addr_abs = (hi << 8) | lo
        addr_abs &+= UInt16(y)
        if (addr_abs & 0xFF00) != (hi << 8) {
            return 1
        } else {
            return 0
        }
    }

    // Indirect addressing
    private func IND() -> UInt8 {
        let ptr_lo = UInt16(read(pc))
        pc += 1
        let ptr_hi = UInt16(read(pc))
        pc += 1
        let ptr = (ptr_hi << 8) | ptr_lo
        if ptr_lo == 0x00FF {
            addr_abs = (UInt16(read(ptr & 0xFF00)) << 8) | UInt16(read(ptr + 0))
        } else {
            addr_abs = (UInt16(read(ptr + 1)) << 8) | UInt16(read(ptr + 0))
        }
        return 0
    }

    // Indexed Indirect,X addressing
    private func IZX() -> UInt8 {
        let t = UInt16(read(pc))
        pc += 1
        let lo = UInt16(read((t &+ UInt16(x)) & 0x00FF))
        let hi = UInt16(read((t &+ UInt16(x) &+ 1) & 0x00FF))
        addr_abs = (hi << 8) | lo
        return 0
    }

    // Indirect Indexed,Y addressing
    private func IZY() -> UInt8 {
        let t = UInt16(read(pc))
        pc += 1
        let lo = UInt16(read(t & 0x00FF))
        let hi = UInt16(read((t + 1) & 0x00FF))
        addr_abs = (hi << 8) | lo
        addr_abs &+= UInt16(y)
        if (addr_abs & 0xFF00) != (hi << 8) {
            return 1
        } else {
            return 0
        }
    }

    
    // MARK: Opcodes
    // Add with Carry
    private func ADC() -> UInt8 {
        _ = fetch()
        temp = UInt16(a) &+ UInt16(fetched) &+ UInt16(getFlag(.C))
        setFlag(.C, temp > 255)
        setFlag(.Z, (temp & 0x00FF) == 0)
        setFlag(.V, (~(UInt16(a) ^ UInt16(fetched)) & (UInt16(a) ^ temp)) & 0x0080 != 0)
        setFlag(.N, temp & 0x80 != 0)
        a = UInt8(temp & 0x00FF)
        return 1
    }

    // Logical AND
    private func AND() -> UInt8 {
        _ = fetch()
        a = a & fetched
        setFlag(.Z, a == 0x00)
        setFlag(.N, a & 0x80 != 0)
        return 1
    }

    // Arithmetic Shift Left
    private func ASL() -> UInt8 {
        _ = fetch()
        temp = UInt16(fetched) << 1
        setFlag(.C, (temp & 0xFF00) > 0)
        setFlag(.Z, (temp & 0x00FF) == 0x00)
        setFlag(.N, temp & 0x80 != 0)
        if lookup[Int(opcode)].addressingMode == .IMP {
            a = UInt8(temp & 0x00FF)
        } else {
            write(addr_abs, UInt8(temp & 0x00FF))
        }
        return 0
    }

    // Branch if Carry Clear
    private func BCC() -> UInt8 {
        if getFlag(.C) == 0 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Branch if Carry Set
    private func BCS() -> UInt8 {
        if getFlag(.C) == 1 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Branch if Equal
    private func BEQ() -> UInt8 {
        if getFlag(.Z) == 1 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Bit Test
    private func BIT() -> UInt8 {
        _ = fetch()
        temp = UInt16(a & fetched)
        setFlag(.Z, (temp & 0x00FF) == 0x00)
        setFlag(.N, fetched & (1 << 7) != 0)
        setFlag(.V, fetched & (1 << 6) != 0)
        return 0
    }

    // Branch if Minus
    private func BMI() -> UInt8 {
        if getFlag(.N) == 1 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Branch if Not Equal
    private func BNE() -> UInt8 {
        if getFlag(.Z) == 0 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Branch if Positive
    private func BPL() -> UInt8 {
        if getFlag(.N) == 0 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Force Interrupt
    private func BRK() -> UInt8 {
        pc += 1
        setFlag(.I, true)
        write(0x0100 + UInt16(stkp), UInt8((pc >> 8) & 0x00FF))
        stkp -= 1
        write(0x0100 + UInt16(stkp), UInt8(pc & 0x00FF))
        stkp -= 1
        setFlag(.B, true)
        write(0x0100 + UInt16(stkp), status)
        stkp -= 1
        setFlag(.B, false)
        pc = UInt16(read(0xFFFE)) | (UInt16(read(0xFFFF)) << 8)
        return 0
    }

    // Branch if Overflow Clear
    private func BVC() -> UInt8 {
        if getFlag(.V) == 0 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Branch if Overflow Set
    private func BVS() -> UInt8 {
        if getFlag(.V) == 1 {
            cycles += 1
            addr_abs = pc &+ addr_rel
            if (addr_abs & 0xFF00) != (pc & 0xFF00) {
                cycles += 1
            }
            pc = addr_abs
        }
        return 0
    }

    // Clear Carry Flag
    private func CLC() -> UInt8 {
        setFlag(.C, false)
        return 0
    }

    // Clear Decimal Mode
    private func CLD() -> UInt8 {
        setFlag(.D, false)
        return 0
    }

    // Clear Interrupt Disable
    private func CLI() -> UInt8 {
        setFlag(.I, false)
        return 0
    }

    // Clear Overflow Flag
    private func CLV() -> UInt8 {
        setFlag(.V, false)
        return 0
    }

    // Compare Accumulator
    private func CMP() -> UInt8 {
        _ = fetch()
        temp = UInt16(a) &- UInt16(fetched)
        setFlag(.C, a >= fetched)
        setFlag(.Z, (temp & 0x00FF) == 0x0000)
        setFlag(.N, temp & 0x0080 != 0)
        return 1
    }

    // Compare X Register
    private func CPX() -> UInt8 {
        _ = fetch()
        temp = UInt16(x) &- UInt16(fetched)
        setFlag(.C, x >= fetched)
        setFlag(.Z, (temp & 0x00FF) == 0x0000)
        setFlag(.N, temp & 0x0080 != 0)
        return 0
    }

    // Compare Y Register
    private func CPY() -> UInt8 {
        _ = fetch()
        temp = UInt16(y) &- UInt16(fetched)
        setFlag(.C, y >= fetched)
        setFlag(.Z, (temp & 0x00FF) == 0x0000)
        setFlag(.N, temp & 0x0080 != 0)
        return 0
    }

    // Decrement Memory
    private func DEC() -> UInt8 {
        _ = fetch()
        temp = UInt16(fetched &- 1)
        write(addr_abs, UInt8(temp & 0x00FF))
        setFlag(.Z, (temp & 0x00FF) == 0x0000)
        setFlag(.N, temp & 0x0080 != 0)
        return 0
    }

    // Decrement X Register
    private func DEX() -> UInt8 {
        x &-= 1
        setFlag(.Z, x == 0x00)
        setFlag(.N, x & 0x80 != 0)
        return 0
    }

    // Decrement Y Register
    private func DEY() -> UInt8 {
        y &-= 1
        setFlag(.Z, y == 0x00)
        setFlag(.N, y & 0x80 != 0)
        return 0
    }

    // Exclusive OR
    private func EOR() -> UInt8 {
        _ = fetch()
        a = a ^ fetched
        setFlag(.Z, a == 0x00)
        setFlag(.N, a & 0x80 != 0)
        return 1
    }

    // Increment Memory
    private func INC() -> UInt8 {
        _ = fetch()
        temp = UInt16(fetched &+ 1)
        write(addr_abs, UInt8(temp & 0x00FF))
        setFlag(.Z, (temp & 0x00FF) == 0x0000)
        setFlag(.N, temp & 0x0080 != 0)
        return 0
    }

    // Increment X Register
    private func INX() -> UInt8 {
        x &+= 1
        setFlag(.Z, x == 0x00)
        setFlag(.N, x & 0x80 != 0)
        return 0
    }

    // Increment Y Register
    private func INY() -> UInt8 {
        y &+= 1
        setFlag(.Z, y == 0x00)
        setFlag(.N, y & 0x80 != 0)
        return 0
    }

    // Jump
    private func JMP() -> UInt8 {
        pc = addr_abs
        return 0
    }

    // Jump to Subroutine
    private func JSR() -> UInt8 {
        pc -= 1
        write(0x0100 + UInt16(stkp), UInt8((pc >> 8) & 0x00FF))
        stkp -= 1
        write(0x0100 + UInt16(stkp), UInt8(pc & 0x00FF))
        stkp -= 1
        pc = addr_abs
        return 0
    }

    // Load Accumulator
    private func LDA() -> UInt8 {
        _ = fetch()
        a = fetched
        setFlag(.Z, a == 0x00)
        setFlag(.N, a & 0x80 != 0)
        return 1
    }

    // Load X Register
    private func LDX() -> UInt8 {
        _ = fetch()
        x = fetched
        setFlag(.Z, x == 0x00)
        setFlag(.N, x & 0x80 != 0)
        return 1
    }

    // Load Y Register
    private func LDY() -> UInt8 {
        _ = fetch()
        y = fetched
        setFlag(.Z, y == 0x00)
        setFlag(.N, y & 0x80 != 0)
        return 1
    }

    // Logical Shift Right
    private func LSR() -> UInt8 {
        _ = fetch()
        setFlag(.C, fetched & 0x0001 != 0)
        temp = UInt16(fetched >> 1)
        setFlag(.Z, (temp & 0x00FF) == 0x0000)
        setFlag(.N, temp & 0x0080 != 0)
        if lookup[Int(opcode)].addressingMode == .IMP {
            a = UInt8(temp & 0x00FF)
        } else {
            write(addr_abs, UInt8(temp & 0x00FF))
        }
        return 0
    }

    // No Operation
    private func NOP() -> UInt8 {
        switch opcode {
        case 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC:
            return 1
        default:
            return 0
        }
    }

    // Logical Inclusive OR
    private func ORA() -> UInt8 {
        _ = fetch()
        a = a | fetched
        setFlag(.Z, a == 0x00)
        setFlag(.N, a & 0x80 != 0)
        return 1
    }

    // Push Accumulator
    private func PHA() -> UInt8 {
        write(0x0100 + UInt16(stkp), a)
        stkp -= 1
        return 0
    }

    // Push Processor Status
    private func PHP() -> UInt8 {
        write(0x0100 + UInt16(stkp), status | FLAGS6502.B.rawValue | FLAGS6502.U.rawValue)
        setFlag(.B, false)
        setFlag(.U, false)
        stkp -= 1
        return 0
    }

    // Pull Accumulator
    private func PLA() -> UInt8 {
        stkp += 1
        a = read(0x0100 + UInt16(stkp))
        setFlag(.Z, a == 0x00)
        setFlag(.N, a & 0x80 != 0)
        return 0
    }

    // Pull Processor Status
    private func PLP() -> UInt8 {
        stkp += 1
        status = read(0x0100 + UInt16(stkp))
        setFlag(.U, true)
        return 0
    }

    // Rotate Left
    private func ROL() -> UInt8 {
        _ = fetch()
        temp = (UInt16(fetched) << 1) | UInt16(getFlag(.C))
        setFlag(.C, temp & 0xFF00 != 0)
        setFlag(.Z, (temp & 0x00FF) == 0x0000)
        setFlag(.N, temp & 0x0080 != 0)
        if lookup[Int(opcode)].addressingMode == .IMP {
            a = UInt8(temp & 0x00FF)
        } else {
            write(addr_abs, UInt8(temp & 0x00FF))
        }
        return 0
    }

    // Rotate Right
    private func ROR() -> UInt8 {
        _ = fetch()
        temp = (UInt16(getFlag(.C)) << 7) | (UInt16(fetched) >> 1)
        setFlag(.C, fetched & 0x01 != 0)
        setFlag(.Z, (temp & 0x00FF) == 0x00)
        setFlag(.N, temp & 0x0080 != 0)
        if lookup[Int(opcode)].addressingMode == .IMP {
            a = UInt8(temp & 0x00FF)
        } else {
            write(addr_abs, UInt8(temp & 0x00FF))
        }
        return 0
    }

    // Return from Interrupt
    private func RTI() -> UInt8 {
        stkp += 1
        status = read(0x0100 + UInt16(stkp))
        status &= ~FLAGS6502.B.rawValue
        status &= ~FLAGS6502.U.rawValue
        stkp += 1
        pc = UInt16(read(0x0100 + UInt16(stkp)))
        stkp += 1
        pc |= UInt16(read(0x0100 + UInt16(stkp))) << 8
        return 0
    }

    // Return from Subroutine
    private func RTS() -> UInt8 {
        stkp += 1
        pc = UInt16(read(0x0100 + UInt16(stkp)))
        stkp += 1
        pc |= UInt16(read(0x0100 + UInt16(stkp))) << 8
        pc += 1
        return 0
    }

    // Subtract with Carry
    private func SBC() -> UInt8 {
        _ = fetch()
        let value = UInt16(fetched) ^ 0x00FF
        temp = UInt16(a) &+ value &+ UInt16(getFlag(.C))
        setFlag(.C, temp & 0xFF00 != 0)
        setFlag(.Z, (temp & 0x00FF) == 0)
        setFlag(.V, (temp ^ UInt16(a)) & (temp ^ value) & 0x0080 != 0)
        setFlag(.N, temp & 0x0080 != 0)
        a = UInt8(temp & 0x00FF)
        return 1
    }

    // Set Carry Flag
    private func SEC() -> UInt8 {
        setFlag(.C, true)
        return 0
    }

    // Set Decimal Flag
    private func SED() -> UInt8 {
        setFlag(.D, true)
        return 0
    }

    // Set Interrupt Disable
    private func SEI() -> UInt8 {
        setFlag(.I, true)
        return 0
    }

    // Store Accumulator
    private func STA() -> UInt8 {
        write(addr_abs, a)
        return 0
    }

    // Store X Register
    private func STX() -> UInt8 {
        write(addr_abs, x)
        return 0
    }

    // Store Y Register
    private func STY() -> UInt8 {
        write(addr_abs, y)
        return 0
    }

    // Transfer Accumulator to X
    private func TAX() -> UInt8 {
        x = a
        setFlag(.Z, x == 0x00)
        setFlag(.N, x & 0x80 != 0)
        return 0
    }

    // Transfer Accumulator to Y
    private func TAY() -> UInt8 {
        y = a
        setFlag(.Z, y == 0x00)
        setFlag(.N, y & 0x80 != 0)
        return 0
    }

    // Transfer Stack Pointer to X
    private func TSX() -> UInt8 {
        x = stkp
        setFlag(.Z, x == 0x00)
        setFlag(.N, x & 0x80 != 0)
        return 0
    }

    // Transfer X to Accumulator
    private func TXA() -> UInt8 {
        a = x
        setFlag(.Z, a == 0x00)
        setFlag(.N, a & 0x80 != 0)
        return 0
    }

    // Transfer X to Stack Pointer
    private func TXS() -> UInt8 {
        stkp = x
        return 0
    }

    // Transfer Y to Accumulator
    private func TYA() -> UInt8 {
        a = y
        setFlag(.Z, a == 0x00)
        setFlag(.N, a & 0x80 != 0)
        return 0
    }

    // Illegal Opcode
    private func XXX() -> UInt8 {
        return 0
    }

    
    private func setupInstructionTable() {
        lookup = [
            // MARK: Translation Table
            Instruction(name: "BRK", operate: BRK, addressingMode: .IMM, cycles: 7),
            Instruction(name: "ORA", operate: ORA, addressingMode: .IZX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 3),
            Instruction(name: "ORA", operate: ORA, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "ASL", operate: ASL, addressingMode: .ZP0, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "PHP", operate: PHP, addressingMode: .IMP, cycles: 3),
            Instruction(name: "ORA", operate: ORA, addressingMode: .IMM, cycles: 2),
            Instruction(name: "ASL", operate: ASL, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "ORA", operate: ORA, addressingMode: .ABS, cycles: 4),
            Instruction(name: "ASL", operate: ASL, addressingMode: .ABS, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            
            Instruction(name: "BPL", operate: BPL, addressingMode: .REL, cycles: 2),
            Instruction(name: "ORA", operate: ORA, addressingMode: .IZY, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "ORA", operate: ORA, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "ASL", operate: ASL, addressingMode: .ZPX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "CLC", operate: CLC, addressingMode: .IMP, cycles: 2),
            Instruction(name: "ORA", operate: ORA, addressingMode: .ABY, cycles: 4),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "ORA", operate: ORA, addressingMode: .ABX, cycles: 4),
            Instruction(name: "ASL", operate: ASL, addressingMode: .ABX, cycles: 7),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            
            Instruction(name: "JSR", operate: JSR, addressingMode: .ABS, cycles: 6),
            Instruction(name: "AND", operate: AND, addressingMode: .IZX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "BIT", operate: BIT, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "AND", operate: AND, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "ROL", operate: ROL, addressingMode: .ZP0, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "PLP", operate: PLP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "AND", operate: AND, addressingMode: .IMM, cycles: 2),
            Instruction(name: "ROL", operate: ROL, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "BIT", operate: BIT, addressingMode: .ABS, cycles: 4),
            Instruction(name: "AND", operate: AND, addressingMode: .ABS, cycles: 4),
            Instruction(name: "ROL", operate: ROL, addressingMode: .ABS, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            
            Instruction(name: "BMI", operate: BMI, addressingMode: .REL, cycles: 2),
            Instruction(name: "AND", operate: AND, addressingMode: .IZY, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "AND", operate: AND, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "ROL", operate: ROL, addressingMode: .ZPX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "SEC", operate: SEC, addressingMode: .IMP, cycles: 2),
            Instruction(name: "AND", operate: AND, addressingMode: .ABY, cycles: 4),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "AND", operate: AND, addressingMode: .ABX, cycles: 4),
            Instruction(name: "ROL", operate: ROL, addressingMode: .ABX, cycles: 7),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            
            Instruction(name: "RTI", operate: RTI, addressingMode: .IMP, cycles: 6),
            Instruction(name: "EOR", operate: EOR, addressingMode: .IZX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 3),
            Instruction(name: "EOR", operate: EOR, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "LSR", operate: LSR, addressingMode: .ZP0, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "PHA", operate: PHA, addressingMode: .IMP, cycles: 3),
            Instruction(name: "EOR", operate: EOR, addressingMode: .IMM, cycles: 2),
            Instruction(name: "LSR", operate: LSR, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "JMP", operate: JMP, addressingMode: .ABS, cycles: 3),
            Instruction(name: "EOR", operate: EOR, addressingMode: .ABS, cycles: 4),
            Instruction(name: "LSR", operate: LSR, addressingMode: .ABS, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            
            Instruction(name: "BVC", operate: BVC, addressingMode: .REL, cycles: 2),
            Instruction(name: "EOR", operate: EOR, addressingMode: .IZY, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "EOR", operate: EOR, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "LSR", operate: LSR, addressingMode: .ZPX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "CLI", operate: CLI, addressingMode: .IMP, cycles: 2),
            Instruction(name: "EOR", operate: EOR, addressingMode: .ABY, cycles: 4),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "EOR", operate: EOR, addressingMode: .ABX, cycles: 4),
            Instruction(name: "LSR", operate: LSR, addressingMode: .ABX, cycles: 7),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            
            Instruction(name: "RTS", operate: RTS, addressingMode: .IMP, cycles: 6),
            Instruction(name: "ADC", operate: ADC, addressingMode: .IZX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 3),
            Instruction(name: "ADC", operate: ADC, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "ROR", operate: ROR, addressingMode: .ZP0, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "PLA", operate: PLA, addressingMode: .IMP, cycles: 4),
            Instruction(name: "ADC", operate: ADC, addressingMode: .IMM, cycles: 2),
            Instruction(name: "ROR", operate: ROR, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "JMP", operate: JMP, addressingMode: .IND, cycles: 5),
            Instruction(name: "ADC", operate: ADC, addressingMode: .ABS, cycles: 4),
            Instruction(name: "ROR", operate: ROR, addressingMode: .ABS, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            
            Instruction(name: "BVS", operate: BVS, addressingMode: .REL, cycles: 2),
            Instruction(name: "ADC", operate: ADC, addressingMode: .IZY, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "ADC", operate: ADC, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "ROR", operate: ROR, addressingMode: .ZPX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "SEI", operate: SEI, addressingMode: .IMP, cycles: 2),
            Instruction(name: "ADC", operate: ADC, addressingMode: .ABY, cycles: 4),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "ADC", operate: ADC, addressingMode: .ABX, cycles: 4),
            Instruction(name: "ROR", operate: ROR, addressingMode: .ABX, cycles: 7),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "STA", operate: STA, addressingMode: .IZX, cycles: 6),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "STY", operate: STY, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "STA", operate: STA, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "STX", operate: STX, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 3),
            Instruction(name: "DEY", operate: DEY, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "TXA", operate: TXA, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "STY", operate: STY, addressingMode: .ABS, cycles: 4),
            Instruction(name: "STA", operate: STA, addressingMode: .ABS, cycles: 4),
            Instruction(name: "STX", operate: STX, addressingMode: .ABS, cycles: 4),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 4),
            
            Instruction(name: "BCC", operate: BCC, addressingMode: .REL, cycles: 2),
            Instruction(name: "STA", operate: STA, addressingMode: .IZY, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "STY", operate: STY, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "STA", operate: STA, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "STX", operate: STX, addressingMode: .ZPY, cycles: 4),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 4),
            Instruction(name: "TYA", operate: TYA, addressingMode: .IMP, cycles: 2),
            Instruction(name: "STA", operate: STA, addressingMode: .ABY, cycles: 5),
            Instruction(name: "TXS", operate: TXS, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 5),
            Instruction(name: "STA", operate: STA, addressingMode: .ABX, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            
            Instruction(name: "LDY", operate: LDY, addressingMode: .IMM, cycles: 2),
            Instruction(name: "LDA", operate: LDA, addressingMode: .IZX, cycles: 6),
            Instruction(name: "LDX", operate: LDX, addressingMode: .IMM, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "LDY", operate: LDY, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "LDA", operate: LDA, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "LDX", operate: LDX, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 3),
            Instruction(name: "TAY", operate: TAY, addressingMode: .IMP, cycles: 2),
            Instruction(name: "LDA", operate: LDA, addressingMode: .IMM, cycles: 2),
            Instruction(name: "TAX", operate: TAX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "LDY", operate: LDY, addressingMode: .ABS, cycles: 4),
            Instruction(name: "LDA", operate: LDA, addressingMode: .ABS, cycles: 4),
            Instruction(name: "LDX", operate: LDX, addressingMode: .ABS, cycles: 4),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 4),
            
            Instruction(name: "BCS", operate: BCS, addressingMode: .REL, cycles: 2),
            Instruction(name: "LDA", operate: LDA, addressingMode: .IZY, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "LDY", operate: LDY, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "LDA", operate: LDA, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "LDX", operate: LDX, addressingMode: .ZPY, cycles: 4),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 4),
            Instruction(name: "CLV", operate: CLV, addressingMode: .IMP, cycles: 2),
            Instruction(name: "LDA", operate: LDA, addressingMode: .ABY, cycles: 4),
            Instruction(name: "TSX", operate: TSX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 4),
            Instruction(name: "LDY", operate: LDY, addressingMode: .ABX, cycles: 4),
            Instruction(name: "LDA", operate: LDA, addressingMode: .ABX, cycles: 4),
            Instruction(name: "LDX", operate: LDX, addressingMode: .ABY, cycles: 4),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 4),
            
            Instruction(name: "CPY", operate: CPY, addressingMode: .IMM, cycles: 2),
            Instruction(name: "CMP", operate: CMP, addressingMode: .IZX, cycles: 6),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "CPY", operate: CPY, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "CMP", operate: CMP, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "DEC", operate: DEC, addressingMode: .ZP0, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "INY", operate: INY, addressingMode: .IMP, cycles: 2),
            Instruction(name: "CMP", operate: CMP, addressingMode: .IMM, cycles: 2),
            Instruction(name: "DEX", operate: DEX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "CPY", operate: CPY, addressingMode: .ABS, cycles: 4),
            Instruction(name: "CMP", operate: CMP, addressingMode: .ABS, cycles: 4),
            Instruction(name: "DEC", operate: DEC, addressingMode: .ABS, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            
            Instruction(name: "BNE", operate: BNE, addressingMode: .REL, cycles: 2),
            Instruction(name: "CMP", operate: CMP, addressingMode: .IZY, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "CMP", operate: CMP, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "DEC", operate: DEC, addressingMode: .ZPX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "CLD", operate: CLD, addressingMode: .IMP, cycles: 2),
            Instruction(name: "CMP", operate: CMP, addressingMode: .ABY, cycles: 4),
            Instruction(name: "NOP", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "CMP", operate: CMP, addressingMode: .ABX, cycles: 4),
            Instruction(name: "DEC", operate: DEC, addressingMode: .ABX, cycles: 7),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            
            Instruction(name: "CPX", operate: CPX, addressingMode: .IMM, cycles: 2),
            Instruction(name: "SBC", operate: SBC, addressingMode: .IZX, cycles: 6),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "CPX", operate: CPX, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "SBC", operate: SBC, addressingMode: .ZP0, cycles: 3),
            Instruction(name: "INC", operate: INC, addressingMode: .ZP0, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 5),
            Instruction(name: "INX", operate: INX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "SBC", operate: SBC, addressingMode: .IMM, cycles: 2),
            Instruction(name: "NOP", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: SBC, addressingMode: .IMP, cycles: 2),
            Instruction(name: "CPX", operate: CPX, addressingMode: .ABS, cycles: 4),
            Instruction(name: "SBC", operate: SBC, addressingMode: .ABS, cycles: 4),
            Instruction(name: "INC", operate: INC, addressingMode: .ABS, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            
            Instruction(name: "BEQ", operate: BEQ, addressingMode: .REL, cycles: 2),
            Instruction(name: "SBC", operate: SBC, addressingMode: .IZY, cycles: 5),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 8),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "SBC", operate: SBC, addressingMode: .ZPX, cycles: 4),
            Instruction(name: "INC", operate: INC, addressingMode: .ZPX, cycles: 6),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 6),
            Instruction(name: "SED", operate: SED, addressingMode: .IMP, cycles: 2),
            Instruction(name: "SBC", operate: SBC, addressingMode: .ABY, cycles: 4),
            Instruction(name: "NOP", operate: NOP, addressingMode: .IMP, cycles: 2),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7),
            Instruction(name: "???", operate: NOP, addressingMode: .IMP, cycles: 4),
            Instruction(name: "SBC", operate: SBC, addressingMode: .ABX, cycles: 4),
            Instruction(name: "INC", operate: INC, addressingMode: .ABX, cycles: 7),
            Instruction(name: "???", operate: XXX, addressingMode: .IMP, cycles: 7)
        ]
    }
}
