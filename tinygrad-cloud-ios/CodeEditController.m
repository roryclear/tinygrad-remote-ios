#import "CodeEditController.h"
#import <Metal/Metal.h>
#import "tinygrad.h" // Assuming tinygrad.h contains kernel_dims, kernel_buffer_sizes, and kernel_buffer_ints

static id<MTLDevice> device;
static id<MTLCommandQueue> mtl_queue;

@interface CodeEditController () <UITextFieldDelegate>
@property (nonatomic, strong) NSString *originalTitle;
@property (nonatomic, strong) NSMutableArray<UITextField *> *globalSizeTextFields;
@property (nonatomic, strong) NSMutableArray<UITextField *> *localSizeTextFields;
@property (nonatomic, strong) NSMutableArray<UITextField *> *bufferSizeTextFields;
@property (nonatomic, strong) NSMutableArray<UIButton *> *bufferViewButtons; // New property for buffer view buttons
@property (nonatomic, strong) NSMutableArray<id<MTLBuffer>> *buffers; // New property to store buffers
@property (nonatomic, strong) NSMutableArray<UITextField *> *intArgTextFields;
@property (nonatomic, strong) UILabel *resultLabel;
@property (nonatomic, strong) NSNumber *lastExecutionTime; // in microseconds
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *bufferLabel;
@property (nonatomic, strong) UILabel *intArgLabel;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) NSLayoutConstraint *textViewDynamicHeightConstraint;
- (void)runTapped;
- (void)viewBufferContents:(UIButton *)sender; // New action for viewing buffer contents
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

        CGFloat padding = 10.0;

        self.scrollView = [[UIScrollView alloc] init];
        self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.scrollView];

        self.contentView = [[UIView alloc] init];
        self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.scrollView addSubview:self.contentView];

        self.textView = [[UITextView alloc] init];
        self.textView.text = code;
        self.textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
        self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.textView.layer.borderColor = [UIColor systemGray5Color].CGColor;
        self.textView.layer.borderWidth = 1.0;
        self.textView.layer.cornerRadius = 5.0;
        self.textView.alwaysBounceVertical = YES;
        self.textView.scrollEnabled = NO;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.textView];

        self.globalSizeTextFields = [NSMutableArray array];
        self.localSizeTextFields = [NSMutableArray array];
        self.bufferSizeTextFields = [NSMutableArray array];
        self.bufferViewButtons = [NSMutableArray array]; // Initialize new array
        self.buffers = [NSMutableArray array]; // Initialize buffers array
        self.intArgTextFields = [NSMutableArray array];

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

        self.bufferLabel = [[UILabel alloc] init];
        self.bufferLabel.text = @"Buffer Sizes (bytes):";
        self.bufferLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        self.bufferLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.bufferLabel];

        self.intArgLabel = [[UILabel alloc] init];
        self.intArgLabel.text = @"Integer Arguments:";
        self.intArgLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        self.intArgLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.intArgLabel];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *suffixKeys = @[@"_X", @"_Y", @"_Z"];
        NSArray<NSNumber *> *tinygradDims = nil;

        if (saved_kernels[title]) {
            tinygradDims = kernel_dims[title];
        }

        for (int i = 0; i < 3; i++) {
            UITextField *globalTF = [[UITextField alloc] init];
            globalTF.placeholder = (i == 0) ? @"X" : ((i == 1) ? @"Y" : @"Z");
            globalTF.keyboardType = UIKeyboardTypeNumberPad;
            globalTF.borderStyle = UITextBorderStyleRoundedRect;
            globalTF.delegate = self;
            NSString *globalKey = [NSString stringWithFormat:@"%@_globalSize%@", self.originalTitle, suffixKeys[i]];
            NSString *globalText = [defaults stringForKey:globalKey];
            if (!globalText && tinygradDims && i < tinygradDims.count && [tinygradDims[i] intValue] > 0) {
                globalText = [tinygradDims[i] stringValue];
            }
            globalTF.text = globalText ?: @"1";
            globalTF.tag = 100 + i;
            globalTF.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:globalTF];
            [self.globalSizeTextFields addObject:globalTF];

            UITextField *localTF = [[UITextField alloc] init];
            localTF.placeholder = (i == 0) ? @"X" : ((i == 1) ? @"Y" : @"Z");
            localTF.keyboardType = UIKeyboardTypeNumberPad;
            localTF.borderStyle = UITextBorderStyleRoundedRect;
            localTF.delegate = self;
            NSString *localKey = [NSString stringWithFormat:@"%@_localSize%@", self.originalTitle, suffixKeys[i]];
            NSString *localText = [defaults stringForKey:localKey];
            if (!localText && tinygradDims && i + 3 < tinygradDims.count && [tinygradDims[i + 3] intValue] > 0) {
                localText = [tinygradDims[i + 3] stringValue];
            }
            localTF.text = localText ?: @"1";
            localTF.tag = 200 + i;
            localTF.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:localTF];
            [self.localSizeTextFields addObject:localTF];
        }

        NSUInteger totalBuffers = 0;
        NSArray<NSNumber *> *bufferSizes = kernel_buffer_sizes[title];
        if (bufferSizes && [bufferSizes isKindOfClass:[NSArray class]] && bufferSizes.count > 0) {
            totalBuffers = bufferSizes.count;
        } else {
            NSUInteger deviceCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bdevice\\b" options:0 error:nil] numberOfMatchesInString:code options:0 range:NSMakeRange(0, code.length)];
            NSUInteger constantCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bconstant\\b" options:0 error:nil] numberOfMatchesInString:code options:0 range:NSMakeRange(0, code.length)];
            totalBuffers = deviceCount + constantCount;
        }

        for (NSUInteger i = 0; i < totalBuffers; i++) {
            UITextField *bufferTF = [[UITextField alloc] init];
            bufferTF.placeholder = [NSString stringWithFormat:@"Buffer %lu", (unsigned long)(i + 1)];
            bufferTF.keyboardType = UIKeyboardTypeNumberPad;
            bufferTF.borderStyle = UITextBorderStyleRoundedRect;
            bufferTF.delegate = self;
            NSString *bufferKey = [NSString stringWithFormat:@"%@_bufferSize_%lu", self.originalTitle, (unsigned long)i];
            NSString *bufferText = [defaults stringForKey:bufferKey];
            if (!bufferText && bufferSizes && i < bufferSizes.count && [bufferSizes[i] integerValue] > 0) {
                bufferText = [bufferSizes[i] stringValue];
            }
            bufferTF.text = bufferText ?: @"8";
            bufferTF.tag = 300 + i;
            bufferTF.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:bufferTF];
            [self.bufferSizeTextFields addObject:bufferTF];

            UIButton *viewButton = [UIButton buttonWithType:UIButtonTypeSystem];
            [viewButton setTitle:@"View" forState:UIControlStateNormal];
            viewButton.titleLabel.font = [UIFont systemFontOfSize:12];
            viewButton.tag = 500 + i; // Unique tag
            [viewButton addTarget:self action:@selector(viewBufferContents:) forControlEvents:UIControlEventTouchUpInside];
            viewButton.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:viewButton];
            [self.bufferViewButtons addObject:viewButton];
        }

        [self setupIntArgTextFieldsWithCode:code defaults:defaults];

        self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.runButton setTitle:@"Run Kernel" forState:UIControlStateNormal];
        [self.runButton addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];
        self.runButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        self.runButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.runButton];

        self.resultLabel = [[UILabel alloc] init];
        self.resultLabel.textAlignment = NSTextAlignmentCenter;
        self.resultLabel.font = [UIFont systemFontOfSize:16];
        self.resultLabel.numberOfLines = 0;
        self.resultLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.resultLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

            [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
            [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
            [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor]
        ]];

        CGFloat initialTextViewWidth = CGRectGetWidth(self.view.bounds) - (2 * padding);
        if (initialTextViewWidth <= 0) initialTextViewWidth = 300;
        CGSize initialSize = [self.textView sizeThatFits:CGSizeMake(initialTextViewWidth, CGFLOAT_MAX)];
        self.textViewDynamicHeightConstraint = [self.textView.heightAnchor constraintEqualToConstant:MAX(initialSize.height, 250.0)];
        [self.textViewDynamicHeightConstraint setActive:YES];

        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
        [constraints addObjectsFromArray:@[
            [self.textView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:padding],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
            [self.textView.heightAnchor constraintGreaterThanOrEqualToConstant:250],

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

            [self.bufferLabel.topAnchor constraintEqualToAnchor:self.localSizeTextFields[0].bottomAnchor constant:padding],
            [self.bufferLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        ]];

        NSLayoutAnchor *lastAnchor = self.bufferLabel.bottomAnchor;
        for (NSUInteger i = 0; i < self.bufferSizeTextFields.count; i++) {
            UITextField *bufferTF = self.bufferSizeTextFields[i];
            UIButton *viewButton = self.bufferViewButtons[i];
            [constraints addObjectsFromArray:@[
                [bufferTF.topAnchor constraintEqualToAnchor:lastAnchor constant:padding/2],
                [bufferTF.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
                [bufferTF.widthAnchor constraintEqualToConstant:100],

                [viewButton.centerYAnchor constraintEqualToAnchor:bufferTF.centerYAnchor],
                [viewButton.leadingAnchor constraintEqualToAnchor:bufferTF.trailingAnchor constant:padding/2],
                [viewButton.widthAnchor constraintEqualToConstant:50],
                [viewButton.heightAnchor constraintEqualToConstant:30]
            ]];
            lastAnchor = bufferTF.bottomAnchor;
        }

        [constraints addObject:[self.intArgLabel.topAnchor constraintEqualToAnchor:lastAnchor constant:padding]];
        [constraints addObject:[self.intArgLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]];
        lastAnchor = self.intArgLabel.bottomAnchor;

        for (NSUInteger i = 0; i < self.intArgTextFields.count; i++) {
            UITextField *intArgTF = self.intArgTextFields[i];
            [constraints addObjectsFromArray:@[
                [intArgTF.topAnchor constraintEqualToAnchor:lastAnchor constant:padding/2],
                [intArgTF.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
                [intArgTF.widthAnchor constraintEqualToConstant:100],
            ]];
            lastAnchor = intArgTF.bottomAnchor;
        }

        [constraints addObjectsFromArray:@[
            [self.runButton.topAnchor constraintEqualToAnchor:lastAnchor constant:padding * 2],
            [self.runButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.runButton.heightAnchor constraintEqualToConstant:44],

            [self.resultLabel.topAnchor constraintEqualToAnchor:self.runButton.bottomAnchor constant:padding],
            [self.resultLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [self.resultLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
            [self.resultLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
        ]];

        [NSLayoutConstraint activateConstraints:constraints];

        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                              target:self
                                                                                              action:@selector(saveTapped)];

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
    [self updateTextViewHeight];
}

- (void)textViewDidChangeNotification:(NSNotification *)notification {
    [self updateTextViewHeight];
}

- (void)updateTextViewHeight {
    CGFloat fixedWidth = self.textView.frame.size.width;
    if (fixedWidth <= 0) {
        fixedWidth = CGRectGetWidth(self.view.bounds) - 20.0;
        if (fixedWidth <= 0) fixedWidth = 300;
    }

    CGSize newSize = [self.textView sizeThatFits:CGSizeMake(fixedWidth, CGFLOAT_MAX)];
    CGFloat targetHeight = MAX(newSize.height, 250.0);

    if (fabs(self.textViewDynamicHeightConstraint.constant - targetHeight) > 0.1) {
        self.textViewDynamicHeightConstraint.constant = targetHeight;
        [UIView animateWithDuration:0.1 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
}

#pragma mark - Integer Argument Setup

- (void)setupIntArgTextFieldsWithCode:(NSString *)code defaults:(NSUserDefaults *)defaults {
    for (UITextField *intArgTF in self.intArgTextFields) {
        [intArgTF removeFromSuperview];
    }
    [self.intArgTextFields removeAllObjects];

    NSUInteger totalIntArgs = 0;
    NSArray<NSNumber *> *intArgValues = kernel_buffer_ints[_originalTitle];
    if (intArgValues && [intArgValues isKindOfClass:[NSArray class]] && intArgValues.count > 0) {
        totalIntArgs = intArgValues.count;
    } else {
        NSString *safeKernelName = [[self.originalTitle componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
        NSString *pattern = [NSString stringWithFormat:@"kernel void %@\\([^)]*\\)", [NSRegularExpression escapedPatternForString:safeKernelName]];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:code options:0 range:NSMakeRange(0, code.length)];

        if (match) {
            NSRange signatureRange = [match rangeAtIndex:0];
            NSString *signature = [code substringWithRange:signatureRange];
            
            NSRegularExpression *intArgRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bint\\s+\\w+" options:0 error:nil];
            totalIntArgs = [intArgRegex numberOfMatchesInString:signature options:0 range:NSMakeRange(0, signature.length)];
            
            NSUInteger constantIntCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bconstant\\s+int\\s+\\w+" options:0 error:nil] numberOfMatchesInString:signature options:0 range:NSMakeRange(0, signature.length)];
            totalIntArgs -= constantIntCount;
        }
    }

    for (NSUInteger i = 0; i < totalIntArgs; i++) {
        UITextField *intArgTF = [[UITextField alloc] init];
        intArgTF.placeholder = [NSString stringWithFormat:@"Arg %lu", (unsigned long)(i + 1)];
        intArgTF.keyboardType = UIKeyboardTypeNumberPad;
        intArgTF.borderStyle = UITextBorderStyleRoundedRect;
        intArgTF.delegate = self;
        NSString *intArgKey = [NSString stringWithFormat:@"%@_intArg_%lu", self.originalTitle, (unsigned long)i];
        NSString *intArgText = [defaults stringForKey:intArgKey];
        if (!intArgText && intArgValues && i < intArgValues.count) {
            intArgText = [intArgValues[i] stringValue];
        }
        intArgTF.text = intArgText ?: @"0";
        intArgTF.tag = 400 + i;
        intArgTF.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:intArgTF];
        [self.intArgTextFields addObject:intArgTF];
    }
}

#pragma mark - Actions

- (void)saveTapped {
    [self.view endEditing:YES];

    if (self.onSave) {
        self.onSave(self.textView.text);
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *suffixKeys = @[@"_X", @"_Y", @"_Z"];

    for (int i = 0; i < 3; i++) {
        NSString *globalKey = [NSString stringWithFormat:@"%@_globalSize%@", self.originalTitle, suffixKeys[i]];
        NSString *localKey = [NSString stringWithFormat:@"%@_localSize%@", self.originalTitle, suffixKeys[i]];
        [defaults setObject:self.globalSizeTextFields[i].text forKey:globalKey];
        [defaults setObject:self.localSizeTextFields[i].text forKey:localKey];
    }

    for (NSUInteger i = 0; i < self.bufferSizeTextFields.count; i++) {
        NSString *bufferKey = [NSString stringWithFormat:@"%@_bufferSize_%lu", self.originalTitle, (unsigned long)i];
        [defaults setObject:self.bufferSizeTextFields[i].text forKey:bufferKey];
    }

    for (NSUInteger i = 0; i < self.intArgTextFields.count; i++) {
        NSString *intArgKey = [NSString stringWithFormat:@"%@_intArg_%lu", self.originalTitle, (unsigned long)i];
        [defaults setObject:self.intArgTextFields[i].text forKey:intArgKey];
    }

    [defaults synchronize];
}

- (void)viewBufferContents:(UIButton *)sender {
    NSUInteger index = sender.tag - 500; // Corresponds to buffer index
    if (index >= self.buffers.count || !self.buffers[index]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:@"Buffer not available. Run the kernel first."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    id<MTLBuffer> buffer = self.buffers[index];
    NSUInteger length = buffer.length;
    unsigned char *contents = (unsigned char *)buffer.contents;
    NSMutableString *hexString = [NSMutableString stringWithCapacity:length * 2];
    for (NSUInteger i = 0; i < length; i++) {
        [hexString appendFormat:@"%02x", contents[i]];
        if (i < length - 1) [hexString appendString:@" "];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Buffer %lu Contents", (unsigned long)(index + 1)]
                                                                   message:hexString.length > 0 ? hexString : @"Empty buffer"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runTapped {
    [self.view endEditing:YES];

    NSString *kernelCode = self.textView.text;

    // Save current buffer size text field values
    NSMutableArray<NSString *> *currentBufferSizes = [NSMutableArray array];
    for (UITextField *textField in self.bufferSizeTextFields) {
        [currentBufferSizes addObject:textField.text ?: @""];
    }

    // Determine total buffers
    NSUInteger totalBuffers = 0;
    NSArray<NSNumber *> *bufferSizes = kernel_buffer_sizes[_originalTitle];
    if (bufferSizes && [bufferSizes isKindOfClass:[NSArray class]] && bufferSizes.count > 0) {
        totalBuffers = bufferSizes.count;
    } else {
        NSUInteger deviceCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bdevice\\b" options:0 error:nil] numberOfMatchesInString:kernelCode options:0 range:NSMakeRange(0, kernelCode.length)];
        NSUInteger constantCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bconstant\\b" options:0 error:nil] numberOfMatchesInString:kernelCode options:0 range:NSMakeRange(0, kernelCode.length)];
        totalBuffers = deviceCount + constantCount;
    }

    // Determine total integer arguments
    NSUInteger totalIntArgs = 0;
    NSArray<NSNumber *> *intArgValues = kernel_buffer_ints[_originalTitle];
    if (intArgValues && [intArgValues isKindOfClass:[NSArray class]] && intArgValues.count > 0) {
        totalIntArgs = intArgValues.count;
    } else {
        NSString *safeKernelName = [[self.originalTitle componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
        NSString *pattern = [NSString stringWithFormat:@"kernel void %@\\([^)]*\\)", [NSRegularExpression escapedPatternForString:safeKernelName]];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:kernelCode options:0 range:NSMakeRange(0, kernelCode.length)];

        if (match) {
            NSRange signatureRange = [match rangeAtIndex:0];
            NSString *signature = [kernelCode substringWithRange:signatureRange];
            NSRegularExpression *intArgRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bint\\s+\\w+" options:0 error:nil];
            totalIntArgs = [intArgRegex numberOfMatchesInString:signature options:0 range:NSMakeRange(0, signature.length)];
            NSUInteger constantIntCount = [[NSRegularExpression regularExpressionWithPattern:@"\\bconstant\\s+int\\s+\\w+" options:0 error:nil] numberOfMatchesInString:signature options:0 range:NSMakeRange(0, signature.length)];
            totalIntArgs -= constantIntCount;
        }
    }

    // Remove existing buffer and int arg text fields, and their buttons
    for (UITextField *textField in self.bufferSizeTextFields) { [textField removeFromSuperview]; }
    [self.bufferSizeTextFields removeAllObjects];
    for (UIButton *button in self.bufferViewButtons) { [button removeFromSuperview]; }
    [self.bufferViewButtons removeAllObjects];
    [self.buffers removeAllObjects];
    for (UITextField *textField in self.intArgTextFields) { [textField removeFromSuperview]; }
    [self.intArgTextFields removeAllObjects];

    // Deactivate old constraints
    for (NSLayoutConstraint *constraint in self.contentView.constraints) {
        BOOL isDynamicConstraint = NO;
        if (constraint.firstItem == self.bufferLabel || constraint.secondItem == self.bufferLabel) isDynamicConstraint = YES;
        for (UITextField *tf in self.bufferSizeTextFields) {
            if (constraint.firstItem == tf || constraint.secondItem == tf) isDynamicConstraint = YES;
        }
        for (UIButton *btn in self.bufferViewButtons) {
            if (constraint.firstItem == btn || constraint.secondItem == btn) isDynamicConstraint = YES;
        }
        if (constraint.firstItem == self.intArgLabel || constraint.secondItem == self.intArgLabel) isDynamicConstraint = YES;
        for (UITextField *tf in self.intArgTextFields) {
            if (constraint.firstItem == tf || constraint.secondItem == tf) isDynamicConstraint = YES;
        }
        if (constraint.firstItem == self.runButton || constraint.secondItem == self.runButton) isDynamicConstraint = YES;
        if (constraint.firstItem == self.resultLabel || constraint.secondItem == self.resultLabel) isDynamicConstraint = YES;
        
        if (isDynamicConstraint) {
            [constraint setActive:NO];
        }
    }

    // Recreate buffer text fields and view buttons
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat padding = 10.0;

    for (NSUInteger i = 0; i < totalBuffers; i++) {
        UITextField *bufferTF = [[UITextField alloc] init];
        bufferTF.placeholder = [NSString stringWithFormat:@"Buffer %lu", (unsigned long)(i + 1)];
        bufferTF.keyboardType = UIKeyboardTypeNumberPad;
        bufferTF.borderStyle = UITextBorderStyleRoundedRect;
        bufferTF.delegate = self;
        NSString *bufferKey = [NSString stringWithFormat:@"%@_bufferSize_%lu", self.originalTitle, (unsigned long)i];
        NSString *bufferText = (i < currentBufferSizes.count && currentBufferSizes[i].length > 0) ? currentBufferSizes[i] : [defaults stringForKey:bufferKey];
        if (!bufferText && bufferSizes && i < bufferSizes.count && [bufferSizes[i] integerValue] > 0) {
            bufferText = [bufferSizes[i] stringValue];
        }
        bufferTF.text = bufferText ?: @"8";
        bufferTF.tag = 300 + i;
        bufferTF.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:bufferTF];
        [self.bufferSizeTextFields addObject:bufferTF];

        UIButton *viewButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [viewButton setTitle:@"View" forState:UIControlStateNormal];
        viewButton.titleLabel.font = [UIFont systemFontOfSize:12];
        viewButton.tag = 500 + i;
        [viewButton addTarget:self action:@selector(viewBufferContents:) forControlEvents:UIControlEventTouchUpInside];
        viewButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:viewButton];
        [self.bufferViewButtons addObject:viewButton];
    }

    // Recreate integer argument text fields
    for (NSUInteger i = 0; i < totalIntArgs; i++) {
        UITextField *intArgTF = [[UITextField alloc] init];
        intArgTF.placeholder = [NSString stringWithFormat:@"Arg %lu", (unsigned long)(i + 1)];
        intArgTF.keyboardType = UIKeyboardTypeNumberPad;
        intArgTF.borderStyle = UITextBorderStyleRoundedRect;
        intArgTF.delegate = self;
        NSString *intArgKey = [NSString stringWithFormat:@"%@_intArg_%lu", self.originalTitle, (unsigned long)i];
        NSString *intArgText = [defaults stringForKey:intArgKey];
        if (!intArgText && intArgValues && i < intArgValues.count) {
            intArgText = [intArgValues[i] stringValue];
        }
        intArgTF.text = intArgText ?: @"0";
        intArgTF.tag = 400 + i;
        intArgTF.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:intArgTF];
        [self.intArgTextFields addObject:intArgTF];
    }

    // Re-add and activate constraints
    NSMutableArray<NSLayoutConstraint *> *newConstraints = [NSMutableArray array];

    [newConstraints addObject:[self.bufferLabel.topAnchor constraintEqualToAnchor:self.localSizeTextFields[0].bottomAnchor constant:padding]];
    [newConstraints addObject:[self.bufferLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]];

    NSLayoutAnchor *lastAnchor = self.bufferLabel.bottomAnchor;
    for (NSUInteger i = 0; i < self.bufferSizeTextFields.count; i++) {
        UITextField *bufferTF = self.bufferSizeTextFields[i];
        UIButton *viewButton = self.bufferViewButtons[i];
        [newConstraints addObjectsFromArray:@[
            [bufferTF.topAnchor constraintEqualToAnchor:lastAnchor constant:padding/2],
            [bufferTF.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [bufferTF.widthAnchor constraintEqualToConstant:100],

            [viewButton.centerYAnchor constraintEqualToAnchor:bufferTF.centerYAnchor],
            [viewButton.leadingAnchor constraintEqualToAnchor:bufferTF.trailingAnchor constant:padding/2],
            [viewButton.widthAnchor constraintEqualToConstant:50],
            [viewButton.heightAnchor constraintEqualToConstant:30]
        ]];
        lastAnchor = bufferTF.bottomAnchor;
    }

    [newConstraints addObject:[self.intArgLabel.topAnchor constraintEqualToAnchor:lastAnchor constant:padding]];
    [newConstraints addObject:[self.intArgLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]];
    lastAnchor = self.intArgLabel.bottomAnchor;

    for (NSUInteger i = 0; i < self.intArgTextFields.count; i++) {
        UITextField *intArgTF = self.intArgTextFields[i];
        [newConstraints addObjectsFromArray:@[
            [intArgTF.topAnchor constraintEqualToAnchor:lastAnchor constant:padding/2],
            [intArgTF.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
            [intArgTF.widthAnchor constraintEqualToConstant:100],
        ]];
        lastAnchor = intArgTF.bottomAnchor;
    }

    [newConstraints addObjectsFromArray:@[
        [self.runButton.topAnchor constraintEqualToAnchor:lastAnchor constant:padding * 2],
        [self.runButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.runButton.heightAnchor constraintEqualToConstant:44],

        [self.resultLabel.topAnchor constraintEqualToAnchor:self.runButton.bottomAnchor constant:padding],
        [self.resultLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.resultLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.resultLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
    ]];

    [NSLayoutConstraint activateConstraints:newConstraints];

    [self.view layoutIfNeeded];

    // Metal Kernel Execution
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

    id<MTLCommandBuffer> commandBuffer = [mtl_queue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    [computeEncoder setComputePipelineState:pipelineState];

    [self.buffers removeAllObjects]; // Clear previous buffers
    for (NSUInteger i = 0; i < totalBuffers; i++) {
        NSInteger byteSize = [self.bufferSizeTextFields[i].text integerValue];
        if (byteSize <= 0) {
            byteSize = 8;
            self.bufferSizeTextFields[i].text = @"8";
        }

        id<MTLBuffer> buffer = [device newBufferWithLength:byteSize options:MTLResourceStorageModeShared];
        if (!buffer) {
            self.resultLabel.textColor = [UIColor systemRedColor];
            self.resultLabel.text = [NSString stringWithFormat:@"Failed to create buffer of size %ld for index %lu.", (long)byteSize, (unsigned long)i];
            return;
        }

        memset(buffer.contents, 0, byteSize);
        [computeEncoder setBuffer:buffer offset:0 atIndex:i];
        [self.buffers addObject:buffer]; // Store buffer
    }

    for (NSUInteger i = 0; i < self.intArgTextFields.count; i++) {
        NSInteger value = [self.intArgTextFields[i].text integerValue];
        [computeEncoder setBytes:&value length:sizeof(NSInteger) atIndex:i + totalBuffers];
    }

    @try {
        [computeEncoder dispatchThreadgroups:globalSize threadsPerThreadgroup:localSize];
        [computeEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    } @catch (NSException *exception) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.resultLabel.textColor = [UIColor systemRedColor];
            self.resultLabel.text = [NSString stringWithFormat:@"Dispatch failed: %@", exception.reason];
        });
        return;
    }
    
    NSArray<NSString *> *suffixKeys = @[@"_X", @"_Y", @"_Z"];

    for (int i = 0; i < 3; i++) {
        NSString *globalKey = [NSString stringWithFormat:@"%@_globalSize%@", self.originalTitle, suffixKeys[i]];
        NSString *localKey = [NSString stringWithFormat:@"%@_localSize%@", self.originalTitle, suffixKeys[i]];
        [[NSUserDefaults standardUserDefaults] setObject:self.globalSizeTextFields[i].text forKey:globalKey];
        [[NSUserDefaults standardUserDefaults] setObject:self.localSizeTextFields[i].text forKey:localKey];
    }

    for (NSUInteger i = 0; i < self.bufferSizeTextFields.count; i++) {
        NSString *bufferKey = [NSString stringWithFormat:@"%@_bufferSize_%lu", self.originalTitle, (unsigned long)i];
        [[NSUserDefaults standardUserDefaults] setObject:self.bufferSizeTextFields[i].text forKey:bufferKey];
    }

    for (NSUInteger i = 0; i < self.intArgTextFields.count; i++) {
        NSString *intArgKey = [NSString stringWithFormat:@"%@_intArg_%lu", self.originalTitle, (unsigned long)i];
        [[NSUserDefaults standardUserDefaults] setObject:self.intArgTextFields[i].text forKey:intArgKey];
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

    UIView *activeInput = nil;
    if ([self.textView isFirstResponder]) {
        activeInput = self.textView;
    } else {
        for (UITextField *textField in self.globalSizeTextFields) {
            if ([textField isFirstResponder]) {
                activeInput = textField;
                break;
            }
        }
        if (!activeInput) {
            for (UITextField *textField in self.localSizeTextFields) {
                if ([textField isFirstResponder]) {
                    activeInput = textField;
                    break;
                }
            }
        }
        if (!activeInput) {
            for (UITextField *textField in self.bufferSizeTextFields) {
                if ([textField isFirstResponder]) {
                    activeInput = textField;
                    break;
                }
            }
        }
        if (!activeInput) {
            for (UITextField *textField in self.intArgTextFields) {
                if ([textField isFirstResponder]) {
                    activeInput = textField;
                    break;
                }
            }
        }
    }

    if (activeInput) {
        CGRect rect = [self.scrollView convertRect:activeInput.bounds fromView:activeInput];
        rect.origin.y -= self.scrollView.contentOffset.y;
        rect.size.height += 10;

        CGRect visibleRect = self.scrollView.bounds;
        visibleRect.size.height -= keyboardFrame.size.height;

        if (!CGRectContainsRect(visibleRect, rect)) {
            [self.scrollView scrollRectToVisible:rect animated:YES];
        }
    }

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
    for (UITextField *textField in self.bufferSizeTextFields) {
        textField.inputAccessoryView = toolbar;
    }
    for (UITextField *textField in self.intArgTextFields) {
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
    [self.view endEditing:YES];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

- (void)updateRunResult:(NSString *)result isError:(BOOL)isError {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.resultLabel.textColor = isError ? [UIColor systemRedColor] : [UIColor systemGreenColor];
        self.resultLabel.text = result;
    });
}

@end
