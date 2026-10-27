// Exercise the exact shipped receiver, without invoking its main or any scanner API.
#define main unused_feeding_worker_main
#include "../Helpers/EpsonFeedingWorker.m"
#undef main
#import <objc/message.h>
@interface AreaFixture:NSObject
@property CGRect area;
@property BOOL reject;
@property NSUInteger dpi;
@end
@implementation AreaFixture
- (CGSize)maxScanSize{return CGSizeMake(8.5,11.7);}
- (NSUInteger)xResolution{return self.dpi;}
- (NSUInteger)yResolution{return self.dpi;}
- (void)setScanArea:(CGRect)value{self.area=CGRectMake(value.origin.x*300,value.origin.y*300,value.size.width*300,value.size.height*300);}
- (CGRect)scanAreaInPixel{return self.area;}
- (void)setScanAreaInPixel:(CGRect)value{if(!self.reject)self.area=value;}
@end

int main(void) { @autoreleasepool {
    AreaFixture *area=[AreaFixture new];
    area.dpi=300;
    NSDictionary *settings=@{@"profileWidthMM":@76,@"profileHeightMM":@102,@"crop":@NO};
    if(!configureFixedArea((id<FeedingScanner>)area,settings)||!CGRectEqualToRect(area.area,CGRectMake(826,0,898,1205))){fprintf(stderr,"Fixed area must be centered in actual pixel bounds\n");return 2;}
    area.reject=YES;
    if(configureFixedArea((id<FeedingScanner>)area,settings)){fprintf(stderr,"Rejected scan area was accepted\n");return 3;}
    if(configureFixedArea((id<FeedingScanner>)area,@{@"profileWidthMM":@76,@"crop":@NO})||configureFixedArea((id<FeedingScanner>)area,@{@"profileWidthMM":@76,@"profileHeightMM":@102,@"crop":@YES})){fprintf(stderr,"Invalid profile area was accepted\n");return 4;}
    area.reject=NO;area.dpi=150;
    if(configureFixedArea((id<FeedingScanner>)area,settings)){fprintf(stderr,"Unconfirmed resolution was accepted\n");return 5;}
    FeedingReceiver *receiver = [FeedingReceiver new];
    @try {
        // Scanner.framework calls this directly; respondsToSelector is not consulted.
        ((void(*)(id,SEL,id,id))objc_msgSend)(receiver,NSSelectorFromString(@"scanner:willScanToScannedImageHandle:"),nil,nil);
        for (NSString *name in @[@"scannerWillBeginContinuousScanning:", @"scannerDidEndContinuousScanning:",
                                 @"scannerWillCancelScanning:", @"scannerDidCancelScanning:"]) {
            ((void(*)(id,SEL,id))objc_msgSend)(receiver,NSSelectorFromString(name),nil);
        }
        ((void(*)(id,SEL,id,long long))objc_msgSend)(receiver,NSSelectorFromString(@"scanner:didPressButton:"),nil,1);
    } @catch (NSException *exception) {
        fprintf(stderr,"Feeding delegate contract failed: %s\n",exception.reason.UTF8String);
        return 1;
    }
    return 0;
} }
