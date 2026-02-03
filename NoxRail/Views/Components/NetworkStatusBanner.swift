import SwiftUI

/// Network status banner component
struct NetworkStatusBanner: View {
    let bluetoothState: BLEPowerState
    let connectedCount: Int
    
    var body: some View {
        HStack(spacing: 8) {
            // Bluetooth indicator
            Image(systemName: bluetoothIcon)
                .foregroundStyle(bluetoothColor)
            
            if bluetoothState.isReady {
                // Connected peers count
                Text("\(connectedCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(connectedCount > 0 ? Color.noxSuccess : Color.secondary)
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var bluetoothIcon: String {
        switch bluetoothState {
        case .poweredOn:
            return "antenna.radiowaves.left.and.right"
        case .poweredOff:
            return "antenna.radiowaves.left.and.right.slash"
        case .unauthorized:
            return "hand.raised.fill"
        default:
            return "antenna.radiowaves.left.and.right"
        }
    }
    
    private var bluetoothColor: Color {
        switch bluetoothState {
        case .poweredOn:
            return Color.noxPrimary
        case .poweredOff:
            return .orange
        case .unauthorized:
            return .red
        default:
            return .secondary
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NetworkStatusBanner(bluetoothState: .poweredOn, connectedCount: 3)
        NetworkStatusBanner(bluetoothState: .poweredOn, connectedCount: 0)
        NetworkStatusBanner(bluetoothState: .poweredOff, connectedCount: 0)
        NetworkStatusBanner(bluetoothState: .unauthorized, connectedCount: 0)
    }
}
