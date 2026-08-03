#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVArUcoDetection : NSObject
@property(nonatomic, readonly) NSInteger markerId;
@property(nonatomic, readonly) CGRect normalizedBoundingBox;
@property(nonatomic, readonly) float confidence;

- (instancetype)initWithMarkerId:(NSInteger)markerId
           normalizedBoundingBox:(CGRect)normalizedBoundingBox
                      confidence:(float)confidence NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface OpenCVArUcoDetector : NSObject
@property(class, nonatomic, readonly) BOOL isOpenCVAvailable;

- (NSArray<OpenCVArUcoDetection *> *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer NS_SWIFT_NAME(detect(pixelBuffer:));
@end

NS_ASSUME_NONNULL_END
