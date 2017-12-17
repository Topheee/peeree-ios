//
//  InAppNotificationViewController.swift
//  Peeree
//
//  Created by Christopher Kobusch on 01.08.17.
//  Copyright © 2017 Kobusch. All rights reserved.
//

import UIKit

/// this class does not work quite correctly when several notifications are presented after another, e.g. when they are currently animating to close
final class InAppNotificationViewController: UIViewController {
    // it would be great to have this nillable and re-initializable for memory warnings
    static var shared: InAppNotificationViewController = InAppNotificationViewController(nibName: "InAppNotification", bundle: nil)
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var messageView: UITextView!
    
    private var displayTimer: Timer!
    
    override var title: String? {
        get {
            return super.title
        }
        set {
            super.title = newValue
            titleLabel?.text = newValue
        }
    }
    
    var message: String? {
        get {
            return messageView?.text
        }
        set {
            messageView?.text = newValue
        }
    }

    @IBAction func close(_ sender: Any) {
        if let timer = sender as? Timer {
            NSLog("Closed from timer \(timer). Valid: \(timer.isValid). Fire Date \(timer.fireDate)")
        }
        dismissFromView(animated: true)
    }

    @IBAction func panView(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let piece = gestureRecognizer.view else { return }
        
        if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
            // Get the distance moved since the last call to this method.
            let translation = gestureRecognizer.translation(in: piece.superview)
            let location = gestureRecognizer.location(in: piece.superview)
            
            // Set the translation point to zero so that the translation distance
            // is only the change since the last call to this method.
            if (piece.frame.origin.y <= 0 && location.y < piece.frame.height + piece.frame.origin.y) {
                piece.frame.origin.y += translation.y
            }
            gestureRecognizer.setTranslation(CGPoint.zero, in: piece.superview)
        } else if gestureRecognizer.state == .cancelled || gestureRecognizer.state == .ended {
            dismissFromView(animated: true, velocity: 0.0 /* gestureRecognizer.velocity(in: piece.superview).y */)
        }
    }
    
    /// only run on the main thread!
    func present(in superViewController: UIViewController, duration: TimeInterval=0.0) {
        // setup our view so that it fits correctly under the (extended) top bar
        let view = self.view!
        superViewController.view.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.topAnchor.constraint(equalTo: superViewController.topLayoutGuide.topAnchor).isActive = true
        titleLabel.topAnchor.constraint(equalTo: superViewController.topLayoutGuide.bottomAnchor, constant: 8.0).isActive = true
        view.leftAnchor.constraint(equalTo: superViewController.view.leftAnchor).isActive = true
        view.rightAnchor.constraint(equalTo: superViewController.view.rightAnchor).isActive = true
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.frame.origin.y = -view.frame.height
        
        titleLabel.textColor = .white
        messageView.textColor = .lightText
        
        UIView.animate(withDuration: 1.0, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: [.beginFromCurrentState], animations: {
            var frame = self.view.frame
            frame.origin.y = 0.0
            self.view.frame = frame
        }, completion: { (completed) in
            NSLog("Presentation animation completed: \(completed)")
            if completed, duration != 0.0 {
                // be sure that an may already established timer does not fire
                self.displayTimer?.invalidate()
                self.displayTimer = nil
                self.displayTimer = Timer.scheduledTimer(timeInterval: duration, target: self, selector: #selector(self.close(_:)), userInfo: nil, repeats: false)
            }
        })
    }
    
    func dismissFromView(animated flag: Bool, velocity: CGFloat=0.0) {
        displayTimer?.invalidate()
        displayTimer = nil
        if flag {
            DispatchQueue.main.async {
                let frame = self.view.frame
                let duration = max((frame.origin.y + frame.height) / frame.height * 2.0, 0.0)
                UIView.animate(withDuration: TimeInterval(duration), delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: velocity, options: [], animations: {
                    var frame = self.view.frame
                    frame.origin.y = -frame.height
                    self.view.frame = frame
                }, completion: { (completed) in
                    NSLog("Dismiss animation completed: \(completed)")
                    if self.view.layer.animationKeys()?.count ?? 0 == 0 {
                        // if no animations are going on, we (hopefully) can be sure that we can remove ourselves from the view hierarchy
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                        self.view.removeFromSuperview()
                    }
                })
            }
        } else {
            view.removeFromSuperview()
        }
    }
    
    func presentGlobally(title: String, message: String) {
        DispatchQueue.main.async {
            guard let topVC = UIApplication.shared.keyWindow?.rootViewController else { return }
            if self.titleLabel == nil {
                self.loadView()
            }
            self.title = title
            self.message = message
            self.present(in: topVC, duration: 5.0 + Double(message.count) / 42.0)
        }
    }
}
