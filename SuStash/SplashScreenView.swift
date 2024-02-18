//
//  LaunchScreenView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-17.
//

import Foundation
import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    
    var body: some View {
        if isActive {
            // Proceed to your main content view
            AuthenticationView()
        } else {
            VStack {
                Image("sustashlogo") // Replace with your logo
                    .resizable()
                    .scaledToFit()
                
                Text("SuStash")
                    .font(.custom("Avenir Next", size: 48))
                    .fontWeight(.thin)
            }
            .onAppear {
                // Simulate a delay to mimic a real splash screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}


struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView()
    }
}
