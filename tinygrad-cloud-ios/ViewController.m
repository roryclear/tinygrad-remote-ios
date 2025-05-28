#import "ViewController.h"
#import "tinygrad.h"

@interface ViewController () <UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *toggleSwitch;
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
    [self.view addSubview:self.tableView];

    self.toggleSwitch = [[UISwitch alloc] init];
    [self.toggleSwitch addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];

    self.ipLabel = [[UILabel alloc] init];
    self.ipLabel.text = @"Turn on tinygrad remote";
    self.ipLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
}

- (void)toggleChanged:(UISwitch *)sender {
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

- (void)updateIPLabel {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.ipLabel.text = [tinygrad getIP];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"CustomCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];

        // Add the label to the left
        self.ipLabel.frame = CGRectMake(15, 0, cell.contentView.bounds.size.width - 100, 44);
        self.ipLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
        [cell.contentView addSubview:self.ipLabel];

        // Add the switch to the right
        self.toggleSwitch.center = CGPointMake(cell.contentView.bounds.size.width - 60, cell.contentView.bounds.size.height / 2);
        self.toggleSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [cell.contentView addSubview:self.toggleSwitch];
    }

    return cell;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

@end

