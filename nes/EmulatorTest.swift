//
//  EmulatorTest.swift
//  nes
//
//  Created by mike on 7/28/25.
//

import Foundation

extension EmulatorTest {
    func executeOneInstruction() {
        repeat {
            bus.cpu.clock()
        } while !bus.cpu.complete()
    }
    
    func completeReset() {
        bus.cpu.reset()
        while !bus.cpu.complete() {
            bus.cpu.clock()
        }
    }
    
    func printMemoryDump(from start: UInt16, length: Int = 128) {
        print("\nMemory dump from $\(String(format: "%04X", start)):")
        print("      00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")
        print("      -----------------------------------------------")
        
        for i in stride(from: 0, to: length, by: 16) {
            print("$\(String(format: "%04X", start + UInt16(i))): ", terminator: "")
            
            // Print hex values
            for j in 0..<16 {
                if i + j < length {
                    let value = bus.ram[Int(start) + i + j]
                    print(String(format: "%02X", value), terminator: " ")
                } else {
                    print("   ", terminator: "")
                }
            }
            
            // Print ASCII representation
            print(" |", terminator: "")
            for j in 0..<16 {
                if i + j < length {
                    let value = bus.ram[Int(start) + i + j]
                    if value >= 32 && value <= 126 {
                        print(String(Character(UnicodeScalar(value))), terminator: "")
                    } else {
                        print(".", terminator: "")
                    }
                }
            }
            print("|")
        }
        print()
    }
    
    func printStack() {
        print("\nStack (SP = $\(String(format: "%02X", bus.cpu.stkp)):")
        // Stack is at 0x0100-0x01FF, grows downward
        let stackStart = 0x01FF
        let stackPointer = 0x0100 + Int(bus.cpu.stkp)
        
        for addr in stride(from: stackStart, to: stackPointer, by: -1) {
            let value = bus.ram[addr]
            let marker = addr == stackPointer + 1 ? "SP→" : "   "
            print("\(marker) $\(String(format: "%04X", addr)): $\(String(format: "%02X", value))")
        }
        print()
    }
}

class EmulatorTest {
    let bus = SystemBus()
    
    func loadProgram(_ bytes: [UInt8], at address: UInt16 = 0x8000) {
        for (offset, byte) in bytes.enumerated() {
            bus.ram[Int(address) + offset] = byte
        }
        
        // Set reset vector to point to our program
        bus.ram[0xFFFC] = UInt8(address & 0xFF)        // Low byte
        bus.ram[0xFFFD] = UInt8((address >> 8) & 0xFF) // High byte
        
        // Debug: verify reset vector
        print("Reset vector set to: $\(String(format: "%04X", address))")
        print("RAM[$FFFC] = $\(String(format: "%02X", bus.ram[0xFFFC]))")
        print("RAM[$FFFD] = $\(String(format: "%02X", bus.ram[0xFFFD]))")
    }
    
    func printCPUState() {
        let cpu = bus.cpu
        print("PC: $\(String(format: "%04X", cpu.pc))  " +
              "A: $\(String(format: "%02X", cpu.a))  " +
              "X: $\(String(format: "%02X", cpu.x))  " +
              "Y: $\(String(format: "%02X", cpu.y))  " +
              "SP: $\(String(format: "%02X", cpu.stkp))  " +
              "Status: \(formatStatus(cpu.status))")
    }
    
    func formatStatus(_ status: UInt8) -> String {
        return "NV-BDIZC: " +
               "\(status & 0x80 != 0 ? "N" : "n")" +
               "\(status & 0x40 != 0 ? "V" : "v")" +
               "-" +
               "\(status & 0x10 != 0 ? "B" : "b")" +
               "\(status & 0x08 != 0 ? "D" : "d")" +
               "\(status & 0x04 != 0 ? "I" : "i")" +
               "\(status & 0x02 != 0 ? "Z" : "z")" +
               "\(status & 0x01 != 0 ? "C" : "c")"
    }
}

func testNOP() {
    print("=== Testing NOP ===")
    let test = EmulatorTest()
    
    test.loadProgram([0xEA, 0xEA, 0xEA])
    test.completeReset()  // Reset and wait for completion
    
    print("After reset:")
    test.printCPUState()
    
    let pcBefore = test.bus.cpu.pc
    test.executeOneInstruction()  // Execute NOP
    
    print("After NOP:")
    test.printCPUState()
    
    assert(test.bus.cpu.pc == pcBefore + 1, "NOP should increment PC by 1")
    print("✓ NOP test passed\n")
}

