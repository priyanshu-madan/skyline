//
//  MinimalApp.swift
//  SkyLine
//
//  Absolute minimal version to ensure compilation
//

import SwiftUI

struct MinimalApp: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            VStack {
                Text("🌍")
                    .font(.system(size: 64))
                Text("Globe")
                    .font(.title)
            }
            .tabItem {
                Image(systemName: "globe")
                Text("Globe")
            }
            .tag(0)
            
            VStack {
                Text("🔍")
                    .font(.system(size: 64))
                Text("Search")
                    .font(.title)
            }
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("Search")
            }
            .tag(1)
            
            VStack {
                Text("✈️")
                    .font(.system(size: 64))
                Text("Flights")
                    .font(.title)
            }
            .tabItem {
                Image(systemName: "airplane")
                Text("Flights")
            }
            .tag(2)
            
            VStack {
                Text("👤")
                    .font(.system(size: 64))
                Text("Profile")
                    .font(.title)
            }
            .tabItem {
                Image(systemName: "person.circle")
                Text("Profile")
            }
            .tag(3)
        }
    }
}

#Preview {
    MinimalApp()
}