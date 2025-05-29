#import <UIKit/UIKit.h>
#import "tinygrad.h"
#import "CodeViewController.h"
#import "CodeEditController.h"

@interface ViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableDictionary *myKernels;
@property (nonatomic, strong) NSMutableArray<NSString *> *myKernelNames;
@property (nonatomic, strong) NSMutableDictionary *kernelTimes;
@property (nonatomic, strong) UISwitch *remoteSwitch;
@property (nonatomic, strong) UISwitch *kernelsSwitch;
@property (nonatomic, strong) UILabel *ipLabel;
@property (nonatomic, assign) BOOL isRemoteEnabled;
@property (nonatomic, strong) NSTimer *ipTimer;

- (void)addCustomKernel;
- (void)showKernelEditor:(NSString *)kernelName;
- (void)remoteToggleChanged:(UISwitch *)sender;
- (void)kernelsToggleChanged:(UISwitch *)sender;
- (void)updateIPLabel;
- (void)saveMyKernels;
- (void)loadMyKernels;

@end
