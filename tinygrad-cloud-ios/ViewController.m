#import "ViewController.h"
#import "tinygrad.h"
#import "CodeEditController.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    self.isRemoteEnabled = NO;
    self.myKernels = [NSMutableDictionary dictionary];
    self.myKernelNames = [NSMutableArray array];

    [self loadMyKernels];

    self.navigationItem.title = @"tinygrad remote";
    UIButton *githubButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [githubButton setTitle:@"GitHub" forState:UIControlStateNormal];
    [githubButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [githubButton addTarget:self action:@selector(openGitHub) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *githubBarButton = [[UIBarButtonItem alloc] initWithCustomView:githubButton];
    self.navigationItem.leftBarButtonItem = githubBarButton;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
        if (save_kernels) {
            self.kernelTimes = [kernel_times copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
    }];
}


#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    if (section == 1) return self.myKernelNames.count; // Use myKernelNames.count
    if (section == 2 && save_kernels) return [kernel_keys count];
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"MY KERNELS";
    if (section == 2 && save_kernels) return @"Tinygrad Kernels";
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
                self.ipLabel.frame = CGRectMake(15, 0, CGRectGetWidth(cell.contentView.bounds) - 100, 44);

                UISwitch *toggle = self.remoteSwitch;
                toggle.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:toggle];
                [NSLayoutConstraint activateConstraints:@[
                    [toggle.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                    [toggle.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
                ]];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Show tinygrad kernels";

                UISwitch *toggle = self.kernelsSwitch;
                toggle.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:toggle];
                [NSLayoutConstraint activateConstraints:@[
                    [toggle.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
                    [toggle.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
                ]];
            }
        }
    else if (indexPath.section == 1) {
        if (indexPath.row < self.myKernelNames.count) {
            NSString *kernelName = self.myKernelNames[indexPath.row];
            
            UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            NSNumber *time = [self getMyKernelTimes][kernelName];
            
            if (time) {
                double nanoseconds = time.doubleValue;

                if (nanoseconds >= 1e6) {
                    double milliseconds = nanoseconds / 1e6;
                    timeLabel.text = [NSString stringWithFormat:@"%.3f ms", milliseconds];
                } else {
                    double microseconds = nanoseconds / 1e3;
                    timeLabel.text = [NSString stringWithFormat:@"%.0f µs", microseconds];
                }
            } else {
                timeLabel.text = @"";
            }
            
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
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

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
    else if (indexPath.section == 2) {
        NSArray<NSString *> *keys = [kernel_keys copy];
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
        if (indexPath.row < self.myKernelNames.count) {
            NSString *kernelName = self.myKernelNames[indexPath.row]; // Use the ordered name
            [self showKernelEditor:kernelName];
        }
    }
    else if (indexPath.section == 2) {
        NSArray<NSString *> *keys = [kernel_keys copy];
        if (indexPath.row < keys.count) {
            NSString *kernelName = keys[indexPath.row];
            NSString *code = saved_kernels[kernelName];
            // Add to myKernels if not already present to allow saving
            if (![self.myKernels.allKeys containsObject:kernelName]) {
                self.myKernels[kernelName] = code;
                [self.myKernelNames addObject:kernelName]; // Add to ordered list
                [self saveMyKernels]; // Save to persist the new kernel
            }
            [self showKernelEditor:kernelName];
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

@end
