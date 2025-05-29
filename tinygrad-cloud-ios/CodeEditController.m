#import "CodeEditController.h"

// Define NSUserDefaults keys for sizes
static NSString *const kGlobalSizeXKey = @"globalSizeX";
static NSString *const kGlobalSizeYKey = @"globalSizeY";
static NSString *const kGlobalSizeZKey = @"globalSizeZ";
static NSString *const kLocalSizeXKey = @"localSizeX";
static NSString *const kLocalSizeYKey = @"localSizeY";
static NSString *const kLocalSizeZKey = @"localSizeZ";

@interface CodeEditController () <UITextFieldDelegate>
@property (nonatomic, strong) NSString *originalTitle;
@property (nonatomic, strong) NSMutableArray<UITextField *> *globalSizeTextFields;
@property (nonatomic, strong) NSMutableArray<UITextField *> *localSizeTextFields;
@property (nonatomic, strong) UILabel *resultLabel;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@end

@implementation CodeEditController

- (instancetype)initWithCode:(NSString *)code title:(NSString *)title {
    self = [super init];
    if (self) {
        _originalTitle = [title copy];
        self.title = title;
        self.view.backgroundColor = [UIColor systemBackgroundColor];

        // Add a UIScrollView to handle keyboard appearance
        self.scrollView = [[UIScrollView alloc] init];
        self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.scrollView];

        self.contentView = [[UIView alloc] init];
        self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.scrollView addSubview:self.contentView];

        // Text view
        self.textView = [[UITextView alloc] init];
        self.textView.text = code;
        self.textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
        self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.textView.layer.borderColor = [UIColor systemGray5Color].CGColor;
        self.textView.layer.borderWidth = 1.0;
        self.textView.layer.cornerRadius = 5.0;
        self.textView.alwaysBounceVertical = YES;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.textView];

        // Global and Local Size Labels and TextFields
        self.globalSizeTextFields = [NSMutableArray array];
        self.localSizeTextFields = [NSMutableArray array];

        UILabel *globalLabel = [[UILabel alloc] init];
        globalLabel.text = @"Global Size (X, Y, Z):";
        globalLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        globalLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:globalLabel];

        UILabel *localLabel = [[UILabel alloc] init];
        localLabel.text = @"Local Size (X, Y, Z):";
        localLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        localLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:localLabel];

        // Load saved sizes or use default "1"
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *globalKeys = @[kGlobalSizeXKey, kGlobalSizeYKey, kGlobalSizeZKey];
        NSArray<NSString *> *localKeys = @[kLocalSizeXKey, kLocalSizeYKey, kLocalSizeZKey];

        for (int i = 0; i < 3; i++) {
            UITextField *globalTF = [[UITextField alloc] init];
            globalTF.placeholder = (i == 0) ? @"X" : ((i == 1) ? @"Y" : @"Z");
            globalTF.keyboardType = UIKeyboardTypeNumberPad;
            globalTF.borderStyle = UITextBorderStyleRoundedRect;
            globalTF.delegate = self;
            // Load saved value, otherwise default to "1"
            globalTF.text = [defaults stringForKey:globalKeys[i]] ?: @"1";
            globalTF.tag = 100 + i; // Assign unique tags
            globalTF.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:globalTF];
            [self.globalSizeTextFields addObject:globalTF];

            UITextField *localTF = [[UITextField alloc] init];
            localTF.placeholder = (i == 0) ? @"X" : ((i == 1) ? @"Y" : @"Z");
            localTF.keyboardType = UIKeyboardTypeNumberPad;
            localTF.borderStyle = UITextBorderStyleRoundedRect;
            localTF.delegate = self;
            // Load saved value, otherwise default to "1"
            localTF.text = [defaults stringForKey:localKeys[i]] ?: @"1";
            localTF.tag = 200 + i; // Assign unique tags
            localTF.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:localTF];
            [self.localSizeTextFields addObject:localTF];
        }

        // Run Button
        UIButton *runButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [runButton setTitle:@"Run Kernel" forState:UIControlStateNormal];
        [runButton addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];
        runButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        runButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:runButton];

        // Result Label
        self.resultLabel = [[UILabel alloc] init];
        self.resultLabel.textAlignment = NSTextAlignmentCenter;
        self.resultLabel.font = [UIFont systemFontOfSize:16];
        self.resultLabel.numberOfLines = 0;
        self.resultLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.resultLabel];

        // Constraints for scrollView and contentView
        [NSLayoutConstraint activateConstraints:@[
            [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

            [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
            [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
            [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor] // Important for vertical scrolling
        ]];

        // Constraints for elements within contentView
        CGFloat padding = 10.0;
        [NSLayoutConstraint activateConstraints:@[
            [self.textView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:padding],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
            [self.textView.heightAnchor constraintGreaterThanOrEqualToConstant:100], // Minimum height
            [self.textView.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor multiplier:0.4], // Max 40% of view

            // Global Size
            [globalLabel.topAnchor constraintEqualToAnchor:self.textView.bottomAnchor constant:padding],
            [globalLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],

            [self.globalSizeTextFields[0].topAnchor constraintEqualToAnchor:globalLabel.bottomAnchor constant:padding/2],
            [self.globalSizeTextFields[0].leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.globalSizeTextFields[0].widthAnchor constraintEqualToConstant:70],

            [self.globalSizeTextFields[1].topAnchor constraintEqualToAnchor:self.globalSizeTextFields[0].topAnchor],
            [self.globalSizeTextFields[1].leadingAnchor constraintEqualToAnchor:self.globalSizeTextFields[0].trailingAnchor constant:padding],
            [self.globalSizeTextFields[1].widthAnchor constraintEqualToConstant:70],

            [self.globalSizeTextFields[2].topAnchor constraintEqualToAnchor:self.globalSizeTextFields[0].topAnchor],
            [self.globalSizeTextFields[2].leadingAnchor constraintEqualToAnchor:self.globalSizeTextFields[1].trailingAnchor constant:padding],
            [self.globalSizeTextFields[2].widthAnchor constraintEqualToConstant:70],

            // Local Size
            [localLabel.topAnchor constraintEqualToAnchor:self.globalSizeTextFields[0].bottomAnchor constant:padding],
            [localLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],

            [self.localSizeTextFields[0].topAnchor constraintEqualToAnchor:localLabel.bottomAnchor constant:padding/2],
            [self.localSizeTextFields[0].leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.localSizeTextFields[0].widthAnchor constraintEqualToConstant:70],

            [self.localSizeTextFields[1].topAnchor constraintEqualToAnchor:self.localSizeTextFields[0].topAnchor],
            [self.localSizeTextFields[1].leadingAnchor constraintEqualToAnchor:self.localSizeTextFields[0].trailingAnchor constant:padding],
            [self.localSizeTextFields[1].widthAnchor constraintEqualToConstant:70],

            [self.localSizeTextFields[2].topAnchor constraintEqualToAnchor:self.localSizeTextFields[0].topAnchor],
            [self.localSizeTextFields[2].leadingAnchor constraintEqualToAnchor:self.localSizeTextFields[1].trailingAnchor constant:padding],
            [self.localSizeTextFields[2].widthAnchor constraintEqualToConstant:70],

            // Run Button
            [runButton.topAnchor constraintEqualToAnchor:self.localSizeTextFields[0].bottomAnchor constant:padding * 2],
            [runButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [runButton.heightAnchor constraintEqualToConstant:44],

            // Result Label
            [self.resultLabel.topAnchor constraintEqualToAnchor:runButton.bottomAnchor constant:padding],
            [self.resultLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.resultLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
            [self.resultLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding], // Pin to bottom of contentView
        ]];

        // Navigation items
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                              target:self
                                                                                              action:@selector(saveTapped)];

        // Register for keyboard notifications
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)saveTapped {
    [self.view endEditing:YES]; // Dismiss keyboard before saving

    // Save the kernel code
    if (self.onSave) {
        self.onSave(self.textView.text);
    }

    // Save the global and local sizes to NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *globalKeys = @[kGlobalSizeXKey, kGlobalSizeYKey, kGlobalSizeZKey];
    NSArray<NSString *> *localKeys = @[kLocalSizeXKey, kLocalSizeYKey, kLocalSizeZKey];

    for (int i = 0; i < 3; i++) {
        [defaults setObject:self.globalSizeTextFields[i].text forKey:globalKeys[i]];
        [defaults setObject:self.localSizeTextFields[i].text forKey:localKeys[i]];
    }
    [defaults synchronize]; // Ensure immediate saving

    // Provide visual feedback that saving occurred
    self.resultLabel.textColor = [UIColor systemGreenColor];
    self.resultLabel.text = @"Kernel code and sizes saved successfully!";
    // You might want to clear the result label after a short delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.resultLabel.text = @"";
    });
}

- (void)runTapped {
    [self.view endEditing:YES]; // Dismiss keyboard

    // This button does nothing for now, as per the request.

    // Example of how you would collect the data if it were to run:
    NSMutableArray<NSNumber *> *globalSizes = [NSMutableArray array];
    for (UITextField *tf in self.globalSizeTextFields) {
        [globalSizes addObject:@(tf.text.integerValue)];
    }

    NSMutableArray<NSNumber *> *localSizes = [NSMutableArray array];
    for (UITextField *tf in self.localSizeTextFields) {
        [localSizes addObject:@(tf.text.integerValue)];
    }

    self.resultLabel.textColor = [UIColor systemOrangeColor];
    self.resultLabel.text = @"Run button functionality is currently disabled.";

    /*
    // Example of how to call the delegate if it were active
    if ([self.delegate respondsToSelector:@selector(codeEditController:didRequestRunCode:globalSizes:localSizes:)]) {
        [self.delegate codeEditController:self
                       didRequestRunCode:self.textView.text
                             globalSizes:globalSizes
                              localSizes:localSizes];
    }
    */
}

#pragma mark - Keyboard Handling

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSValue *keyboardFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
    CGRect keyboardFrame = [keyboardFrameValue CGRectValue];
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardFrame.size.height, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;

    // Find the currently active text field
    UITextField *activeTextField = nil;
    for (UITextField *textField in self.globalSizeTextFields) {
        if ([textField isFirstResponder]) {
            activeTextField = textField;
            break;
        }
    }
    if (!activeTextField) {
        for (UITextField *textField in self.localSizeTextFields) {
            if ([textField isFirstResponder]) {
                activeTextField = textField;
                break;
            }
        }
    }

    if (activeTextField) {
        // Calculate the rect of the active text field in the scroll view's coordinate system
        CGRect rect = [self.scrollView convertRect:activeTextField.bounds fromView:activeTextField];
        // Adjust for any insets from the navigation bar/safe area if needed
        rect.origin.y -= self.scrollView.contentOffset.y; // Account for current scroll offset
        rect.size.height += 10; // Add some padding below the text field

        // Check if the text field is obscured by the keyboard
        CGRect visibleRect = self.scrollView.bounds;
        visibleRect.size.height -= keyboardFrame.size.height; // Area visible above keyboard

        if (!CGRectContainsRect(visibleRect, rect)) {
            [self.scrollView scrollRectToVisible:rect animated:YES];
        }
    }

    // Add a "Done" button to the number pad
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonTapped)];
    [toolbar setItems:@[flexSpace, doneButton] animated:NO];

    for (UITextField *textField in self.globalSizeTextFields) {
        textField.inputAccessoryView = toolbar;
    }
    for (UITextField *textField in self.localSizeTextFields) {
        textField.inputAccessoryView = toolbar;
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSTimeInterval animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)doneButtonTapped {
    [self.view endEditing:YES]; // Dismiss the keyboard
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

// Public method to update run result label (can still be used if run button is enabled later)
- (void)updateRunResult:(NSString *)result isError:(BOOL)isError {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.resultLabel.textColor = isError ? [UIColor systemRedColor] : [UIColor systemGreenColor];
        self.resultLabel.text = result;
    });
}

@end
