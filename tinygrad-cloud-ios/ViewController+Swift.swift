import UIKit

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var tableView: UITableView!
    var remoteSwitch = UISwitch()
    var kernelsSwitch = UISwitch()
    var ipLabel = UILabel()

    var isRemoteEnabled = false
    var myKernels: [String: String] = [:]
    var myKernelNames: [String] = []
    var kernelTimes: [String: NSNumber] = [:]
    var ipTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        loadMyKernels()

        navigationItem.title = "tinygrad remote"
        let githubButton = UIButton(type: .system)
        githubButton.setTitle("GitHub", for: .normal)
        githubButton.addTarget(self, action: #selector(openGitHub), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: githubButton)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addCustomKernel))

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        remoteSwitch.addTarget(self, action: #selector(remoteToggleChanged), for: .valueChanged)
        kernelsSwitch.addTarget(self, action: #selector(kernelsToggleChanged), for: .valueChanged)
        ipLabel.text = "Turn on tinygrad remote"
        ipLabel.font = .systemFont(ofSize: 16)

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            if is_save_kernels_enabled() {
                self?.kernelTimes = (get_kernel_times() as? [String: NSNumber]) ?? [:]
                DispatchQueue.main.async { self?.tableView.reloadData() }
            }
        }
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 2 }
        if section == 1 { return myKernelNames.count }
        if section == 2 && is_save_kernels_enabled() { return (get_kernel_keys() as? [String])?.count ?? 0 }
        return 0
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 1 { return "My Kernels" }
        if section == 2 && is_save_kernels_enabled() { return "Tinygrad Kernels" }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") ?? UITableViewCell(style: .default, reuseIdentifier: "Cell")
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.textLabel?.text = ""
        cell.accessoryType = .none

        if indexPath.section == 0 {
            let toggle = indexPath.row == 0 ? remoteSwitch : kernelsSwitch
            if indexPath.row == 0 {
                ipLabel.frame = CGRect(x: 15, y: 0, width: cell.contentView.bounds.width - 100, height: 44)
                cell.contentView.addSubview(ipLabel)
            } else {
                cell.textLabel?.text = "Show tinygrad kernels"
            }
            toggle.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(toggle)
            NSLayoutConstraint.activate([
                toggle.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -15),
                toggle.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
            ])
            return cell
        }

        let name = indexPath.section == 1 ? myKernelNames[indexPath.row] : ((get_kernel_keys() as? [String])?[indexPath.row] ?? "")
        let timeNum = indexPath.section == 1 ? getMyKernelTimes()[name] : kernelTimes[name]
        cell.accessoryType = indexPath.section == 1 ? .disclosureIndicator : .none

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 16)
        nameLabel.lineBreakMode = .byTruncatingMiddle

        let timeLabel = UILabel()
        timeLabel.font = .systemFont(ofSize: 14)
        timeLabel.textColor = .secondaryLabel
        timeLabel.textAlignment = .right
        if let ns = timeNum?.doubleValue {
            timeLabel.text = ns >= 1e6 ? String(format: "%.3f ms", ns / 1e6) : String(format: "%.0f µs", ns / 1e3)
        }

        [nameLabel, timeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            timeLabel.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -15),
            timeLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            nameLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 15),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -10),
            nameLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 1 && indexPath.row < myKernelNames.count {
            showKernelEditor(myKernelNames[indexPath.row])
        } else if indexPath.section == 2, let keys = get_kernel_keys() as? [String], indexPath.row < keys.count {
            let kernelName = keys[indexPath.row]
            if let saved = get_saved_kernels() as? [String: String], let code = saved[kernelName] {
                if myKernels[kernelName] == nil {
                    myKernels[kernelName] = code
                    myKernelNames.append(kernelName)
                    saveMyKernels()
                }
                showKernelEditor(kernelName)
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension ViewController {
    @objc func openGitHub() {
        guard let url = URL(string: "https://github.com/roryclear/tinygrad-remote-ios") else { return }
        if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
    }
    
    @objc func getMyKernelTimes() -> [String: NSNumber] {
        var times: [String: NSNumber] = [:]
        for name in myKernelNames {
            if let time = UserDefaults.standard.object(forKey: "\(name)_lastExecutionTime") as? NSNumber {
                times[name] = time
            }
        }
        return times
    }
    
    @objc func addCustomKernel() {
        let alert = UIAlertController(title: "New Custom Kernel", message: "Enter a name for your new kernel:", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Kernel Name"; $0.text = "kernel_\(self.myKernels.count + 1)" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self, let kernelName = alert.textFields?.first?.text, !kernelName.isEmpty else { return }
            if self.myKernels[kernelName] == nil {
                let safeName = kernelName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "_")
                let defaultCode = "#include <metal_stdlib>\nusing namespace metal;\nkernel void \(safeName)(uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {\n\n}"
                self.myKernels[kernelName] = defaultCode
                self.myKernelNames.append(kernelName)
                self.saveMyKernels()
                self.showKernelEditor(kernelName)
            } else {
                let errorAlert = UIAlertController(title: "Error", message: "Kernel name already exists.", preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
            }
        })
        present(alert, animated: true)
    }
    
    @objc func showKernelEditor(_ kernelName: String) {
        guard let code = myKernels[kernelName], let navController = navigationController else { return }
        guard let vc = CodeEditController(code: code, title: kernelName) else { return }
        vc.onSave = { [weak self] newCode in
            guard let self = self, let newCode = newCode else { return }
            self.myKernels[kernelName] = newCode
            if !self.myKernelNames.contains(kernelName) { self.myKernelNames.append(kernelName) }
            self.saveMyKernels()
            self.tableView.reloadData()
        }
        navController.pushViewController(vc, animated: true)
    }
    
    @objc func remoteToggleChanged(_ sender: UISwitch) {
        if sender.isOn {
            tinygrad.start()
            isRemoteEnabled = true
            updateIPLabel()
            ipTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.updateIPLabel() }
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
        DispatchQueue.main.async { [weak self] in self?.ipLabel.text = tinygrad.getIP() }
    }
    
    @objc func saveMyKernels() {
        UserDefaults.standard.set(myKernels, forKey: "myKernels")
        UserDefaults.standard.set(myKernelNames, forKey: "myKernelNames")
    }
    
    @objc func loadMyKernels() {
        myKernels = UserDefaults.standard.dictionary(forKey: "myKernels") as? [String: String] ?? [:]
        myKernelNames = UserDefaults.standard.array(forKey: "myKernelNames") as? [String] ?? Array(myKernels.keys)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && indexPath.section == 1 && indexPath.row < myKernelNames.count {
            let name = myKernelNames.remove(at: indexPath.row)
            myKernels.removeValue(forKey: name)
            saveMyKernels()
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { indexPath.section == 1 }
}
