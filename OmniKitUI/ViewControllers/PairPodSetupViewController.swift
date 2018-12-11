//
//  PairPodSetupViewController.swift
//  OmniKitUI
//
//  Created by Pete Schwamb on 9/18/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI
import RileyLinkKit
import OmniKit

class PairPodSetupViewController: SetupTableViewController {
    
    var rileyLinkPumpManager: RileyLinkPumpManager!
    
    var pumpManager: OmnipodPumpManager! {
        didSet {
            if oldValue == nil && pumpManager != nil {
                pumpManagerWasSet()
            }
        }
    }
    
    // MARK: -
    
    @IBOutlet weak var activityIndicator: SetupIndicatorView!
    
    @IBOutlet weak var loadingLabel: UILabel!
    
    private var loadingText: String? {
        didSet {
            tableView.beginUpdates()
            loadingLabel.text = loadingText
            
            let isHidden = (loadingText == nil)
            loadingLabel.isHidden = isHidden
            tableView.endUpdates()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        continueState = .initial
    }
    
    private func pumpManagerWasSet() {
        // Still priming?
        pumpManager.primeFinishesAt(completion: { (finishTime) in
            let currentTime = Date()
            if let finishTime = finishTime, finishTime > currentTime {
                self.continueState = .pairing
                let delay = finishTime.timeIntervalSince(currentTime)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.continueState = .ready
                }
            }
        })
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if case .pairing = continueState {
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - State
    
    private enum State {
        case initial
        case pairing
        case priming(finishTime: Date)
        case fault
        case ready
    }
    
    private var continueState: State = .initial {
        didSet {
            switch continueState {
            case .initial:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setPairTitle()
            case .pairing:
                activityIndicator.state = .loading
                footerView.primaryButton.isEnabled = false
                footerView.primaryButton.setPairTitle()
                lastError = nil
                loadingText = LocalizedString("Pairing...", comment: "The text of the loading label when pairing")
            case .priming(let finishTime):
                activityIndicator.state = .timedProgress(finishTime: finishTime)
                footerView.primaryButton.isEnabled = false
                footerView.primaryButton.setPairTitle()
                lastError = nil
                loadingText = LocalizedString("Priming...", comment: "The text of the loading label when priming")
            case .fault:
                activityIndicator.state = .hidden
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.setDeactivateTitle()
            case .ready:
                activityIndicator.state = .completed
                footerView.primaryButton.isEnabled = true
                footerView.primaryButton.resetTitle()
                lastError = nil
                loadingText = LocalizedString("Primed", comment: "The text of the loading label when pod is primed")
            }
        }
    }
    
    private var lastError: Error? {
        didSet {
            guard oldValue != nil || lastError != nil else {
                return
            }
            
            var errorText = lastError?.localizedDescription
            
            if let error = lastError as? LocalizedError {
                let localizedText = [error.errorDescription, error.failureReason, error.recoverySuggestion].compactMap({ $0 }).joined(separator: ". ") + "."
                
                if !localizedText.isEmpty {
                    errorText = localizedText
                }
            }
            
            loadingText = errorText
            
            // If we have an error, update the continue state
            if let podCommsError = lastError as? PodCommsError,
                case PodCommsError.podFault = podCommsError
            {
                continueState = .fault
            } else if lastError != nil {
                continueState = .initial
            }
        }
    }
    
    // MARK: - Navigation
    
    private func navigateToReplacePod() {
        performSegue(withIdentifier: "ReplacePod", sender: nil)
    }

    override func continueButtonPressed(_ sender: Any) {
        switch continueState {
        case .initial:
            pair()
        case .ready:
            super.continueButtonPressed(sender)
        case .fault:
            navigateToReplacePod()
        default:
            break
        }

    }
    
    override func cancelButtonPressed(_ sender: Any) {
        pumpManager.getPodState { (podState) in
            DispatchQueue.main.async {
                if podState != nil {
                    let confirmVC = UIAlertController(pumpDeletionHandler: {
                        self.navigateToReplacePod()
                    })
                    self.present(confirmVC, animated: true) {}
                } else {
                    super.cancelButtonPressed(sender)
                }
            }
        }
    }
    
    // MARK: -
    
    func pair() {
        self.continueState = .pairing
        
        pumpManager.pairAndPrime() { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let finishTime):
                    self.continueState = .priming(finishTime: finishTime)
                    let delay = finishTime.timeIntervalSinceNow
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.continueState = .ready
                    }
                case .failure(let error):
                    self.lastError = error
                }
            }
        }
    }
}

private extension SetupButton {
    func setPairTitle() {
        setTitle(LocalizedString("Pair", comment: "Button title to pair with pod during setup"), for: .normal)
    }
    
    func setDeactivateTitle() {
        setTitle(LocalizedString("Deactivate", comment: "Button title to deactivate pod because of fault during setup"), for: .normal)
    }
}

private extension UIAlertController {
    convenience init(pumpDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: LocalizedString("Are you sure you want to shutdown this pod?", comment: "Confirmation message for shutting down a pod"),
            preferredStyle: .actionSheet
        )
        
        addAction(UIAlertAction(
            title: LocalizedString("Deactivate Pod", comment: "Button title to deactivate pod"),
            style: .destructive,
            handler: { (_) in
                handler()
        }
        ))
        
        let exit = LocalizedString("Continue", comment: "The title of the continue action in an action sheet")
        addAction(UIAlertAction(title: exit, style: .default, handler: nil))
    }
}