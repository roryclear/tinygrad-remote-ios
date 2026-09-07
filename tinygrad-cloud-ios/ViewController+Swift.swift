import UIKit

extension ViewController {
    @objc func openGitHub() {
        guard let url = URL(string: "https://github.com/roryclear/tinygrad-remote-ios") else { return }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
