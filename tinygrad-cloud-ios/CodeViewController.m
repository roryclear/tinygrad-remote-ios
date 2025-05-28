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

        // Text view
        self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
        self.textView.text = code;
        self.textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.textView.editable = YES;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;

        // Buttons
        UIButton *runButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [runButton setTitle:@"Run" forState:UIControlStateNormal];
        runButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        runButton.translatesAutoresizingMaskIntoConstraints = NO;

        UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [saveButton setTitle:@"Save" forState:UIControlStateNormal];
        saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        saveButton.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[runButton, saveButton]];
        buttonStack.axis = UILayoutConstraintAxisHorizontal;
        buttonStack.distribution = UIStackViewDistributionFillEqually;
        buttonStack.spacing = 20;
        buttonStack.translatesAutoresizingMaskIntoConstraints = NO;

        // Add views
        [self.view addSubview:self.textView];
        [self.view addSubview:buttonStack];

        // Constraints
        [NSLayoutConstraint activateConstraints:@[
            [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
            [self.textView.bottomAnchor constraintEqualToAnchor:buttonStack.topAnchor constant:-10],

            [buttonStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [buttonStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            [buttonStack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
            [buttonStack.heightAnchor constraintEqualToConstant:44],
        ]];

        // Keyboard notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillShow:)
                                                     name:UIKeyboardWillShowNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillHide:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:nil];
    }
    return self;
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect kbFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, kbFrame.size.height + 10, 0);

    [UIView animateWithDuration:duration animations:^{
        self.textView.contentInset = insets;
        self.textView.scrollIndicatorInsets = insets;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    double duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    [UIView animateWithDuration:duration animations:^{
        self.textView.contentInset = UIEdgeInsetsZero;
        self.textView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

