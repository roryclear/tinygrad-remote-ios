#import <UIKit/UIKit.h>
#import "tinygrad.h"

@interface ViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *remoteSwitch;
@property (nonatomic, strong) UISwitch *kernelsSwitch;
@property (nonatomic, strong) UILabel *ipLabel;
@property (nonatomic, strong) NSTimer *ipTimer;
@property (nonatomic, assign) BOOL isRemoteEnabled;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *kernelTimes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *myKernels;

@end
