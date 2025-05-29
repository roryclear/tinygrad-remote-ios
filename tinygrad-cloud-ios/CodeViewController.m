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
        
        UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
        UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
        toolbar.items = @[flexSpace, doneButton];
        [self.textView setInputAccessoryView:toolbar];

        // Copy button
        UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [copyButton setTitle:@"Copy" forState:UIControlStateNormal];
        copyButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [copyButton addTarget:self action:@selector(copyToClipboard) forControlEvents:UIControlEventTouchUpInside];
        copyButton.translatesAutoresizingMaskIntoConstraints = NO;

        // Add views
        [self.view addSubview:self.textView];
        [self.view addSubview:copyButton];

        // Constraints
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

- (void)dismissKeyboard {
    [self.textView resignFirstResponder];
}

- (void)copyToClipboard {
    [UIPasteboard generalPasteboard].string = self.textView.text;
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

