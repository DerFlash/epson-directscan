// Native automatic feeding with the installed Epson driver; no vendor binaries are bundled.
#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import <objc/runtime.h>
#import "../Sources/EpsonImageProcessing/include/EpsonImageProcessing.h"
#include <signal.h>
#include <unistd.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
@protocol FeedingUSB <NSObject>
- (id)initWithLocationID:(unsigned int)location productIDForValidation:(unsigned short)product;
@end
@protocol FeedingScanner <NSObject>
- (id)initWithInterface:(id)interface; - (int)open; - (int)close; - (BOOL)isOpened;
- (void)setDelegate:(id)value; - (void)setWorkFolder:(NSString*)value;
- (BOOL)autoFeedingModeSupported; - (BOOL)duplexSupported;
- (BOOL)autoCroppingSupported; - (BOOL)skewCorrectionSupported;
- (NSIndexSet*)supportedColorFormats; - (NSIndexSet*)supportedImageFormats;
- (void)setXResolution:(NSUInteger)value; - (void)setYResolution:(NSUInteger)value;
- (void)setColorFormat:(int)value; - (int)colorFormat; - (void)setImageFormat:(int)value; - (int)imageFormat;
- (void)setDuplexEnabled:(BOOL)value; - (BOOL)duplexEnabled;
- (void)setAutoCroppingEnabled:(BOOL)value; - (BOOL)autoCroppingEnabled;
- (void)setSkewCorrectionEnabled:(BOOL)value; - (BOOL)skewCorrectionEnabled;
- (void)setScanAreaInPixel:(CGRect)value; - (void)setAutoFeedingModeTimeout:(NSUInteger)value;
- (int)startScanningInAFM; - (int)stopScanningInAutoFeedingMode;
- (BOOL)isScanning; - (unsigned char)jobMode;
@end
@protocol FeedingImage <NSObject>
- (void)seekToOffset:(NSUInteger)offset; - (NSData*)readDataToEnd;
- (NSUInteger)bitsPerSample; - (NSUInteger)samplesPerPixel;
- (int)surfaceType; - (NSUInteger)paperSerialNumber; - (BOOL)closed; - (int)imageFormat;
@end
static volatile sig_atomic_t aborted=0, finishing=0;
static void signalHandler(int number){if(number==SIGUSR1)finishing=1;else aborted=1;}
static void emitObject(NSDictionary *event){
 NSData *d=[NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
 if(d){flockfile(stdout);fwrite(d.bytes,1,d.length,stdout);putchar('\n');fflush(stdout);funlockfile(stdout);}
}
static void emit(NSString *name,NSInteger value){emitObject(@{@"event":name,@"value":@(value)});}
static BOOL methodHasReturn(Class cls, SEL selector, const char *type, unsigned count) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char *actual = method_copyReturnType(method);
    BOOL match = actual && strcmp(actual, type) == 0;
    free(actual); return match;
}
static BOOL argumentHasType(Class cls, SEL selector, unsigned index, const char *type) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    char *actual = method_copyArgumentType(method, index);
    BOOL match = actual && strcmp(actual, type) == 0;
    free(actual); return match;
}
static int numberProperty(io_registry_entry_t entry, CFStringRef key) {
    CFTypeRef property = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0);
    int value = -1;
    if (property && CFGetTypeID(property) == CFNumberGetTypeID()) CFNumberGetValue(property, kCFNumberIntType, &value);
    if (property) CFRelease(property);
    return value;
}
static BOOL findLocation(unsigned int *location) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) != KERN_SUCCESS) return NO;
    unsigned matches = 0; io_service_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        if (numberProperty(entry, CFSTR("idVendor")) == 1208 && numberProperty(entry, CFSTR("idProduct")) == 400) {
            *location = (unsigned int)numberProperty(entry, CFSTR("locationID")); matches++;
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator); return matches == 1;
}
static int claimLease(NSString *root) {
    int fd = open([[root stringByAppendingPathComponent:@"scanner.lock"] fileSystemRepresentation],
                  O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return -1;
    struct stat info;
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != getuid() || flock(fd, LOCK_EX | LOCK_NB) != 0) {
        close(fd); return -1;
    }
    fchmod(fd, 0600); return fd;
}

