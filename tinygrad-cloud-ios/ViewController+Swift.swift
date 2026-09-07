import UIKit

extension ViewController {
    @objc func openGitHub() {
        guard let url = URL(string: "https://github.com/roryclear/tinygrad-remote-ios") else { return }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    @objc func getMyKernelTimes() -> [String: NSNumber] {
        let defaults = UserDefaults.standard
        var times: [String: NSNumber] = [:]
        
        for kernelName in myKernelNames {
            if let name = kernelName as? String {
                let timeKey = "\(name)_lastExecutionTime"
                if let time = defaults.object(forKey: timeKey) as? NSNumber {
                    times[name] = time
                }
            }
        }
        
        return times
    }
    
    @objc func addCustomKernel() {
        let alert = UIAlertController(
            title: "New Custom Kernel",
            message: "Enter a name for your new kernel:",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Kernel Name"
            textField.text = String(format: "kernel_%lu", self.myKernels.count + 1)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let nameTextField = alert.textFields?.first,
                  let kernelName = nameTextField.text else { return }
            
            if !kernelName.isEmpty && !self.myKernels.allKeys.contains(where: { $0 as? String == kernelName }) {
                // Replace non-alphanumeric characters with underscores
                let safeKernelName = kernelName.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
                    .joined(separator: "_")
                
                let defaultCode = """
                #include <metal_stdlib>
                using namespace metal;
                kernel void \(safeKernelName)(uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {
                
                }
                """
                
                self.myKernels[kernelName] = defaultCode
                self.myKernelNames.add(kernelName) // Add to ordered list
                self.saveMyKernels() // Save after adding
                self.showKernelEditor(kernelName)
            } else {
                // Handle duplicate or empty name
                let errorAlert = UIAlertController(
                    title: "Error",
                    message: "Kernel name already exists or is empty.",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(errorAlert, animated: true, completion: nil)
            }
        }
        
        alert.addAction(cancelAction)
        alert.addAction(createAction)
        present(alert, animated: true, completion: nil)
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
