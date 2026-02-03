import SwiftUI

/// Main tab-based navigation view
struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var peersViewModel = PeersViewModel()
    @StateObject private var chatListViewModel = ChatListViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NearbyPeersView(viewModel: peersViewModel)
                .tabItem {
                    Label("Nearby", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)
            
            ChatListView(viewModel: chatListViewModel)
                .tabItem {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .badge(chatListViewModel.totalUnreadCount)
                .tag(1)
            
            SettingsView(viewModel: settingsViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(Color.noxPrimary)
    }
}

#Preview {
    MainTabView()
}
