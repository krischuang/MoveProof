import SwiftUI
import UIKit

/// Entry point for the MoveProof share extension.
///
/// Hosts the confirmation view, then completes the extension request. The two exit
/// paths both end in `completeRequest` or `cancelRequest`, which is what stops the
/// share sheet hanging around after the tenant is finished.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = ShareConfirmationView(
            collector: SharedItemCollector(inputItems: extensionContext?.inputItems ?? []),
            onFinish: { [weak self] in
                // The files are already in the App Group inbox by this point, so the
                // main app has everything it needs whether or not it is running.
                self?.showResultThenFinish()
            },
            onCancel: { [weak self] in
                self?.finish()
            }
        )

        let hosting = UIHostingController(rootView: rootView)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    /// Leaves the confirmation on screen briefly so the tenant sees that the file
    /// was accepted, rather than the sheet vanishing with no feedback.
    private func showResultThenFinish() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.finish()
        }
    }

    /// Dismisses the share sheet. Uses `completeRequest` in every case: nothing here
    /// failed from the host app's point of view, and the tenant has already been
    /// told in-sheet if a file could not be read.
    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