static BOOL exact(Class cls,NSString *name,const char *encoding){Method m=class_getInstanceMethod(cls,NSSelectorFromString(name));return m && strcmp(method_getTypeEncoding(m),encoding)==0;}
static BOOL compatible(void){
 NSBundle *b=[NSBundle bundleWithPath:@"/Library/Image Capture/Support/EPSON/Epson Scan 2/Core/Scanner.framework"];
 if(![[b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"6.7.84"] || ![b load])return NO;
 Class c=NSClassFromString(@"ESCI2Scanner"),u=NSClassFromString(@"USBInterface");
 if(!exact(u,@"initWithLocationID:productIDForValidation:","@24@0:8I16S20"))return NO;
 NSDictionary *types=@{@"initWithInterface:":@"@24@0:8@16",@"open":@"i16@0:8",@"close":@"i16@0:8",@"isOpened":@"B16@0:8",@"setDelegate:":@"v24@0:8@16",@"setWorkFolder:":@"v24@0:8@16",@"autoFeedingModeSupported":@"B16@0:8",@"duplexSupported":@"B16@0:8",@"autoCroppingSupported":@"B16@0:8",@"skewCorrectionSupported":@"B16@0:8",@"supportedColorFormats":@"@16@0:8",@"supportedImageFormats":@"@16@0:8",@"setXResolution:":@"v24@0:8Q16",@"setYResolution:":@"v24@0:8Q16",@"setColorFormat:":@"v20@0:8i16",@"colorFormat":@"i16@0:8",@"setImageFormat:":@"v20@0:8i16",@"imageFormat":@"i16@0:8",@"setDuplexEnabled:":@"v20@0:8B16",@"duplexEnabled":@"B16@0:8",@"setAutoCroppingEnabled:":@"v20@0:8B16",@"autoCroppingEnabled":@"B16@0:8",@"setSkewCorrectionEnabled:":@"v20@0:8B16",@"skewCorrectionEnabled":@"B16@0:8",@"setScanAreaInPixel:":@"v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16",@"setAutoFeedingModeTimeout:":@"v24@0:8Q16",@"startScanningInAFM":@"i16@0:8",@"stopScanningInAutoFeedingMode":@"i16@0:8",@"isScanning":@"B16@0:8",@"jobMode":@"C16@0:8"};
 for(NSString *key in types)if(!exact(c,key,[types[key] UTF8String]))return NO;
 return YES;
}
@interface FeedingReceiver:NSObject
@property(atomic) BOOL failed; @property(atomic) BOOL stopRequested;
@property NSUInteger pages; @property BOOL rotate; @property BOOL duplex;
@property(strong) NSString *folder;
@end
@implementation FeedingReceiver
- (void)scannerWillBeginContinuousScanning:(id)s{emit(@"batchBegin",1);}
- (void)scannerDidEndContinuousScanning:(id)s{emit(@"batchEnd",1);}
- (void)scannerDidRequestStop:(id)s{self.stopRequested=YES;}
- (void)scannerDidDisconnect:(id)s{self.failed=YES;emit(@"error",-310);}
- (void)scanner:(id)s didCompleteScanningWithError:(int)e{if(e){self.failed=YES;emit(@"error",e);}}
- (void)scanner:(id)s didInterruptScanningWithError:(int)e{self.failed=YES;emit(@"error",e?e:-311);}
- (void)scanner:(id)s didScanToScannedImageHandle:(id<FeedingImage>)handle {
 @synchronized(self){@autoreleasepool{
  if(self.failed)return;
  Class c=[handle class];NSDictionary *types=@{@"seekToOffset:":@"v24@0:8Q16",@"readDataToEnd":@"@16@0:8",@"bitsPerSample":@"Q16@0:8",@"samplesPerPixel":@"Q16@0:8",@"surfaceType":@"i16@0:8",@"paperSerialNumber":@"Q16@0:8",@"closed":@"B16@0:8",@"imageFormat":@"i16@0:8"};
  for(NSString *key in types)if(!exact(c,key,[types[key] UTF8String])){self.failed=YES;emit(@"error",-312);return;}
  int side=[handle surfaceType];NSUInteger sheet=[handle paperSerialNumber];
  if(![handle closed]||[handle bitsPerSample]!=8||[handle samplesPerPixel]!=3||[handle imageFormat]!=1||side<0||side>1||sheet<1||(!self.duplex&&side!=0)){self.failed=YES;emit(@"error",-313);return;}
  [handle seekToOffset:0];NSData *data=[handle readDataToEnd];
  NSString *raw=[self.folder stringByAppendingPathComponent:[NSString stringWithFormat:@"raw-%04lu.jpeg",self.pages+1]];
  NSString *name=[NSString stringWithFormat:@"page-%04lu.jpg",self.pages+1];NSString *output=[self.folder stringByAppendingPathComponent:name];
  if(data.length<4||data.length>300*1024*1024||![data writeToFile:raw options:NSDataWritingWithoutOverwriting error:nil]){self.failed=YES;emit(@"error",-314);return;}
  unsigned orientation=0;int status=EDCorrectJPEG(raw.fileSystemRepresentation,output.fileSystemRepresentation,self.rotate,&orientation);
  if(status){self.failed=YES;emit(@"error",-320-status);return;}
  [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:output error:nil];
  NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:output];[file synchronizeFile];[file closeFile];
  [NSFileManager.defaultManager removeItemAtPath:raw error:nil];self.pages++;
  emitObject(@{@"event":@"page",@"value":@(self.pages),@"file":name,@"sheet":@(sheet),@"side":@(side)});
 }}
}
@end
int main(int argc,char **argv){@autoreleasepool{
 BOOL check=argc==2&&strcmp(argv[1],"--check")==0;
 if(!compatible()){emit(@"error",-301);emit(@"closed",0);return 1;}
 if(check){emit(@"compatible",6784);return 0;}
 if(argc!=5||argv[1][0]!='/'||argv[2][0]!='/')return 2;
 pid_t parent=(pid_t)strtol(argv[4],NULL,10);if(parent<=1||getppid()!=parent)return 2;
 NSString *root=@(argv[1]),*folder=@(argv[2]);
 NSString *expected=[root stringByAppendingPathComponent:@"Pending"];
 if(![[folder stringByDeletingLastPathComponent] isEqual:expected]||![[NSUUID alloc] initWithUUIDString:folder.lastPathComponent])return 2;
 NSData *bytes=[[NSData alloc] initWithBase64EncodedString:@(argv[3]) options:0];NSDictionary *settings=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;
 if(![settings isKindOfClass:NSDictionary.class]||![settings[@"automaticFeeding"] isEqual:@YES]||[settings[@"paused"] boolValue])return 2;
 for(NSString *key in @[@"duplex",@"crop",@"deskew",@"rotate"])if(![settings[key] isKindOfClass:NSNumber.class])return 2;
 signal(SIGTERM,signalHandler);signal(SIGINT,signalHandler);signal(SIGUSR1,signalHandler);
 [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyProhibited];
 int lease=claimLease(root);if(lease<0){emit(@"error",-302);emit(@"closed",0);return 1;}
 if(getppid()!=parent){close(lease);emit(@"closed",0);return 1;}
 unsigned location=0;if(!findLocation(&location)){close(lease);emit(@"error",-303);emit(@"closed",0);return 1;}
 id<FeedingUSB> usb=[(id<FeedingUSB>)[NSClassFromString(@"USBInterface") alloc] initWithLocationID:location productIDForValidation:400];
 id<FeedingScanner> scanner=[(id<FeedingScanner>)[NSClassFromString(@"ESCI2Scanner") alloc] initWithInterface:usb];
 FeedingReceiver *receiver=[FeedingReceiver new];receiver.folder=folder;receiver.rotate=[settings[@"rotate"] boolValue];receiver.duplex=[settings[@"duplex"] boolValue];
 NSString *work=[[root stringByAppendingPathComponent:@"DriverWork"] stringByAppendingPathComponent:folder.lastPathComponent];
 [NSFileManager.defaultManager createDirectoryAtPath:work withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 [scanner setWorkFolder:work];[scanner setDelegate:receiver];int result=1;BOOL opened=NO;
 @try{
  int status=[scanner open];opened=[scanner isOpened];if(status||!opened){emit(@"error",-304);return 1;}
  if(![scanner autoFeedingModeSupported]||![[scanner supportedColorFormats] containsIndex:1800]||![[scanner supportedImageFormats] containsIndex:1]||(receiver.duplex&&![scanner duplexSupported])||([settings[@"crop"] boolValue]&&![scanner autoCroppingSupported])||([settings[@"deskew"] boolValue]&&![scanner skewCorrectionSupported])){emit(@"error",-305);return 1;}
  [scanner setXResolution:300];[scanner setYResolution:300];[scanner setColorFormat:1800];[scanner setImageFormat:1];[scanner setDuplexEnabled:receiver.duplex];[scanner setAutoCroppingEnabled:[settings[@"crop"] boolValue]];[scanner setSkewCorrectionEnabled:[settings[@"deskew"] boolValue]];[scanner setScanAreaInPixel:CGRectMake(0,0,1748,2480)];
  // Parent measures inactivity after a processed batch, excluding active transfer.
  [scanner setAutoFeedingModeTimeout:0];
  if([scanner colorFormat]!=1800||[scanner imageFormat]!=1||[scanner duplexEnabled]!=receiver.duplex||[scanner autoCroppingEnabled]!=[settings[@"crop"] boolValue]||[scanner skewCorrectionEnabled]!=[settings[@"deskew"] boolValue]){emit(@"error",-306);return 1;}
  if(receiver.rotate){NSBundle *b=[NSBundle bundleWithPath:@"/Library/Image Capture/Support/EPSON/Epson Scan 2/Core/ImageProcessor.framework"];if(![[b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"6.7.84"]||![b load]||!NSClassFromString(@"EIPAnalyzer")||![NSFileManager.defaultManager fileExistsAtPath:@"/Library/Image Capture/Support/EPSON/Epson Scan 2/PlugIns/Esaod.bundle"]){emit(@"error",-307);return 1;}}
  if(aborted||getppid()!=parent)return 1;
  emit(@"ready",1);status=[scanner startScanningInAFM];if(status){emit(@"error",status);return 1;}
  BOOL stopSent=NO;NSTimeInterval stopDeadline=0;
  while([scanner jobMode]!=0||[scanner isScanning]){@autoreleasepool{
   [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
   if(getppid()!=parent)aborted=1;
   if((aborted||finishing||receiver.failed||receiver.stopRequested)&&!stopSent){stopSent=YES;stopDeadline=NSProcessInfo.processInfo.systemUptime+12;int code=[scanner stopScanningInAutoFeedingMode];if(code){receiver.failed=YES;emit(@"error",code);}}
   if(stopSent&&NSProcessInfo.processInfo.systemUptime>=stopDeadline){receiver.failed=YES;emit(@"error",-308);break;}
  }}
  result=receiver.failed||aborted?1:0;if(result==0)emit(@"end",0);
 }@catch(NSException *exception){emit(@"error",-309);result=1;}
 @finally{
  if([scanner jobMode]!=0)[scanner stopScanningInAutoFeedingMode];int code=opened?[scanner close]:0;
  emit(@"closed",code);if(code)result=1;[scanner setDelegate:nil];
  if(code==0)[NSFileManager.defaultManager removeItemAtPath:work error:nil];
  close(lease);
 }
 return result;
}}
