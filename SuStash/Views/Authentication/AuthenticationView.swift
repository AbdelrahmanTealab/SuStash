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
                Image("sustashlogo") // Replace with your logo
                    .resizable()
                    .scaledToFit()
                HStack(alignment:.firstTextBaseline) {
                    Image(systemName: "exclamationmark.circle")
                        .resizable()
                        .frame(width:20,height: 20  )
                        .foregroundStyle(.red)
                        
                    Text(viewModel.errorMessage)
                        .font(.custom("Avenir Next", size: 20))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                
            }
        }
        .onAppear {
            viewModel.checkAuthentication()
        }
    }
}
struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationView()
    }
}
