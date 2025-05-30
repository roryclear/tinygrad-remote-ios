#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface tinygrad : NSObject
+ (NSString *)getIP;
+ (void)start;
+ (void)toggleSaveKernels;
+ (BOOL)isSaveKernelsEnabled;
+ (NSArray<NSString *> *)getKernelKeys;
+ (NSString *)getKernelCodeForKey:(NSString *)key; //todo do directly?
+ (NSDictionary<NSString *, NSNumber *> *)getKernelTimes;
+ (NSArray *)getDimsForKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
