//
//  ControllerPort.swift
//  nes
//
//  Created by mike on 8/5/25.
//

class NESController {
    var buttons: Controller = []
    private var shiftRegister: UInt8 = 0
    private var strobe: Bool = false

    // Latch (strobe) handler: call when writing to $4016/$4017
    func write(_ value: UInt8) {
        let newStrobe = (value & 1) != 0
        if strobe == false && newStrobe == true {
            // Rising edge: latch buttons into shift register
            shiftRegister = buttons.rawValue
        }
        strobe = newStrobe
    }

    // Shift out one button bit per CPU read to $4016/$4017
    func read() -> UInt8 {
        if strobe {
            // When strobe is high, always return A button state
            return (buttons.contains(.a) ? 0x01 : 0x00) | 0x40
        } else {
            let result = shiftRegister & 0x01
            shiftRegister = (shiftRegister >> 1) | 0x80
            return result | 0x40
        }
    }
}
