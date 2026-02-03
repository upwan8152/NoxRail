import Foundation
import SwiftUI

// MARK: - Data Extensions

extension Data {
    /// Converts data to hex string
    var hexString: String {
        map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Creates data from hex string
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

// MARK: - Date Extensions

extension Date {
    /// Formats date for message display
    var messageTimestamp: String {
        let formatter = DateFormatter()
        
        if Calendar.current.isDateInToday(self) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        } else if Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "dd/MM/yy"
        }
        
        return formatter.string(from: self)
    }
    
    /// Formats date for chat list display
    var chatListTimestamp: String {
        let formatter = DateFormatter()
        
        if Calendar.current.isDateInToday(self) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "dd/MM"
        }
        
        return formatter.string(from: self)
    }
    
    /// Relative time description
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - String Extensions

extension String {
    /// Truncates string to specified length with ellipsis
    func truncated(to length: Int) -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length)) + "..."
    }
    
    /// Returns first character as uppercase string
    var firstLetter: String {
        String(self.prefix(1)).uppercased()
    }
}

// MARK: - Color Extensions

extension Color {
    /// Creates color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // Theme colors
    static let noxPrimary = Color(hex: "6366F1") // Indigo
    static let noxSecondary = Color(hex: "8B5CF6") // Purple
    static let noxAccent = Color(hex: "06B6D4") // Cyan
    static let noxSuccess = Color(hex: "22C55E") // Green
    static let noxWarning = Color(hex: "F59E0B") // Amber
    static let noxError = Color(hex: "EF4444") // Red
    
    // Chat bubble colors
    static let outgoingBubble = Color(hex: "6366F1")
    static let incomingBubble = Color(hex: "374151")
}

// MARK: - View Extensions

extension View {
    /// Applies conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Hides keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Array Extensions

extension Array where Element: Identifiable {
    /// Finds index of element by ID
    func firstIndex(matching element: Element) -> Int? {
        firstIndex { $0.id == element.id }
    }
}

// MARK: - UUID Extensions

extension UUID {
    /// Short ID for display
    var short: String {
        String(uuidString.prefix(8))
    }
}
