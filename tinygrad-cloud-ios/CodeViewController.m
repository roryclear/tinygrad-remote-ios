#import "CodeViewController.h"

@interface CodeViewController ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation CodeViewController

- (instancetype)initWithCode:(NSString *)code title:(NSString *)title {
    self = [super init];
    if (self) {
        self.title = title;
        self.view.backgroundColor = [UIColor systemBackgroundColor];

        self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
        self.textView.text = code;
        self.textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.textView.editable = NO;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;

        UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [copyButton setTitle:@"Copy" forState:UIControlStateNormal];
        copyButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [copyButton addTarget:self action:@selector(copyToClipboard) forControlEvents:UIControlEventTouchUpInside];
        copyButton.translatesAutoresizingMaskIntoConstraints = NO;

        [self.view addSubview:self.textView];
        [self.view addSubview:copyButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
            [self.textView.bottomAnchor constraintEqualToAnchor:copyButton.topAnchor constant:-10],

            [copyButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [copyButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            [copyButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
            [copyButton.heightAnchor constraintEqualToConstant:44],
        ]];
    }
    return self;
}

- (void)copyToClipboard {
    [UIPasteboard generalPasteboard].string = self.textView.text;
}

@end