func testLDAImmediate() {
    print("=== Testing LDA Immediate ===")
    let test = EmulatorTest()
    
    // LDA #$42 = 0xA9 0x42
    test.loadProgram([0xA9, 0x42])
    test.completeReset()  // Using the helper function
    
    print("After reset:")
    test.printCPUState()
    
    // Check what instruction we're about to execute
    let opcode = test.bus.ram[Int(test.bus.cpu.pc)]
    print("Opcode at PC: $\(String(format: "%02X", opcode)) (should be $A9)")
    
    // Execute LDA #$42
    test.executeOneInstruction()
    
    print("After LDA #$42:")
    test.printCPUState()
    
    print("A register: $\(String(format: "%02X", test.bus.cpu.a)) (should be $42)")
    print("Zero flag: \(test.bus.cpu.status & 0x02 != 0) (should be false)")
    print("Negative flag: \(test.bus.cpu.status & 0x80 != 0) (should be false)")
    
    assert(test.bus.cpu.a == 0x42, "A register should be 0x42")
    assert(test.bus.cpu.status & 0x02 == 0, "Zero flag should be clear")
    assert(test.bus.cpu.status & 0x80 == 0, "Negative flag should be clear")
    print("✓ LDA test passed\n")
}

func testMultiplicationProgram() {
    print("=== Testing 10 × 3 Multiplication ===")
    let test = EmulatorTest()
    
    let program: [UInt8] = [
        0xA2, 0x0A,       // LDX #10      ; X = 10
        0x8E, 0x00, 0x00, // STX $0000    ; Store 10 at address 0
        0xA2, 0x03,       // LDX #3       ; X = 3
        0x8E, 0x01, 0x00, // STX $0001    ; Store 3 at address 1
        0xAC, 0x00, 0x00, // LDY $0000    ; Y = 10 (loop counter)
        0xA9, 0x00,       // LDA #0       ; A = 0 (accumulator)
        0x18,             // CLC          ; Clear carry
        // loop:
        0x6D, 0x01, 0x00, // ADC $0001    ; A = A + 3
        0x88,             // DEY          ; Y = Y - 1
        0xD0, 0xFA,       // BNE loop     ; Branch if Y != 0
        0x8D, 0x02, 0x00, // STA $0002    ; Store result at address 2
        0xEA,             // NOP
        0xEA,             // NOP
        0xEA              // NOP
    ]
    
    test.loadProgram(program)
    test.bus.cpu.reset()
    
    print("Initial state:")
    test.printCPUState()
    
    // Run until we hit the first NOP
    var instructionCount = 0
    while test.bus.ram[Int(test.bus.cpu.pc)] != 0xEA {
        repeat {
            test.bus.cpu.clock()
        } while !test.bus.cpu.complete()
        
        instructionCount += 1
        if instructionCount % 5 == 0 {  // Print every 5 instructions
            print("After \(instructionCount) instructions:")
            test.printCPUState()
        }
    }
    
    print("\nFinal state:")
    test.printCPUState()
    print("Memory[0] = \(test.bus.ram[0]) (should be 10)")
    print("Memory[1] = \(test.bus.ram[1]) (should be 3)")
    print("Memory[2] = \(test.bus.ram[2]) (should be 30)")
    
    assert(test.bus.ram[2] == 30, "10 × 3 should equal 30")
    print("✓ Multiplication test passed\n")
}

func runWithTrace(instructions: Int) {
    let test = EmulatorTest()
    // ... load program ...
    
    for i in 0..<instructions {
        let pc = test.bus.cpu.pc
        let opcode = test.bus.ram[Int(pc)]
        
        print("\(i): ", terminator: "")
        test.printCPUState()
        print("     Next: $\(String(format: "%02X", opcode)) at $\(String(format: "%04X", pc))")
        
        repeat {
            test.bus.cpu.clock()
        } while !test.bus.cpu.complete()
    }
}

func testLDAZeroPage() {
    print("=== Testing LDA Zero Page ===")
    let test = EmulatorTest()
    
    // Put value 0x33 at zero page address 0x10
    test.bus.ram[0x10] = 0x33
    
    // LDA $10 = 0xA5 0x10
    test.loadProgram([0xA5, 0x10])
    test.completeReset()
    test.executeOneInstruction()
    
    assert(test.bus.cpu.a == 0x33, "A should be 0x33")
    print("✓ LDA Zero Page test passed\n")
}

func testADCWithCarry() {
    print("=== Testing ADC with Carry ===")
    let test = EmulatorTest()
    
    test.loadProgram([
        0xA9, 0xFF,  // LDA #$FF
        0x69, 0x01,  // ADC #$01  (FF + 01 = 00 with carry)
    ])
    test.completeReset()
    test.executeOneInstruction()  // LDA
    test.executeOneInstruction()  // ADC
    
    assert(test.bus.cpu.a == 0x00, "A should wrap to 0x00")
    assert(test.bus.cpu.status & 0x01 != 0, "Carry flag should be set")
    print("✓ ADC with carry test passed\n")
}

