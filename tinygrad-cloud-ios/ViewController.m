#import "ViewController.h"
#import "tinygrad.h"
#import "CodeViewController.h"
#import "CodeEditController.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    self.isRemoteEnabled = NO;
    self.myKernels = [NSMutableDictionary dictionary];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                          target:self
                                                                                          action:@selector(addCustomKernel)];

    self.remoteSwitch = [[UISwitch alloc] init];
    [self.remoteSwitch addTarget:self action:@selector(remoteToggleChanged:) forControlEvents:UIControlEventValueChanged];

    self.kernelsSwitch = [[UISwitch alloc] init];
    [self.kernelsSwitch addTarget:self action:@selector(kernelsToggleChanged:) forControlEvents:UIControlEventValueChanged];

    self.ipLabel = [[UILabel alloc] init];
    self.ipLabel.text = @"Turn on tinygrad remote";
    self.ipLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    
    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
        if ([tinygrad isSaveKernelsEnabled]) {
            self.kernelTimes = [tinygrad getKernelTimes];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
    }];
}

- (void)addCustomKernel {
    NSString *defaultName = [NSString stringWithFormat:@"Custom Kernel %lu", (unsigned long)self.myKernels.count + 1];
    NSString *defaultCode = @"// Enter your kernel code here\n// This is your custom kernel";
    self.myKernels[defaultName] = defaultCode;
    [self showKernelEditor:defaultName];
}

- (void)showKernelEditor:(NSString *)kernelName {
    CodeEditController *vc = [[CodeEditController alloc] initWithCode:self.myKernels[kernelName] title:kernelName];
    
    __weak typeof(self) weakSelf = self;
    vc.onSave = ^(NSString *code) {
        weakSelf.myKernels[kernelName] = code;
        [weakSelf.tableView reloadData];
    };
    
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)remoteToggleChanged:(UISwitch *)sender {
    if (sender.isOn) {
        [tinygrad start];
        self.isRemoteEnabled = YES;
        [self updateIPLabel];
        self.ipTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
            [self updateIPLabel];
        }];
    } else {
        self.isRemoteEnabled = NO;
        [self.ipTimer invalidate];
        self.ipLabel.text = @"Turn on tinygrad remote";
    }
    [self.tableView reloadData];
}

- (void)kernelsToggleChanged:(UISwitch *)sender {
    [tinygrad toggleSaveKernels];
    [self.tableView reloadData];
}

- (void)updateIPLabel {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.ipLabel.text = [tinygrad getIP];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    if (section == 1) return self.myKernels.count;
    if (section == 2 && [tinygrad isSaveKernelsEnabled]) return [tinygrad getKernelKeys].count;
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"MY KERNELS";
    if (section == 2 && [tinygrad isSaveKernelsEnabled]) return @"Tinygrad Kernels";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    cell.textLabel.text = @"";
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            [cell.contentView addSubview:self.ipLabel];
            self.ipLabel.frame = CGRectMake(15, 0, cell.contentView.bounds.size.width - 100, 44);
            UISwitch *toggle = self.remoteSwitch;
            toggle.center = CGPointMake(cell.contentView.bounds.size.width - 60, cell.contentView.bounds.size.height / 2);
            [cell.contentView addSubview:toggle];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Show tinygrad kernels";
            UISwitch *toggle = self.kernelsSwitch;
            toggle.center = CGPointMake(cell.contentView.bounds.size.width - 60, cell.contentView.bounds.size.height / 2);
            [cell.contentView addSubview:toggle];
        }
    }
    else if (indexPath.section == 1) {
        NSArray *myKernelNames = [self.myKernels allKeys];
        if (indexPath.row < myKernelNames.count) {
            NSString *kernelName = myKernelNames[indexPath.row];
            cell.textLabel.text = kernelName;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    else if (indexPath.section == 2) {
        NSArray<NSString *> *keys = [tinygrad getKernelKeys];
        if (indexPath.row < keys.count) {
            NSString *kernelName = keys[indexPath.row];
            NSNumber *time = self.kernelTimes[kernelName];

            UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            double ns = time.doubleValue;
            timeLabel.text = ns >= 1e6 ? [NSString stringWithFormat:@"%.3f ms", ns / 1e6]
                                       : [NSString stringWithFormat:@"%.0f µs", ns / 1e3];
            timeLabel.font = [UIFont systemFontOfSize:14];
            timeLabel.textAlignment = NSTextAlignmentRight;
            timeLabel.textColor = [UIColor secondaryLabelColor];
            timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:timeLabel];

            UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            nameLabel.text = kernelName;
            nameLabel.font = [UIFont systemFontOfSize:16];
            nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:nameLabel];

            cell.textLabel.text = @"";

            [NSLayoutConstraint activateConstraints:@[
                [timeLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                [timeLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [timeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:60],

                [nameLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:15],
                [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:timeLabel.leadingAnchor constant:-10],
                [nameLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        }
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        NSArray *myKernelNames = [self.myKernels allKeys];
        if (indexPath.row < myKernelNames.count) {
            [self showKernelEditor:myKernelNames[indexPath.row]];
        }
    }
    else if (indexPath.section == 2) {
        NSArray<NSString *> *keys = [tinygrad getKernelKeys];
        if (indexPath.row < keys.count) {
            NSString *key = keys[indexPath.row];
            NSString *code = [tinygrad getKernelCodeForKey:key];
            CodeViewController *vc = [[CodeViewController alloc] initWithCode:code title:key];
            [self.navigationController pushViewController:vc animated:YES];
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 1) {
        NSArray *myKernelNames = [self.myKernels allKeys];
        if (indexPath.row < myKernelNames.count) {
            NSString *kernelName = myKernelNames[indexPath.row];
            [self.myKernels removeObjectForKey:kernelName];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

@end
