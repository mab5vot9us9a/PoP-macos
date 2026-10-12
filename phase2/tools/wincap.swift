import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let id = w[kCGWindowNumber as String] as! Int
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print("\(id)\t\(owner)\t\(name)\t\(b["Width"]!)x\(b["Height"]!)")
    if owner.lowercased().contains("wine") || name.lowercased().contains("pagonia") { if (b["Width"] as! Double) > 1000 { print("TARGET \(id)") } }
}