func testStackPushPull() {
    print("=== Testing Stack Push/Pull ===")
    let test = EmulatorTest()
    
    test.loadProgram([
        0xA9, 0x42,  // LDA #$42
        0x48,        // PHA (push A)
        0xA9, 0x00,  // LDA #$00
        0x68,        // PLA (pull A)
    ])
    test.completeReset()
    test.executeOneInstruction()  // LDA #$42
    let spBefore = test.bus.cpu.stkp
    test.executeOneInstruction()  // PHA
    assert(test.bus.cpu.stkp == spBefore - 1, "Stack pointer should decrement")
    test.executeOneInstruction()  // LDA #$00
    test.executeOneInstruction()  // PLA
    
    assert(test.bus.cpu.a == 0x42, "A should be restored to 0x42")
    assert(test.bus.cpu.stkp == spBefore, "Stack pointer should be restored")
    print("✓ Stack test passed\n")
}



func runAllTests() {
    print("Starting 6502 Emulator Tests\n")
    
    var passed = 0
    var failed = 0
    
    let tests = [
        ("NOP", testNOP),
        ("LDA Immediate", testLDAImmediate),
        ("LDA Zero Page", testLDAZeroPage),
        ("ADC with Carry", testADCWithCarry),
        ("Stack Operations", testStackPushPull),
        ("Multiplication Program", testMultiplicationProgram),
        ("Visual Multiplication", testMultiplicationProgramVisual)
    ]
    
    for (name, test) in tests {
        print("Running \(name)...")
        test() 
        passed += 1
    }
    
    print("\n=============================")
    print("Tests Passed: \(passed)")
    print("Tests Failed: \(failed)")
    print("=============================\n")
}

func testMultiplicationProgramVisual() {
    print("=== Testing 10 × 3 Multiplication (Visual) ===")
    let test = EmulatorTest()
    
    let program: [UInt8] = [
        0xA2, 0x0A,       // LDX #10
        0x8E, 0x00, 0x00, // STX $0000
        0xA2, 0x03,       // LDX #3
        0x8E, 0x01, 0x00, // STX $0001
        0xAC, 0x00, 0x00, // LDY $0000
        0xA9, 0x00,       // LDA #0
        0x18,             // CLC
        0x6D, 0x01, 0x00, // ADC $0001
        0x88,             // DEY
        0xD0, 0xFA,       // BNE loop
        0x8D, 0x02, 0x00, // STA $0002
        0xEA, 0xEA, 0xEA  // NOP NOP NOP
    ]
    
    test.loadProgram(program)
    test.completeReset()
    
    // Show initial memory state
    print("\nInitial memory state:")
    test.printMemoryDump(from: 0x0000, length: 32)
    test.printMemoryDump(from: 0x8000, length: 32)
    
    // Run program with visualization
    var stepCount = 0
    while test.bus.ram[Int(test.bus.cpu.pc)] != 0xEA {
        stepCount += 1
        print("\n--- Step \(stepCount) ---")
        test.printCPUState()
        
        // Show next instruction
        let pc = test.bus.cpu.pc
        let opcode = test.bus.ram[Int(pc)]
        print("Next instruction: $\(String(format: "%02X", opcode)) at $\(String(format: "%04X", pc))")
        
        test.executeOneInstruction()
        
        // Show memory changes for key steps
        if stepCount == 2 || stepCount == 4 || stepCount == 14 {
            print("\nMemory after step \(stepCount):")
            test.printMemoryDump(from: 0x0000, length: 16)
        }
    }
    
    print("\n=== Final State ===")
    test.printCPUState()
    test.printMemoryDump(from: 0x0000, length: 16)
    
    print("\nResult: \(test.bus.ram[0]) × \(test.bus.ram[1]) = \(test.bus.ram[2])")
    print("✓ Visual multiplication test complete\n")
}

func interactiveDebug() {
    print("=== Interactive 6502 Debugger ===")
    let test = EmulatorTest()
    
    // Load a simple program
    test.loadProgram([
        0xA9, 0x42,  // LDA #$42
        0x85, 0x00,  // STA $00
        0xE6, 0x00,  // INC $00
        0xEA,        // NOP
    ])
    test.completeReset()
    
    var running = true
    while running {
        print("\n" + String(repeating: "-", count: 50))
        test.printCPUState()
        
        let pc = test.bus.cpu.pc
        let opcode = test.bus.ram[Int(pc)]
        print("Next: $\(String(format: "%02X", opcode)) at $\(String(format: "%04X", pc))")
        
        print("\nCommands: (s)tep, (m)emory, (z)ero page, (q)uit")
        print("Enter command: ", terminator: "")
        
        if let input = readLine()?.lowercased() {
            switch input {
            case "s":
                test.executeOneInstruction()
            case "m":
                print("Enter address (hex): ", terminator: "")
                if let addrStr = readLine(),
                   let addr = UInt16(addrStr, radix: 16) {
                    test.printMemoryDump(from: addr, length: 64)
                }
            case "z":
                test.printMemoryDump(from: 0x0000, length: 256)
            case "q":
                running = false
            default:
                print("Unknown command")
            }
        }
    }
}
