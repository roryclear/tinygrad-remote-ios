import Foundation

extension tinygrad {
    @objc static func start() {
        if !hasSharedInstance() {
            createSharedInstance()
        }
    }
    
    @objc static func stop() {
        invalidateSocket()
        setSharedInstanceNil()
    }
    
    @objc static func toggleSaveKernels() { toggleSaveKernelsValue() }
}
