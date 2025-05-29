#import "CodeEditController.h"
#import <Metal/Metal.h>

static id<MTLDevice> device;
static id<MTLCommandQueue> mtl_queue;

@interface CodeEditController () <UITextFieldDelegate>
@property (nonatomic, strong) NSString *originalTitle;
@property (nonatomic, strong) NSMutableArray<UITextField *> *globalSizeTextFields;
@property (nonatomic, strong) NSMutableArray<UITextField *> *localSizeTextFields;
@property (nonatomic, strong) UILabel *resultLabel;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Property to hold the dynamic height constraint for the textView
@property (nonatomic, strong) NSLayoutConstraint *textViewDynamicHeightConstraint;

// NEW: Properties for dynamic inputs
@property (nonatomic, strong) UIStackView *inputsStackView; // Vertical stack view for all input rows
@property (nonatomic, strong) NSMutableArray<UITextField *> *inputTextFields; // Array to keep track of input text fields

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

        // Load saved sizes or use default "1"
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *suffixKeys = @[@"_X", @"_Y", @"_Z"]; // Suffixes for dynamic keys

        for (int i = 0; i < 3; i++) {
            // Global Size Text Field
            UITextField *globalTF = [[UITextField alloc] init];
            globalTF.placeholder = (i == 0) ? @"X" : ((i == 1) ? @"Y" : @"Z");
            globalTF.keyboardType = UIKeyboardTypeNumberPad;
            globalTF.borderStyle = UITextBorderStyleRoundedRect;
            globalTF.delegate = self;
            
            // Construct dynamic key for global size
            NSString *globalKey = [NSString stringWithFormat:@"%@_globalSize%@", self.originalTitle, suffixKeys[i]];
            globalTF.text = [defaults stringForKey:globalKey] ?: @"1"; // Load per-kernel value
            
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

            // Construct dynamic key for local size
            NSString *localKey = [NSString stringWithFormat:@"%@_localSize%@", self.originalTitle, suffixKeys[i]];
            localTF.text = [defaults stringForKey:localKey] ?: @"1"; // Load per-kernel value
            
            localTF.tag = 200 + i; // Assign unique tags for keyboard handling
            localTF.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:localTF];
            [self.localSizeTextFields addObject:localTF];
        }

        // NEW: Inputs Section
        UILabel *inputsLabel = [[UILabel alloc] init];
        inputsLabel.text = @"Kernel Inputs (Byte Sizes):";
        inputsLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        inputsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:inputsLabel];

        self.inputsStackView = [[UIStackView alloc] init];
        self.inputsStackView.axis = UILayoutConstraintAxisVertical;
        self.inputsStackView.distribution = UIStackViewDistributionFill;
        self.inputsStackView.alignment = UIStackViewAlignmentLeading; // Align left
        self.inputsStackView.spacing = padding / 2; // Half padding between input rows
        self.inputsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.inputsStackView];

        self.inputTextFields = [NSMutableArray array]; // Initialize the array for tracking text fields

        UIButton *addInputButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [addInputButton setTitle:@"Add Input" forState:UIControlStateNormal];
        [addInputButton addTarget:self action:@selector(addInputTapped) forControlEvents:UIControlEventTouchUpInside];
        addInputButton.titleLabel.font = [UIFont systemFontOfSize:16];
        addInputButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:addInputButton];
        
        // Load existing inputs or add a default one
        NSString *inputSizesKey = [NSString stringWithFormat:@"%@_inputSizes", self.originalTitle];
        NSArray<NSString *> *savedInputSizes = [defaults arrayForKey:inputSizesKey];
        if (savedInputSizes.count > 0) {
            for (NSString *inputSizeText in savedInputSizes) {
                [self addInputRowWithText:inputSizeText];
            }
        } else {
            // Add one default empty input field if none saved
            [self addInputRowWithText:@""];
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
            // Set a higher minimum height for the text view, which will act as a lower bound for dynamic height
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

            // NEW: Inputs section constraints
            [inputsLabel.topAnchor constraintEqualToAnchor:self.localSizeTextFields[0].bottomAnchor constant:padding],
            [inputsLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],

            [self.inputsStackView.topAnchor constraintEqualToAnchor:inputsLabel.bottomAnchor constant:padding/2],
            [self.inputsStackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.inputsStackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
            // Keep stack view height flexible
            
            [addInputButton.topAnchor constraintEqualToAnchor:self.inputsStackView.bottomAnchor constant:padding/2],
            [addInputButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [addInputButton.heightAnchor constraintEqualToConstant:30], // Smaller button

            // Run Button (now relative to addInputButton)
            [runButton.topAnchor constraintEqualToAnchor:addInputButton.bottomAnchor constant:padding * 2],
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(textViewDidChangeNotification:)
                                                     name:UITextViewTextDidChangeNotification
                                                   object:self.textView];

        // NEW: Force layout and update text view height for initial content
        [self.view layoutIfNeeded]; // Ensure textView has a valid frame
        [self updateTextViewHeight]; // Update height based on initial content
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dynamic Input Methods

- (void)addInputRowWithText:(NSString *)initialText {
    NSInteger inputCount = self.inputTextFields.count;

    UIStackView *rowStackView = [[UIStackView alloc] init];
    rowStackView.axis = UILayoutConstraintAxisHorizontal;
    rowStackView.distribution = UIStackViewDistributionFill;
    rowStackView.alignment = UIStackViewAlignmentCenter;
    rowStackView.spacing = 8;
    rowStackView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"Input %ld:", (long)(inputCount + 1)];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [rowStackView addArrangedSubview:label];

    UITextField *textField = [[UITextField alloc] init];
    textField.placeholder = @"Byte Size";
    textField.text = initialText;
    textField.keyboardType = UIKeyboardTypeNumberPad;
    textField.borderStyle = UITextBorderStyleRoundedRect;
    textField.delegate = self;
    textField.tag = 300 + inputCount; // Assign unique tags starting from 300
    [rowStackView addArrangedSubview:textField];
    [self.inputTextFields addObject:textField]; // Keep track of the text field

    // Constraint for textField width to make it look decent
    [textField.widthAnchor constraintEqualToConstant:100].active = YES;

    UIButton *removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [removeButton setTitle:@"Remove" forState:UIControlStateNormal];
    [removeButton addTarget:self action:@selector(removeInputTapped:) forControlEvents:UIControlEventTouchUpInside];
    removeButton.tag = inputCount; // Use the index for removal
    [rowStackView addArrangedSubview:removeButton];
    
    [self.inputsStackView addArrangedSubview:rowStackView];

    // Ensure layout updates after adding
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)addInputTapped {
    [self addInputRowWithText:@""]; // Add a new empty input field
}

- (void)removeInputTapped:(UIButton *)sender {
    if (self.inputTextFields.count <= 1) {
        // Prevent removing the last input field, show a message or disable button
        self.resultLabel.textColor = [UIColor systemOrangeColor];
        self.resultLabel.text = @"Cannot remove the last input field.";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.resultLabel.text = @"";
        });
        return;
    }

    // Get the stack view containing the button (the horizontal row stack view)
    UIStackView *rowToRemove = (UIStackView *)sender.superview;
    if (rowToRemove && [self.inputsStackView.arrangedSubviews containsObject:rowToRemove]) {
        // Remove the associated text field from our tracking array
        UITextField *textFieldToRemove = nil;
        for (UIView *subview in rowToRemove.arrangedSubviews) {
            if ([subview isKindOfClass:[UITextField class]]) {
                textFieldToRemove = (UITextField *)subview;
                break;
            }
        }
        if (textFieldToRemove) {
            [self.inputTextFields removeObject:textFieldToRemove];
        }

        [self.inputsStackView removeArrangedSubview:rowToRemove];
        [rowToRemove removeFromSuperview];

        // Re-label inputs and re-tag buttons after removal
        [self updateInputLabelsAndTags];
        
        // Ensure layout updates after removing
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }
}

