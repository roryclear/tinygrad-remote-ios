#import "CodeEditController.h"

@interface CodeEditController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSString *originalTitle;
@end

@implementation CodeEditController

- (instancetype)initWithCode:(NSString *)code title:(NSString *)title {
    self = [super init];
    if (self) {
        _originalTitle = [title copy];
        self.title = title;
        self.view.backgroundColor = [UIColor systemBackgroundColor];

        // Text view
        self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
        self.textView.text = code;
        self.textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
        self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.textView];

        // Constraints
        [NSLayoutConstraint activateConstraints:@[
            [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
        ]];

        // Navigation items
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                              target:self
                                                                                              action:@selector(saveTapped)];
    }
    return self;
}

- (void)saveTapped {
    if (self.onSave) {
        self.onSave(self.textView.text);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end
