#import <UIKit/UIKit.h>

@interface CodeEditController : UIViewController

- (instancetype)initWithCode:(NSString *)code title:(NSString *)title;

@property (nonatomic, copy) void (^onSave)(NSString *code);

@end
