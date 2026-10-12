// click.swift: post mouse/keyboard events. Usage:
//   click move X Y | click X Y [double] | click key <keycode> | click wheel DY
import CoreGraphics
import Foundation
let a = CommandLine.arguments
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap); usleep(60_000) }
if a.count >= 4 && a[1] == "move" {
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
} else if a.count >= 3 && a[1] == "key" {
    let k = CGKeyCode(UInt16(a[2])!)
    post(CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: true))
    post(CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: false))
} else if a.count >= 3 && a[1] == "wheel" {
    post(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(a[2])!, wheel2: 0, wheel3: 0))
} else if a.count >= 3 {
    let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
    let n = a.count >= 4 && a[3] == "double" ? 2 : 1
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    usleep(150_000)
    for i in 1...n {
        let d = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
        let u = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
        d?.setIntegerValueField(.mouseEventClickState, value: Int64(i)); u?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
        post(d); post(u)
    }
} else { print("usage: click X Y [double] | move X Y | key CODE | wheel DY"); exit(2) }
