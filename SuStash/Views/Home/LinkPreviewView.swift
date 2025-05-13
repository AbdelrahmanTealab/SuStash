//
//  LinkPreviewView.swift
//  SuStash
//
//  Created by Abdelrahman  Tealab on 2024-02-18.
//

import Foundation
import SwiftUI
import LinkPresentation

struct LinkPreview: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> LPLinkView {
        let linkView = LPLinkView(url: url)
        let provider = LPMetadataProvider()
        
        provider.startFetchingMetadata(for: url) { metadata, error in
            guard let metadata = metadata, error == nil else {
                // Handle error
                return
            }
            
            DispatchQueue.main.async {
                linkView.metadata = metadata
                linkView.sizeToFit()
            }
        }
        
        return linkView
    }
    
    func updateUIView(_ uiView: LPLinkView, context: Context) {
        // Update the view if needed.
    }
}
