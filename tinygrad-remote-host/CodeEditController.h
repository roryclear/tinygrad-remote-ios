#import <UIKit/UIKit.h>

@class CodeEditController;

@protocol CodeEditControllerDelegate <NSObject>

// Delegate method to be called when the "Run" button is tapped.
// For now, this method will do nothing, as per the user's request.
- (void)codeEditController:(CodeEditController *)controller
           didRequestRunCode:(NSString *)code
                  globalSizes:(NSArray<NSNumber *> *)globalSizes
                   localSizes:(NSArray<NSNumber *> *)localSizes;

@end

@interface CodeEditController : UIViewController

@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) void (^onSave)(NSString *code);
@property (nonatomic, weak) id<CodeEditControllerDelegate> delegate;
@property (nonatomic, strong) NSMutableArray<id<MTLBuffer>> *lastRunBuffers;

- (instancetype)initWithCode:(NSString *)code title:(NSString *)title;

@end
