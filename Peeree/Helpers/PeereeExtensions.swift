//
//  PeereeExtensions.swift
//  Peeree
//
//  Created by Christopher Kobusch on 05.08.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import UIKit

extension UIAlertController {
    /// This is the preferred method to display an UIAlertController since it sets the tint color of the global theme. 
    func present(completion: (() -> Void)?) {
        presentInFrontMostViewController(true, completion: completion)
        self.view.tintColor = theme.globalTintColor
    }
}