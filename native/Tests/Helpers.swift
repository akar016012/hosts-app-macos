import Foundation

// Encodes a Swift string as a JSON string literal (with surrounding quotes), used
// to build hand-written legacy JSON for the back-compat decode test.
func jsonString(_ s: String) -> String {
    let data = try! JSONEncoder().encode(s)
    return String(data: data, encoding: .utf8)!
}
