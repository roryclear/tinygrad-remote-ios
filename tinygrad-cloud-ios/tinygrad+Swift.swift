import Foundation

import Foundation

extension tinygrad {
    @objc static func start() {
        if !hasSharedInstance() {
            createSharedInstance()
        }
        setupSocket()
    }

    @objc static func stop() {
        invalidateSocket()
        setSharedInstanceNil()
    }

    @objc static func toggleSaveKernels() { toggleSaveKernelsValue() }

    private static func setupSocket() {
        var socket: CFSocket?

        while socket == nil {
            let cb: CFSocketCallBack = { socket, type, address, data, info in
                AcceptCallback(socket, type, address, data, info)
            }
            socket = CFSocketCreate(
                nil,
                PF_INET,
                SOCK_STREAM,
                IPPROTO_TCP,    
                CFSocketCallBackType.acceptCallBack.rawValue,
                cb,
                nil
            )
            if socket == nil { sleep(1) }
        }

        guard let sock = socket else { return }

        var address = sockaddr_in()
        memset(&address, 0, MemoryLayout<sockaddr_in>.size)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_port = CFSwapInt16HostToBig(6667)
        address.sin_addr.s_addr = INADDR_ANY

        let addressData = CFDataCreate(
            nil,
            withUnsafeBytes(of: &address) { $0.bindMemory(to: UInt8.self).baseAddress },
            MemoryLayout<sockaddr_in>.size
        )

        while CFSocketSetAddress(sock, addressData) != CFSocketError.success {
            sleep(1)
        }

        let source = CFSocketCreateRunLoopSource(nil, sock, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)

        setSocket(sock)
        NSLog("HTTP Server started on port 6667.")
    }
    
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
