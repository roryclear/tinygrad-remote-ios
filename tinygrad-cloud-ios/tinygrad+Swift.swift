import Foundation

extension tinygrad {
    @objc static func start() {
        if !hasSharedInstance() {
            createSharedInstance()
        }
    }
}
