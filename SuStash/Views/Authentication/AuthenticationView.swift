//
//  LoginView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import Foundation
import SwiftUI

struct AuthenticationView: View {
    @StateObject var viewModel = AuthenticationViewModel()

    var body: some View {
        VStack {
            if viewModel.isUserAuthenticated {
                // User is authenticated; proceed to the main app content.
                TabBarView()
            } else {
                // User is not authenticated; show a message or a button to open Settings.
                Text("Please log in to your iCloud account in Settings.")
            }
        }
        .onAppear {
            viewModel.checkAuthentication()
        }
    }
}
