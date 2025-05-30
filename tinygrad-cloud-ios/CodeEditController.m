#import "CodeEditController.h"
#import <Metal/Metal.h>
#import "tinygrad.h"

static id<MTLDevice> device;
static id<MTLCommandQueue> mtl_queue;

@interface CodeEditController () <UITextFieldDelegate>
@property (nonatomic, strong) NSString *originalTitle;
@property (nonatomic, strong) NSMutableArray<UITextField *> *globalSizeTextFields;
@property (nonatomic, strong) NSMutableArray<UITextField *> *localSizeTextFields;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) NSNumber *lastExecutionTime; // in microseconds

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Property to hold the dynamic height constraint for the textView
@property (nonatomic, strong) NSLayoutConstraint *textViewDynamicHeightConstraint;

// Declare runTapped method in the interface so it's visible within the @implementation
- (void)runTapped;

@end

@implementation CodeEditController

- (instancetype)initWithCode:(NSString *)code title:(NSString *)title {
    self = [super init];
    if (self) {
        device = MTLCreateSystemDefaultDevice();
        mtl_queue = [device newCommandQueueWithMaxCommandBufferCount:1024];
        _originalTitle = [title copy];
        self.title = title;
        self.view.backgroundColor = [UIColor systemBackgroundColor];

        // Declare padding here, at the beginning of the method
        CGFloat padding = 10.0;

        // Add a UIScrollView to handle keyboard appearance and long content
        self.scrollView = [[UIScrollView alloc] init];
        self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.scrollView];

        self.contentView = [[UIView alloc] init];
        self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.scrollView addSubview:self.contentView];

        // Text view
        self.textView = [[UITextView alloc] init];
        self.textView.text = code; // Set the initial code here
        self.textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
        self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.textView.layer.borderColor = [UIColor systemGray5Color].CGColor;
        self.textView.layer.borderWidth = 1.0;
        self.textView.layer.cornerRadius = 5.0;
        self.textView.alwaysBounceVertical = YES; // This enables its own internal scrolling if content is too long for its frame
        self.textView.scrollEnabled = NO; // IMPORTANT: Disable internal scrolling to allow parent UIScrollView to handle it
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

        // Load saved sizes or use defaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *suffixKeys = @[@"_X", @"_Y", @"_Z"]; // Suffixes for dynamic keys
        NSArray<NSNumber *> *tinygradDims = nil;

        // Check if this is a tinygrad kernel and get dimensions if available
        if ([tinygrad getKernelCodeForKey:title]) {
            tinygradDims = [tinygrad getDimsForKey:title];
        }

        for (int i = 0; i < 3; i++) {
            // Global Size Text Field
            UITextField *globalTF = [[UITextField alloc] init];
            globalTF.placeholder = (i == 0) ? @"X" : ((i == 1) ? @"Y" : @"Z");
            globalTF.keyboardType = UIKeyboardTypeNumberPad;
            globalTF.borderStyle = UITextBorderStyleRoundedRect;
            globalTF.delegate = self;
            
            // Set global size: prefer saved value, then tinygrad dimension, then default "1"
            NSString *globalKey = [NSString stringWithFormat:@"%@_globalSize%@", self.originalTitle, suffixKeys[i]];
            NSString *globalText = [defaults stringForKey:globalKey];
            if (!globalText && tinygradDims && i < 3 && [tinygradDims[i] intValue] > 0) {
                globalText = [tinygradDims[i] stringValue]; // Use tinygrad global size (indices 0, 1, 2)
            }
            globalTF.text = globalText ?: @"1";
            
            globalTF.tag = 100 + i; // Assign unique tags for keyboard handling
            globalTF.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:globalTF];
            [self.globalSizeTextFields addObject:globalTF];

            // Local Size Text Field
            UITextField *localTF = [[UITextField alloc] init];
            localTF.placeholder = (i == 0) ? @"X" : ((i == 1) ? @"Y" : @"Z");
            localTF.keyboardType = UIKeyboardTypeNumberPad;
            localTF.borderStyle = UITextBorderStyleRoundedRect;
            localTF.delegate = self;

            // Set local size: prefer saved value, then tinygrad dimension, then default "1"
            NSString *localKey = [NSString stringWithFormat:@"%@_localSize%@", self.originalTitle, suffixKeys[i]];
            NSString *localText = [defaults stringForKey:localKey];
            if (!localText && tinygradDims && i < 3 && [tinygradDims[i + 3] intValue] > 0) {
                localText = [tinygradDims[i + 3] stringValue]; // Use tinygrad local size (indices 3, 4, 5)
            }
            localTF.text = localText ?: @"1";
            
            localTF.tag = 200 + i; // Assign unique tags for keyboard handling
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

        // Initialize the dynamic height constraint
        CGFloat initialTextViewWidth = CGRectGetWidth(self.view.bounds) - (2 * padding);
        if (initialTextViewWidth <= 0) initialTextViewWidth = 300; // Fallback if view bounds not yet available
        
        CGSize initialSize = [self.textView sizeThatFits:CGSizeMake(initialTextViewWidth, CGFLOAT_MAX)];
        self.textViewDynamicHeightConstraint = [self.textView.heightAnchor constraintEqualToConstant:MAX(initialSize.height, 250.0)];
        [self.textViewDynamicHeightConstraint setActive:YES];

        // Constraints for elements within contentView
        [NSLayoutConstraint activateConstraints:@[
            [self.textView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:padding],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
            [self.textView.heightAnchor constraintGreaterThanOrEqualToConstant:250],

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
            [self.resultLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(textViewDidChangeNotification:)
                                                     name:UITextViewTextDidChangeNotification
                                                   object:self.textView];

        // Force layout and update text view height for initial content
        [self.view layoutIfNeeded];
        [self updateTextViewHeight];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Layout & Lifecycle

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Update text view height to ensure it fits content during layout changes
    [self updateTextViewHeight];
}

- (void)textViewDidChangeNotification:(NSNotification *)notification {
    // Update text view height when content changes
    [self updateTextViewHeight];
}

- (void)updateTextViewHeight {
    // Ensure the text view has a valid width
    CGFloat fixedWidth = self.textView.frame.size.width;
    if (fixedWidth <= 0) {
        fixedWidth = CGRectGetWidth(self.view.bounds) - 20.0; // Fallback: 10.0 padding on each side
        if (fixedWidth <= 0) fixedWidth = 300; // Absolute fallback
    }

    // Calculate the content size
    CGSize newSize = [self.textView sizeThatFits:CGSizeMake(fixedWidth, CGFLOAT_MAX)];
    CGFloat targetHeight = MAX(newSize.height, 250.0); // Respect minimum height of 250

    // Update the dynamic height constraint if needed
    if (fabs(self.textViewDynamicHeightConstraint.constant - targetHeight) > 0.1) {
        self.textViewDynamicHeightConstraint.constant = targetHeight;
        // Animate the layout change for smoothness
        [UIView animateWithDuration:0.1 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
}

#pragma mark - Actions

- (void)saveTapped {
    [self.view endEditing:YES]; // Dismiss keyboard before saving

    // Save the kernel code
    if (self.onSave) {
        self.onSave(self.textView.text);
    }

    // Save the global and local sizes to NSUserDefaults for this specific kernel
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *suffixKeys = @[@"_X", @"_Y", @"_Z"]; // Suffixes for dynamic keys

    for (int i = 0; i < 3; i++) {
        NSString *globalKey = [NSString stringWithFormat:@"%@_globalSize%@", self.originalTitle, suffixKeys[i]];
        NSString *localKey = [NSString stringWithFormat:@"%@_localSize%@", self.originalTitle, suffixKeys[i]];
        
        [defaults setObject:self.globalSizeTextFields[i].text forKey:globalKey];
        [defaults setObject:self.localSizeTextFields[i].text forKey:localKey];
    }

    [defaults synchronize]; // Ensure immediate saving
}

- (void)runTapped {
    [self.view endEditing:YES]; // Dismiss keyboard

    NSString *kernelCode = self.textView.text;

    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kernelCode options:nil error:&error];
    if (!library) {
        self.resultLabel.textColor = [UIColor systemRedColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Compile Error: %@", error.localizedDescription];
        return;
    }

    NSString *safeKernelName = [[self.originalTitle componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];

    id<MTLFunction> kernelFunction = [library newFunctionWithName:safeKernelName];
    if (!kernelFunction) {
        self.resultLabel.textColor = [UIColor systemRedColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Kernel function '%@' not found in compiled code.", safeKernelName];
        return;
    }

    id<MTLComputePipelineState> pipelineState = [device newComputePipelineStateWithFunction:kernelFunction error:&error];
    if (!pipelineState) {
        self.resultLabel.textColor = [UIColor systemRedColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Pipeline State Creation Error: %@", error.localizedDescription];
        return;
    }

    MTLSize globalSize = MTLSizeMake([self.globalSizeTextFields[0].text integerValue],
                                     [self.globalSizeTextFields[1].text integerValue],
                                     [self.globalSizeTextFields[2].text integerValue]);

    MTLSize localSize = MTLSizeMake([self.localSizeTextFields[0].text integerValue],
                                    [self.localSizeTextFields[1].text integerValue],
                                    [self.localSizeTextFields[2].text integerValue]);

    if (globalSize.width == 0 || globalSize.height == 0 || globalSize.depth == 0 ||
        localSize.width == 0 || localSize.height == 0 || localSize.depth == 0) {
        self.resultLabel.textColor = [UIColor systemOrangeColor];
        self.resultLabel.text = @"Global or Local size cannot be zero. Please enter valid numbers.";
        return;
    }

    NSUInteger totalThreads = localSize.width * localSize.height * localSize.depth;
    if (totalThreads > pipelineState.maxTotalThreadsPerThreadgroup) {
        self.resultLabel.textColor = [UIColor systemRedColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Total local threads (%lu) exceed maximum supported (%lu).",
                                 (unsigned long)totalThreads, (unsigned long)pipelineState.maxTotalThreadsPerThreadgroup];
        return;
    }

    // Infer the number of 'device' and 'constant' inputs from the kernel code
    NSUInteger deviceCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bdevice\\b" options:0 error:nil] numberOfMatchesInString:kernelCode options:0 range:NSMakeRange(0, kernelCode.length)];
    NSUInteger constantCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bconstant\\b" options:0 error:nil] numberOfMatchesInString:kernelCode options:0 range:NSMakeRange(0, kernelCode.length)];
    
    NSUInteger totalBuffers = deviceCount + constantCount;

    id<MTLCommandBuffer> commandBuffer = [mtl_queue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    [computeEncoder setComputePipelineState:pipelineState];

    NSMutableArray<id<MTLBuffer>> *buffers = [NSMutableArray array];
    for (NSUInteger i = 0; i < totalBuffers; i++) {
        NSInteger byteSize = 8; // Default size for all buffers

        id<MTLBuffer> buffer = [device newBufferWithLength:byteSize options:MTLResourceStorageModeShared];
        if (!buffer) {
            self.resultLabel.textColor = [UIColor systemRedColor];
            self.resultLabel.text = [NSString stringWithFormat:@"Failed to create buffer of size %ld for index %lu.", (long)byteSize, (unsigned long)i];
            return;
        }

        memset(buffer.contents, 0, byteSize);
        [computeEncoder setBuffer:buffer offset:0 atIndex:i];
        [buffers addObject:buffer];
    }

    // Encode and commit
    @try {
        [computeEncoder dispatchThreadgroups:globalSize threadsPerThreadgroup:localSize];
        [computeEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    } @catch (NSException *exception) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.resultLabel.textColor = [UIColor systemRedColor];
            self.resultLabel.text = @"Dispatch failed. Please check threadgroup sizes and buffer usage.";
        });
        return;
    }

    float gpuTimeNs = (float)((commandBuffer.GPUEndTime - commandBuffer.GPUStartTime) * 1e9);
    self.lastExecutionTime = @(gpuTimeNs);
    NSString *timeKey = [NSString stringWithFormat:@"%@_lastExecutionTime", self.originalTitle];
    [[NSUserDefaults standardUserDefaults] setObject:self.lastExecutionTime forKey:timeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.resultLabel.textColor = [UIColor systemBlueColor];
        if (gpuTimeNs >= 1e6) {
            self.resultLabel.text = [NSString stringWithFormat:@"Kernel ran in %.3f ms", gpuTimeNs / 1e6];
        } else {
            self.resultLabel.text = [NSString stringWithFormat:@"Kernel ran in %.0f µs", gpuTimeNs / 1e3];
        }
    });
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

    // Find the currently active text field or text view
    UIView *activeInput = nil;
    if ([self.textView isFirstResponder]) {
        activeInput = self.textView;
    } else {
        // Check global size text fields
        for (UITextField *textField in self.globalSizeTextFields) {
            if ([textField isFirstResponder]) {
                activeInput = textField;
                break;
            }
        }
        // Check local size text fields
        if (!activeInput) {
            for (UITextField *textField in self.localSizeTextFields) {
                if ([textField isFirstResponder]) {
                    activeInput = textField;
                    break;
                }
            }
        }
    }

    if (activeInput) {
        // Calculate the rect of the active input in the scroll view's coordinate system
        CGRect rect = [self.scrollView convertRect:activeInput.bounds fromView:activeInput];
        // Adjust for any insets from the navigation bar/safe area if needed
        rect.origin.y -= self.scrollView.contentOffset.y; // Account for current scroll offset
        rect.size.height += 10; // Add some padding below the input field

        // Check if the input is obscured by the keyboard
        CGRect visibleRect = self.scrollView.bounds;
        visibleRect.size.height -= keyboardFrame.size.height; // Area visible above keyboard

        if (!CGRectContainsRect(visibleRect, rect)) {
            [self.scrollView scrollRectToVisible:rect animated:YES];
        }
    }

    // Add a "Done" button to the number pad for text fields
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
