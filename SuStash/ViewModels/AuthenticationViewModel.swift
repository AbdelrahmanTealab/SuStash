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
    @Published var errorMessage = ""

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
                    self.errorMessage = ""
                case .restricted:
                    // The iCloud account status is restricted.
                    self.isUserAuthenticated = false
                    self.errorMessage = "The iCloud account status is restricted"
                case .couldNotDetermine:
                    // The iCloud account status is undetermined.
                    self.isUserAuthenticated = false
                    self.errorMessage = "The iCloud account status is undetermined"
                case .noAccount:
                    // The user is not logged in to an iCloud account.
                    self.isUserAuthenticated = false
                    self.errorMessage = "Please log in to your iCloud account in Settings"
                case .temporarilyUnavailable:
                    // The iCloud account status is temporarily unavailable.
                    self.isUserAuthenticated = false
                    self.errorMessage = "The iCloud account status is temporarily unavailable"
                @unknown default:
                    // Handle future cases
                    self.isUserAuthenticated = false
                    self.errorMessage = "Unknown Error"
                }
            }
        }
    }
}
