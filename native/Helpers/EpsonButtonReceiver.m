// Our own bridge to the user's installed driver. No Epson code is bundled.
#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import <objc/runtime.h>
#include <signal.h>
#include <unistd.h>

@protocol EpsonUSB <NSObject>
- (id)initWithLocationID:(unsigned int)location productIDForValidation:(unsigned short)product;
@end
@protocol EpsonScanner <NSObject>
- (id)initWithInterface:(id)interface;
- (void)setDelegate:(id)delegate;
- (int)open;
- (int)close;
- (BOOL)isOpened;
@end
static volatile sig_atomic_t stopped = 0;
static void stopReceiver(int number) { stopped = 1; }
static void emit(NSString *event, NSInteger value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"event":event, @"value":@(value)} options:0 error:nil];
    if (data) { fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout); }
}
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
@interface ButtonReceiver : NSObject
@property BOOL armed;
@property BOOL pressed;
@property BOOL disconnected;
@end
@implementation ButtonReceiver
- (void)scanner:(id)scanner didPressButton:(long long)number {
    if (self.armed && number == 1 && !self.pressed) { self.pressed = YES; stopped = 1; }
}
- (void)scannerDidDisconnect:(id)scanner { self.disconnected = YES; stopped = 1; }
@end

int main(int argc, char **argv) { @autoreleasepool {
    BOOL checkOnly = argc == 2 && strcmp(argv[1], "--check") == 0;
    pid_t parent = argc == 3 ? (pid_t)strtol(argv[2], NULL, 10) : 0;
    if (!checkOnly && (argc != 3 || strcmp(argv[1], "--parent") != 0 || parent <= 1 || parent != getppid())) return 2;
    signal(SIGTERM, stopReceiver); signal(SIGINT, stopReceiver);
    [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSBundle *bundle = [NSBundle bundleWithPath:@"/Library/Image Capture/Support/EPSON/Epson Scan 2/Core/Scanner.framework"];
    NSError *error = nil;
    // This internal ABI has only been checked with the installed 6.7.84 driver.
    if (![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"6.7.84"] || ![bundle loadAndReturnError:&error]) {
        emit(@"error", -101); emit(@"closed", 0); return 1;
    }
    Class usbClass = NSClassFromString(@"USBInterface"), scannerClass = NSClassFromString(@"ESCI2Scanner");
    BOOL valid = usbClass && scannerClass &&
        methodHasReturn(usbClass, @selector(initWithLocationID:productIDForValidation:), "@", 4) &&
        argumentHasType(usbClass, @selector(initWithLocationID:productIDForValidation:), 2, "I") &&
        argumentHasType(usbClass, @selector(initWithLocationID:productIDForValidation:), 3, "S") &&
        methodHasReturn(scannerClass, @selector(initWithInterface:), "@", 3) &&
        argumentHasType(scannerClass, @selector(initWithInterface:), 2, "@") &&
        methodHasReturn(scannerClass, @selector(setDelegate:), "v", 3) &&
        argumentHasType(scannerClass, @selector(setDelegate:), 2, "@") &&
        methodHasReturn(scannerClass, @selector(open), "i", 2) &&
        methodHasReturn(scannerClass, @selector(close), "i", 2) &&
        (methodHasReturn(scannerClass, @selector(isOpened), "B", 2) || methodHasReturn(scannerClass, @selector(isOpened), "c", 2));
    if (!valid) { emit(@"error", -102); emit(@"closed", 0); return 1; }
    if (checkOnly) { emit(@"compatible", 6784); return 0; }
    unsigned int location = 0;
    if (!findLocation(&location)) { emit(@"error", -103); emit(@"closed", 0); return 1; }
    id<EpsonUSB> usb = [(id<EpsonUSB>)[usbClass alloc] initWithLocationID:location productIDForValidation:400];
    id<EpsonScanner> scanner = [(id<EpsonScanner>)[scannerClass alloc] initWithInterface:usb];
    if (!usb || !scanner) { emit(@"error", -104); emit(@"closed", 0); return 1; }
    ButtonReceiver *receiver = [ButtonReceiver new]; [scanner setDelegate:receiver];
    int result = 1; BOOL opened = NO;
    @try {
        int status = [scanner open]; opened = [scanner isOpened];
        if (status != 0 || !opened) { emit(@"error", -105); }
        else {
            // Drain events delivered during opening; only presses after Ready count.
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.35]];
            if (!stopped && getppid() == parent) {
                receiver.armed = YES; emit(@"ready", 1);
                NSTimeInterval nextCheck = [NSDate timeIntervalSinceReferenceDate] + 1;
                while (!stopped && getppid() == parent) { @autoreleasepool {
                    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                    if ([NSDate timeIntervalSinceReferenceDate] >= nextCheck) {
                        unsigned int current = 0;
                        if (!findLocation(&current) || current != location) { receiver.disconnected = YES; stopped = 1; }
                        nextCheck = [NSDate timeIntervalSinceReferenceDate] + 1;
                    }
                } }
            }
            result = receiver.disconnected ? 1 : 0;
            if (receiver.disconnected) emit(@"error", -106);
        }
    } @catch (NSException *exception) { emit(@"error", -107); }
    @finally {
        int closeStatus = opened ? [scanner close] : 0;
        if (result == 0 && closeStatus == 0 && receiver.pressed) emit(@"button", 1);
        emit(@"closed", closeStatus);
        if (closeStatus != 0) result = 1;
    }
    return result;
} }
