//
//  Alerts.swift
//  macadamia
//
//  Created by Dario Lass on 02.01.24.
//

import Foundation

import SwiftUI
import UIKit


struct AlertDetail {
    let title:String
    let alertDescription:String?
    let primaryButtonText:String?
    let affirmText:String?
    let onAffirm:(() -> Void)?
    
    init(title: String,
         description: String? = nil,
         primaryButtonText: String? = nil,
         affirmText: String? = nil,
         onAffirm: (() -> Void)? = nil) {
        
        self.title = title
        self.alertDescription = description
        self.primaryButtonText = primaryButtonText
        self.affirmText = affirmText
        self.onAffirm = onAffirm
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No need to update the controller here
    }
}
