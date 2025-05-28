#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface tinygrad : NSObject
+ (NSString *)getIP;
+ (void)start;
+ (void)toggleSaveKernels;
+ (BOOL)isSaveKernelsEnabled;
+ (NSArray<NSString *> *)getKernelKeys;
@end

NS_ASSUME_NONNULL_END