// Helper to update labels and tags after adding/removing rows
- (void)updateInputLabelsAndTags {
    for (int i = 0; i < self.inputsStackView.arrangedSubviews.count; i++) {
        UIStackView *rowStackView = self.inputsStackView.arrangedSubviews[i];
        UILabel *label = nil;
        UITextField *textField = nil;
        UIButton *removeButton = nil;

        for (UIView *subview in rowStackView.arrangedSubviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                label = (UILabel *)subview;
            } else if ([subview isKindOfClass:[UITextField class]]) {
                textField = (UITextField *)subview;
            } else if ([subview isKindOfClass:[UIButton class]]) {
                removeButton = (UIButton *)subview;
            }
        }

        if (label) {
            label.text = [NSString stringWithFormat:@"Input %ld:", (long)(i + 1)];
        }
        if (textField) {
            textField.tag = 300 + i;
        }
        if (removeButton) {
            removeButton.tag = i;
        }
    }
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

    // NEW: Save the input sizes
    NSMutableArray<NSString *> *currentInputSizes = [NSMutableArray array];
    for (UITextField *inputTF in self.inputTextFields) {
        // Only save non-empty inputs, or you might want to save all for consistency
        if (inputTF.text.length > 0) {
            [currentInputSizes addObject:inputTF.text];
        } else {
            [currentInputSizes addObject:@""]; // Save empty string if field is empty
        }
    }
    NSString *inputSizesKey = [NSString stringWithFormat:@"%@_inputSizes", self.originalTitle];
    [defaults setObject:currentInputSizes forKey:inputSizesKey];

    [defaults synchronize]; // Ensure immediate saving
}

