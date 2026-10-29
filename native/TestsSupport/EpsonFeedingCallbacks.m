// Exercise the exact shipped receiver, without invoking its main or any scanner API.
#define main unused_feeding_worker_main
#include "../Helpers/EpsonFeedingWorker.m"
#undef main
#import <objc/message.h>
@interface AreaFixture:NSObject
@property CGRect area;
@property BOOL reject;
@property NSUInteger dpi;
@property unsigned char laminate;
@property float margin;
@property BOOL overscan;
@property BOOL rejectMedia;
@end
@implementation AreaFixture
- (CGSize)maxScanSize{return CGSizeMake(8.5,11.7);}
- (NSUInteger)xResolution{return self.dpi;}
- (NSUInteger)yResolution{return self.dpi;}
- (void)setScanArea:(CGRect)value{self.area=CGRectMake(value.origin.x*300,value.origin.y*300,value.size.width*300,value.size.height*300);}
- (CGRect)scanAreaInPixel{return self.area;}
- (void)setScanAreaInPixel:(CGRect)value{if(!self.reject)self.area=value;}
- (NSIndexSet*)supportedLaminatedPaperModes{return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,2)];}
- (NSArray*)supportedCroppingSizes{return @[@0.2f];}
- (BOOL)autoCroppingEnabled{return YES;}
- (void)setLaminatedPaperMode:(unsigned char)value{if(!self.rejectMedia)self.laminate=value;}
- (unsigned char)laminatedPaperMode{return self.laminate;}
- (void)setCroppingSize:(float)value{if(!self.rejectMedia)self.margin=value;}
- (float)croppingSize{return self.margin;}
- (void)setOverScanEnabled:(BOOL)value{self.overscan=value;}
- (BOOL)overScanEnabled{return self.overscan;}
@end

// Epson6.7.84 may open in mode0. AF start then reports success without
// sending its hardware command; the caller must first enter control mode1.
@interface ControlFixture:NSObject
@property unsigned char controlMode;
@property int controlError;
@property BOOL rejectControl;
@property int captureError;
@property BOOL captureRequested;
@property BOOL afCalled;
@end
@implementation ControlFixture
- (unsigned char)mode{return self.controlMode;}
- (int)setMode:(unsigned char)value{if(!self.controlError&&!self.rejectControl)self.controlMode=value;return self.controlError;}
- (int)startScanningInAFM{self.afCalled=YES;if(self.controlMode==1)self.captureRequested=YES;return self.captureError;}
@end

static NSInteger callbackError(FeedingReceiver *receiver,NSString *selector,NSError *error){
 int descriptors[2];if(pipe(descriptors)!=0)return NSIntegerMin;
 fflush(stdout);int saved=dup(STDOUT_FILENO);
 dup2(descriptors[1],STDOUT_FILENO);close(descriptors[1]);
 @try {((void(*)(id,SEL,id,id))objc_msgSend)(receiver,NSSelectorFromString(selector),nil,error);}
 @finally {fflush(stdout);dup2(saved,STDOUT_FILENO);close(saved);}
 char bytes[4096];ssize_t count=read(descriptors[0],bytes,sizeof(bytes));close(descriptors[0]);
 if(count<=0)return NSIntegerMin;
 NSDictionary *event=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:(NSUInteger)count] options:0 error:nil];
 return [event[@"value"] longLongValue];
}

