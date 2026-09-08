#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class tinygrad;

extern BOOL save_kernels;
extern NSMutableArray<NSString *> *kernel_keys;
extern NSMutableDictionary<NSString *, id> *saved_kernels;
extern NSMutableDictionary<NSString *, id> *kernel_dims;
extern NSMutableDictionary<NSString *, id> *kernel_times;
extern NSMutableDictionary<NSString *, NSMutableArray *> *kernel_buffer_sizes;
extern NSMutableDictionary<NSString *, NSMutableArray *> *kernel_buffer_ints;
extern tinygrad *sharedInstance;
extern CFSocketRef _socket;

void setSharedInstanceNil(void);
BOOL hasSharedInstance(void);
void createSharedInstance(void);
void invalidateSocket(void);
void setSocketNull(void);
void toggleSaveKernelsValue(void);

@interface tinygrad : NSObject
+ (NSString *)getIP;
+ (void)stop;
+ (void)toggleSaveKernels;
NSArray* get_kernel_keys(void);
NSDictionary* get_kernel_times(void);
NSDictionary* get_saved_kernels(void);
BOOL is_save_kernels_enabled(void);
@end

NS_ASSUME_NONNULL_END
