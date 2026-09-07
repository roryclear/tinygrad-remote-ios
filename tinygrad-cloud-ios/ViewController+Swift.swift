import UIKit

extension ViewController {
    @objc func openGitHub() {
        guard let url = URL(string: "https://github.com/roryclear/tinygrad-remote-ios") else { return }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    @objc func showKernelEditor(_ kernelName: String) {
        guard let code = myKernels[kernelName] as? String,
              let navController = navigationController else { return }
        
        let vc = CodeEditController(code: code, title: kernelName)
        
        vc?.onSave = { [weak self] (code: String?) in
            guard let self = self, let code = code else { return }
            
            self.myKernels[kernelName] = code
            if !self.myKernelNames.contains(kernelName) {
                self.myKernelNames.add(kernelName)
            }
            self.saveMyKernels()
            self.tableView.reloadData()
        }
        navController.pushViewController(vc!, animated: true)
    }
    
    @objc func remoteToggleChanged(_ sender: UISwitch) {
        if sender.isOn {
            tinygrad.start()
            isRemoteEnabled = true
            updateIPLabel()
            ipTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.updateIPLabel()
            }
        } else {
            tinygrad.stop()
            isRemoteEnabled = false
            ipTimer?.invalidate()
            ipLabel.text = "Turn on tinygrad remote"
        }
        tableView.reloadData()
    }
    
    @objc func kernelsToggleChanged(_ sender: UISwitch) {
        tinygrad.toggleSaveKernels()
        tableView.reloadData()
    }
    
    @objc func updateIPLabel() {
        DispatchQueue.main.async { [weak self] in
            self?.ipLabel.text = tinygrad.getIP()
        }
    }
    
    @objc func saveMyKernels() {
        UserDefaults.standard.set(myKernels, forKey: "myKernels")
        UserDefaults.standard.set(myKernelNames, forKey: "myKernelNames")
        UserDefaults.standard.synchronize()
    }
    
    @objc func loadMyKernels() {
        if let savedKernels = UserDefaults.standard.dictionary(forKey: "myKernels") {
            myKernels = NSMutableDictionary(dictionary: savedKernels)
        }
        
        if let savedKernelNames = UserDefaults.standard.array(forKey: "myKernelNames") {
            myKernelNames = NSMutableArray(array: savedKernelNames)
        } else {
            myKernelNames = NSMutableArray(array: myKernels.allKeys)
        }
    }
    
}