int main(void) { @autoreleasepool {
    ControlFixture *control=[ControlFixture new];
    if(startFeeding((id<FeedingScanner>)control)!=0||!control.captureRequested){fprintf(stderr,"AF success must actually request capture after acquiring scanner control\n");return 12;}
    control=[ControlFixture new];control.controlError=394;
    if(startFeeding((id<FeedingScanner>)control)!=394||control.afCalled){fprintf(stderr,"Failed control acquisition must stop before AF and preserve its error\n");return 13;}
    control=[ControlFixture new];control.rejectControl=YES;
    if(startFeeding((id<FeedingScanner>)control)==0||control.afCalled){fprintf(stderr,"Unconfirmed control mode must never start AF\n");return 14;}
    control=[ControlFixture new];control.controlMode=1;control.captureError=303;
    if(startFeeding((id<FeedingScanner>)control)!=303||!control.captureRequested){fprintf(stderr,"An existing control session must preserve AF start failures\n");return 15;}
    AreaFixture *area=[AreaFixture new];
    area.dpi=300;
    NSDictionary *settings=@{@"profileWidthMM":@76,@"profileHeightMM":@102,@"crop":@NO};
    if(!configureFixedArea((id<FeedingScanner>)area,settings)||!CGRectEqualToRect(area.area,CGRectMake(826,0,898,1205))){fprintf(stderr,"Fixed area must be centered in actual pixel bounds\n");return 2;}
    area.reject=YES;
    if(configureFixedArea((id<FeedingScanner>)area,settings)){fprintf(stderr,"Rejected scan area was accepted\n");return 3;}
    if(configureFixedArea((id<FeedingScanner>)area,@{@"profileWidthMM":@76,@"crop":@NO})||configureFixedArea((id<FeedingScanner>)area,@{@"profileWidthMM":@76,@"profileHeightMM":@102,@"crop":@YES})){fprintf(stderr,"Invalid profile area was accepted\n");return 4;}
    area.reject=NO;area.dpi=150;
    if(configureFixedArea((id<FeedingScanner>)area,settings)){fprintf(stderr,"Unconfirmed resolution was accepted\n");return 5;}
    area.dpi=300;area.overscan=YES;
    NSDictionary *holder=@{@"transparentOriginal":@YES,@"crop":@YES,@"profileWidthMM":@108,@"profileHeightMM":@83};
    if(!configureFixedArea((id<FeedingScanner>)area,holder)||area.laminate!=1||fabs(area.margin-0.2)>0.00001||area.overscan||!CGRectEqualToRect(area.area,CGRectMake(0,0,2550,3510))){fprintf(stderr,"Transparent capture must acquire full sensor area with laminated mode, positive margin and overscan off\n");return 6;}
    area.rejectMedia=YES;area.laminate=0;area.margin=0;
    if(configureFixedArea((id<FeedingScanner>)area,holder)){fprintf(stderr,"Rejected transparent-media settings were accepted\n");return 7;}
    FeedingReceiver *receiver = [FeedingReceiver new];
    @try {
        // The actual Epson6.7.84 notifier constructs an NSError and passes
        // that object in x3. An integer declaration instead reads its address.
        NSError *driverError=[NSError errorWithDomain:@"com.epson.Scanner" code:394 userInfo:nil];
        for(NSString *name in @[@"scanner:didCompleteScanningWithError:",@"scanner:didInterruptScanningWithError:",@"scanner:didEncounterDeviceCommunicationError:"]){
            FeedingReceiver *failure=[FeedingReceiver new];
            if(callbackError(failure,name,driverError)!=394||!failure.failed){fprintf(stderr,"Epson NSError callback lost its actual code: %s\n",name.UTF8String);return 9;}
            if(!exact(FeedingReceiver.class,name,"v32@0:8@16@24")){fprintf(stderr,"Epson error callback ABI must take an object\n");return 10;}
        }
        for(NSString *name in @[@"scanner:didCompleteScanningWithError:",@"scanner:didEncounterDeviceCommunicationError:"]){
            FeedingReceiver *success=[FeedingReceiver new];
            if(callbackError(success,name,nil)!=NSIntegerMin||success.failed){fprintf(stderr,"Nil NSError must remain a successful notification\n");return 11;}
        }
        // Scanner.framework calls this directly; respondsToSelector is not consulted.
        ((void(*)(id,SEL,id,id))objc_msgSend)(receiver,NSSelectorFromString(@"scanner:willScanToScannedImageHandle:"),nil,nil);
        for (NSString *name in @[@"scannerWillBeginContinuousScanning:", @"scannerDidEndContinuousScanning:",
                                 @"scannerWillCancelScanning:", @"scannerDidCancelScanning:"]) {
            ((void(*)(id,SEL,id))objc_msgSend)(receiver,NSSelectorFromString(name),nil);
        }
        ((void(*)(id,SEL,id,long long))objc_msgSend)(receiver,NSSelectorFromString(@"scanner:didPressButton:"),nil,1);
        receiver.stopRequested=NO;
        [receiver setValue:@YES forKey:@"singleShot"];
        ((void(*)(id,SEL,id))objc_msgSend)(receiver,NSSelectorFromString(@"scannerDidEndContinuousScanning:"),nil);
        if(!receiver.stopRequested){fprintf(stderr,"A single-card capture must finish after its first complete physical batch\n");return 8;}
    } @catch (NSException *exception) {
        fprintf(stderr,"Feeding delegate contract failed: %s\n",exception.reason.UTF8String);
        return 1;
    }
    return 0;
} }
