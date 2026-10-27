#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import "include/EpsonImageProcessing.h"

@protocol EDAnalyzer <NSObject>
- (id)initWithOption:(NSDictionary *)option;
- (unsigned int)judgeDocumentOrientationWithImage:(NSDictionary *)image data:(NSData *)data error:(NSError **)error;
@end

int EDCorrectJPEG(const char *input, const char *output, bool rotate, unsigned int *orientation) {
 @autoreleasepool {
    if (!input || !output || !orientation) return 1;
    *orientation = 1;
    NSData *data = [NSData dataWithContentsOfFile:@(input) options:0 error:nil];
    if (data.length < 4 || data.length > 300*1024*1024) return 2;
    const uint8_t *bytes = data.bytes;
    if (bytes[0]!=255 || bytes[1]!=216 || bytes[data.length-2]!=255 || bytes[data.length-1]!=217) return 2;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    if (!source) return 2;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    uint64_t w = [properties[(__bridge NSString*)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    uint64_t h = [properties[(__bridge NSString*)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    if (!w || !h || w>10000 || h>10000 || w*h>16000000 || CGImageSourceGetCount(source)!=1 || CGImageSourceGetStatus(source)!=kCGImageStatusComplete) { CFRelease(source); return 2; }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageSourceShouldCacheImmediately:@YES});
    BOOL complete = image && CGImageSourceGetStatusAtIndex(source,0)==kCGImageStatusComplete;
    CFRelease(source);
    if (!complete) { if(image)CGImageRelease(image); return 2; }
    @try {
        if (rotate) {
            NSBundle *bundle = [NSBundle bundleWithPath:@"/Library/Image Capture/Support/EPSON/Epson Scan 2/Core/ImageProcessor.framework"];
            if (![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"6.7.84"] || ![bundle load]) { CGImageRelease(image); return 3; }
            Class cls = NSClassFromString(@"EIPAnalyzer");
            Method init = class_getInstanceMethod(cls,@selector(initWithOption:));
            Method judge = class_getInstanceMethod(cls,@selector(judgeDocumentOrientationWithImage:data:error:));
            if (!init || strcmp(method_getTypeEncoding(init),"@24@0:8@16") || !judge || strcmp(method_getTypeEncoding(judge),"I40@0:8@16@24^@32")) { CGImageRelease(image); return 3; }
            NSString *aod = @"/Library/Image Capture/Support/EPSON/Epson Scan 2/PlugIns/Esaod.bundle";
            if (![NSFileManager.defaultManager fileExistsAtPath:aod]) { CGImageRelease(image); return 3; }
            NSMutableData *rgba = [NSMutableData dataWithLength:w*h*4];
            CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(rgba.mutableBytes,w,h,8,w*4,color,kCGImageAlphaNoneSkipLast|kCGBitmapByteOrder32Big);
            CGColorSpaceRelease(color);
            if(!context) { CGImageRelease(image); return 4; }
            CGContextDrawImage(context,CGRectMake(0,0,w,h),image); CGContextRelease(context);
            // Epson's TWAIN input is tightly packed RGB, without the CGContext alpha byte.
            NSMutableData *packed = [NSMutableData dataWithLength:w*h*3];
            const uint8_t *from = rgba.bytes; uint8_t *to = packed.mutableBytes;
            for (size_t n=0;n<w*h;n++) memcpy(to+n*3,from+n*4,3);
            id<EDAnalyzer> analyzer = [(id<EDAnalyzer>)[cls alloc] initWithOption:@{@"aodPath":aod}];
            if(!analyzer) { CGImageRelease(image); return 3; }
            NSError *error=nil;
            *orientation = [analyzer judgeDocumentOrientationWithImage:@{@"width":@(w),@"height":@(h),@"bitsPerSample":@8,@"samplesPerPixel":@3,@"resolutionX":@300,@"resolutionY":@300} data:packed error:&error];
            if(error || *orientation<1 || *orientation>4) { CGImageRelease(image); return 4; }
        }
        if(*orientation==1) {
            CGImageRelease(image); image=NULL;
            return [data writeToFile:@(output) options:NSDataWritingWithoutOverwriting error:nil] ? 0 : 5;
        }
        size_t ow=(*orientation==2||*orientation==4)?h:w, oh=(*orientation==2||*orientation==4)?w:h;
        CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
        CGContextRef context=CGBitmapContextCreate(NULL,ow,oh,8,ow*4,color,kCGImageAlphaNoneSkipLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(color);
        if(!context) { CGImageRelease(image); return 4; }
        CGContextTranslateCTM(context,ow/2.0,oh/2.0);CGContextRotateCTM(context,-(double)(*orientation-1)*M_PI_2);
        CGContextDrawImage(context,CGRectMake(-(double)w/2,-(double)h/2,w,h),image);CGImageRelease(image);image=NULL;
        CGImageRef result=CGBitmapContextCreateImage(context);CGContextRelease(context);
        NSMutableData *encoded=[NSMutableData data];
        CGImageDestinationRef writer=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)encoded,CFSTR("public.jpeg"),1,NULL);
        if(!result || !writer){if(result)CGImageRelease(result);if(writer)CFRelease(writer);return 5;}
        CGImageDestinationAddImage(writer,result,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageDestinationLossyCompressionQuality:@0.95,(__bridge NSString*)kCGImagePropertyDPIWidth:@300,(__bridge NSString*)kCGImagePropertyDPIHeight:@300});
        BOOL saved=CGImageDestinationFinalize(writer);CFRelease(writer);CGImageRelease(result);
        return saved && [encoded writeToFile:@(output) options:NSDataWritingWithoutOverwriting error:nil] ? 0 : 5;
    } @catch(NSException *exception) { if(image)CGImageRelease(image); return 6; }
 }
}
