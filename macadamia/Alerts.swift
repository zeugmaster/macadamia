//
//  Alerts.swift
//  macadamia
//
//  Created by Dario Lass on 02.01.24.
//

import Foundation

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