- (void)runTapped {
    [self.view endEditing:YES]; // Dismiss keyboard

    // Get the kernel code from the text view
    NSString *kernelCode = self.textView.text;

    // Compile the Metal library
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kernelCode options:nil error:&error];
    if (!library) {
        self.resultLabel.textColor = [UIColor systemRedColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Compile Error: %@", error.localizedDescription];
        return;
    }

    // Derive the Metal function name from originalTitle by replacing non-alphanumeric chars with underscores
    NSString *safeKernelName = [[self.originalTitle componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];

    // Get the kernel function
    id<MTLFunction> kernelFunction = [library newFunctionWithName:safeKernelName];
    if (!kernelFunction) {
        self.resultLabel.textColor = [UIColor systemRedColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Kernel function '%@' not found in compiled code.", safeKernelName];
        return;
    }

    // Create the compute pipeline state
    id<MTLComputePipelineState> pipelineState = [device newComputePipelineStateWithFunction:kernelFunction error:&error];
    if (!pipelineState) {
        self.resultLabel.textColor = [UIColor systemRedColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Pipeline State Creation Error: %@", error.localizedDescription];
        return;
    }

    // Get global and local sizes from text fields
    MTLSize globalSize = MTLSizeMake([self.globalSizeTextFields[0].text integerValue],
                                     [self.globalSizeTextFields[1].text integerValue],
                                     [self.globalSizeTextFields[2].text integerValue]);
    
    MTLSize localSize = MTLSizeMake([self.localSizeTextFields[0].text integerValue],
                                    [self.localSizeTextFields[1].text integerValue],
                                    [self.localSizeTextFields[2].text integerValue]);

    // Validate sizes (optional but good practice)
    if (globalSize.width == 0 || globalSize.height == 0 || globalSize.depth == 0 ||
        localSize.width == 0 || localSize.height == 0 || localSize.depth == 0) {
        self.resultLabel.textColor = [UIColor systemOrangeColor];
        self.resultLabel.text = @"Global or Local size cannot be zero. Please enter valid numbers.";
        return;
    }

    // Create command buffer and encoder
    id<MTLCommandBuffer> commandBuffer = [mtl_queue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    [computeEncoder setComputePipelineState:pipelineState];

    // Create and set buffers for kernel inputs
    NSMutableArray<id<MTLBuffer>> *buffers = [NSMutableArray array];
    for (int i = 0; i < self.inputTextFields.count; i++) {
        UITextField *inputTF = self.inputTextFields[i];
        NSInteger byteSize = [inputTF.text integerValue];

        if (byteSize <= 0) {
            self.resultLabel.textColor = [UIColor systemOrangeColor];
            self.resultLabel.text = [NSString stringWithFormat:@"Input %d byte size must be greater than 0.", i + 1];
            // Clean up any buffers already created
            for (id<MTLBuffer> buf in buffers) {
                // In a real app, you might want to reset buffer content or handle it differently.
                // For simplicity here, we're just letting them deallocate.
            }
            return;
        }

        id<MTLBuffer> buffer = [device newBufferWithLength:byteSize options:MTLResourceStorageModeShared];
        // Initialize buffer with some data if needed, e.g., zeros
        memset(buffer.contents, 0, byteSize);
        // You might want to initialize the first float to a known value for testing
        if (byteSize >= sizeof(float)) {
             ((float*)buffer.contents)[0] = 1.0f; // Example: Set first float to 1.0
        }
        
        [computeEncoder setBuffer:buffer offset:0 atIndex:i];
        [buffers addObject:buffer];
    }
    
    // Dispatch threadgroups
    [computeEncoder dispatchThreadgroups:globalSize threadsPerThreadgroup:localSize];
    [computeEncoder endEncoding];
    [commandBuffer commit];

    // Wait for completion and get result (from the first buffer, if available)
    [commandBuffer waitUntilCompleted];
    float gpuTimeMs = (float)((commandBuffer.GPUEndTime - commandBuffer.GPUStartTime) * 1000.0);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.resultLabel.textColor = [UIColor systemBlueColor];
        self.resultLabel.text = [NSString stringWithFormat:@"Kernel ran in %.3f ms", gpuTimeMs];
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
        // NEW: Check dynamic input text fields
        if (!activeInput) {
            for (UITextField *textField in self.inputTextFields) {
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
    // NEW: Apply input accessory view to dynamic input text fields
    for (UITextField *textField in self.inputTextFields) {
        textField.inputAccessoryView = toolbar;
    }
    // No input accessory view for UITextView, as it typically has its own keyboard actions
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
