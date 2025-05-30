#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern BOOL save_kernels;
extern NSMutableArray<NSString *> *kernel_keys;
extern NSMutableDictionary<NSString *, id> *saved_kernels;
extern NSMutableDictionary<NSString *, id> *kernel_dims;
extern NSMutableDictionary<NSString *, id> *kernel_times;
extern NSMutableDictionary<NSString *, NSMutableArray *> *kernel_buffer_sizes;
extern NSMutableDictionary<NSString *, NSMutableArray *> *kernel_buffer_ints;

@interface tinygrad : NSObject
+ (NSString *)getIP;
+ (void)start;
+ (void)toggleSaveKernels;
@end

NS_ASSUME_NONNULL_END
