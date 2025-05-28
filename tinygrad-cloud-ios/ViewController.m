#import "ViewController.h"
#import "tinygrad.h"

@interface ViewController () <UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *remoteSwitch;
@property (nonatomic, strong) UISwitch *kernelsSwitch;
@property (nonatomic, strong) UILabel *ipLabel;
@property (nonatomic, strong) NSTimer *ipTimer;
@property (nonatomic, assign) BOOL isRemoteEnabled;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    self.isRemoteEnabled = NO;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.remoteSwitch = [[UISwitch alloc] init];
    [self.remoteSwitch addTarget:self action:@selector(remoteToggleChanged:) forControlEvents:UIControlEventValueChanged];

    self.kernelsSwitch = [[UISwitch alloc] init];
    [self.kernelsSwitch addTarget:self action:@selector(kernelsToggleChanged:) forControlEvents:UIControlEventValueChanged];

    self.ipLabel = [[UILabel alloc] init];
    self.ipLabel.text = @"Turn on tinygrad remote";
    self.ipLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    
    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(__unused NSTimer *_) {
        if ([tinygrad isSaveKernelsEnabled]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
    }];
}

- (void)remoteToggleChanged:(UISwitch *)sender {
    if (sender.isOn) {
        [tinygrad start];
        self.isRemoteEnabled = YES;
        [self updateIPLabel];
        self.ipTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(__unused NSTimer *_) {
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
}

- (void)updateIPLabel {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.ipLabel.text = [tinygrad getIP];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [tinygrad isSaveKernelsEnabled] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // switches
    if (section == 1) return [tinygrad getKernelKeys].count; // kernel keys
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1 && [tinygrad isSaveKernelsEnabled]) {
        return @"Tinygrad Kernels";
    }
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

    if (indexPath.section == 0) {
        // Remote and Kernel Switches
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
    } else if (indexPath.section == 1) {
        NSArray<NSString *> *keys = [tinygrad getKernelKeys];
        if (indexPath.row < keys.count) {
            cell.textLabel.text = keys[indexPath.row];
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        NSArray<NSString *> *keys = [tinygrad getKernelKeys];
        if (indexPath.row < keys.count) {
            NSString *key = keys[indexPath.row];
            NSString *code = [tinygrad getKernelCodeForKey:key];
            [self showKernelCode:code title:key];
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (void)showKernelCode:(NSString *)code title:(NSString *)title {
    UIViewController *codeVC = [[UIViewController alloc] init];
    codeVC.title = title;
    codeVC.view.backgroundColor = [UIColor systemBackgroundColor];

    // Create editable text view
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.text = code;
    textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    textView.editable = YES;
    textView.translatesAutoresizingMaskIntoConstraints = NO;

    // Create buttons
    UIButton *runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [runButton setTitle:@"Run" forState:UIControlStateNormal];
    runButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    runButton.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveButton setTitle:@"Save" forState:UIControlStateNormal];
    saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;

    // Button container
    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[runButton, saveButton]];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.distribution = UIStackViewDistributionFillEqually;
    buttonStack.spacing = 20;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Add subviews
    [codeVC.view addSubview:textView];
    [codeVC.view addSubview:buttonStack];

    // Set up layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:codeVC.view.safeAreaLayoutGuide.topAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:codeVC.view.leadingAnchor constant:10],
        [textView.trailingAnchor constraintEqualToAnchor:codeVC.view.trailingAnchor constant:-10],
        [textView.bottomAnchor constraintEqualToAnchor:buttonStack.topAnchor constant:-10],

        [buttonStack.leadingAnchor constraintEqualToAnchor:codeVC.view.leadingAnchor constant:20],
        [buttonStack.trailingAnchor constraintEqualToAnchor:codeVC.view.trailingAnchor constant:-20],
        [buttonStack.bottomAnchor constraintEqualToAnchor:codeVC.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [buttonStack.heightAnchor constraintEqualToConstant:44],
    ]];

    // Push onto navigation stack
    [self.navigationController pushViewController:codeVC animated:YES];
}

@end

