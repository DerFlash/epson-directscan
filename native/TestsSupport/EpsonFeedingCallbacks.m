// Exercise the exact shipped receiver, without invoking its main or any scanner API.
#define main unused_feeding_worker_main
#include "../Helpers/EpsonFeedingWorker.m"
#undef main
#import <objc/message.h>

int main(void) { @autoreleasepool {
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
