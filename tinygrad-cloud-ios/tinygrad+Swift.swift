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
    
    @objc static func getIP() -> String {
        var addrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrPtr) == 0, let firstAddr = addrPtr else { return "Waiting for WiFi..." }
        defer { freeifaddrs(addrPtr) }
        var currentAddr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        var ip: String?
        while let addr = currentAddr {
            if let ifaAddr = addr.pointee.ifa_addr,
               ifaAddr.pointee.sa_family == UInt8(AF_INET),
               let ifaName = addr.pointee.ifa_name,
               String(cString: ifaName) == "en0" {
                
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ifaAddr, socklen_t(ifaAddr.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 {
                    ip = String(cString: hostname)
                    break
                }
            }
            currentAddr = addr.pointee.ifa_next
        }
        if let ip = ip {
            return "tinygrad: \(ip):6667"
        } else {
            return "Waiting for WiFi..."
        }
    }
    
    @objc static func extractValues(_ x: String) -> NSMutableDictionary {
        let values = NSMutableDictionary()
        values["op"] = x.components(separatedBy: "(")[0]
        
        let patterns: [String: String] = [
            "name": "name='([^']+)'",
            "datahash": "datahash='([^']+)'",
            "global_sizes": "global_size=\\(([^)]+)\\)",
            "local_sizes": "local_size=\\(([^)]+)\\)",
            "wait": "wait=(True|False)",
            "bufs": "bufs=\\(([^)]+)\\)",
            "vals": "vals=\\(([^)]+)\\)",
            "buffer_num": "buffer_num=(\\d+)",
            "size": "size=(\\d+)"
        ]
        
        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: x, options: [], range: NSRange(location: 0, length: x.utf16.count)) {
                
                let contents = (x as NSString).substring(with: match.range(at: 1))
                var extractedValues: [String] = []
                
                for value in contents.components(separatedBy: ",") {
                    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedValue.count > 0 {
                        extractedValues.append(trimmedValue)
                    }
                }
                
                values[key] = extractedValues
            }
        }
        
        return values
    }
    
}
