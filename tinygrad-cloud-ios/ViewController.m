#import "ViewController.h"
#import "tinygrad.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    UILabel *l = [[UILabel alloc] initWithFrame:self.view.bounds];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    [self.view addSubview:l];

    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(self.view.center.x-50, self.view.center.y+40, 100, 30);
    [b setTitle:@"Help" forState:UIControlStateNormal];
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *_) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/roryclear/tinygrad-remote-ios/blob/main/README.md"] options:@{} completionHandler:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];

    // Use the tinygrad shared instance
    l.text = [tinygrad start];

    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(__unused NSTimer *_) {
        l.text = [tinygrad start];
    }];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

@end
