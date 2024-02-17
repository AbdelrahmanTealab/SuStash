//
//  AuthenticationViewModel.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-16.
//

import Foundation
import CloudKit

class AuthenticationViewModel: ObservableObject {
    @Published var isUserAuthenticated = false

    init() {
        checkAuthentication()
    }
    
    func checkAuthentication() {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    // The user is logged in to iCloud, and your app has permission to access CloudKit.
                    self.isUserAuthenticated = true
                case .restricted, .couldNotDetermine:
                    // The iCloud account status is restricted or undetermined.
                    self.isUserAuthenticated = false
                case .noAccount:
                    // The user is not logged in to an iCloud account.
                    self.isUserAuthenticated = false
                case .temporarilyUnavailable:
                    // The iCloud account status is temporarily unavailable.
                    self.isUserAuthenticated = false
                @unknown default:
                    // Handle future cases
                    self.isUserAuthenticated = false
                }
            }
        }
    }
}
