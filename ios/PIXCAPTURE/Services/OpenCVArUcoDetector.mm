#import "OpenCVArUcoDetector.h"

#import <CoreVideo/CoreVideo.h>

#if __has_include(<opencv2/opencv.hpp>) && __has_include(<opencv2/aruco.hpp>)
#define PIXCAPTURE_HAS_OPENCV 1
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wdocumentation-deprecated-sync"
#endif
#import <opencv2/aruco.hpp>
#import <opencv2/imgproc.hpp>
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
#else
#define PIXCAPTURE_HAS_OPENCV 0
#endif

@implementation OpenCVArUcoDetection

- (instancetype)initWithMarkerId:(NSInteger)markerId
           normalizedBoundingBox:(CGRect)normalizedBoundingBox
                      confidence:(float)confidence {
  self = [super init];
  if (!self) {
    return nil;
  }
  _markerId = markerId;
  _normalizedBoundingBox = normalizedBoundingBox;
  _confidence = confidence;
  return self;
}

@end

@interface OpenCVArUcoDetector () {
#if PIXCAPTURE_HAS_OPENCV
  cv::Ptr<cv::aruco::Dictionary> _dictionary;
  cv::Ptr<cv::aruco::DetectorParameters> _parameters;
#endif
}
@end

@implementation OpenCVArUcoDetector

+ (BOOL)isOpenCVAvailable {
#if PIXCAPTURE_HAS_OPENCV
  return YES;
#else
  return NO;
#endif
}

- (instancetype)init {
  self = [super init];
  if (!self) {
    return nil;
  }

#if PIXCAPTURE_HAS_OPENCV
  _dictionary = cv::makePtr<cv::aruco::Dictionary>(
    cv::aruco::getPredefinedDictionary(cv::aruco::DICT_4X4_100)
  );
  _parameters = cv::makePtr<cv::aruco::DetectorParameters>();
#endif

  return self;
}

- (NSArray<OpenCVArUcoDetection *> *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer {
  if (pixelBuffer == nil) {
    return @[];
  }

#if !PIXCAPTURE_HAS_OPENCV
  (void)pixelBuffer;
  return @[];
#else
  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  cv::Mat gray;
  OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);

  if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
      pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
    uint8_t *luma = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);

    if (luma != nullptr && width > 0 && height > 0 && bytesPerRow > 0) {
      cv::Mat yPlane((int)height, (int)width, CV_8UC1, luma, bytesPerRow);
      gray = yPlane.clone();
    }
  } else if (pixelFormat == kCVPixelFormatType_32BGRA) {
    uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    if (base != nullptr && width > 0 && height > 0 && bytesPerRow > 0) {
      cv::Mat bgra((int)height, (int)width, CV_8UC4, base, bytesPerRow);
      cv::cvtColor(bgra, gray, cv::COLOR_BGRA2GRAY);
    }
  }

  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  if (gray.empty()) {
    return @[];
  }

  std::vector<int> ids;
  std::vector<std::vector<cv::Point2f>> corners;
  cv::aruco::detectMarkers(gray, _dictionary, corners, ids, _parameters);

  if (ids.empty() || corners.empty()) {
    return @[];
  }

  NSMutableArray<OpenCVArUcoDetection *> *results = [NSMutableArray arrayWithCapacity:ids.size()];

  float widthInv = 1.0f / (float)gray.cols;
  float heightInv = 1.0f / (float)gray.rows;

  for (size_t i = 0; i < ids.size() && i < corners.size(); ++i) {
    const std::vector<cv::Point2f> &quad = corners[i];
    if (quad.empty()) {
      continue;
    }

    float minX = 1.0f;
    float maxX = 0.0f;
    float minYTop = 1.0f;
    float maxYTop = 0.0f;

    for (const cv::Point2f &pt : quad) {
      float nx = pt.x * widthInv;
      float nyTop = pt.y * heightInv;
      minX = std::min(minX, nx);
      maxX = std::max(maxX, nx);
      minYTop = std::min(minYTop, nyTop);
      maxYTop = std::max(maxYTop, nyTop);
    }

    minX = std::max(0.0f, std::min(1.0f, minX));
    maxX = std::max(0.0f, std::min(1.0f, maxX));
    minYTop = std::max(0.0f, std::min(1.0f, minYTop));
    maxYTop = std::max(0.0f, std::min(1.0f, maxYTop));

    float widthNorm = std::max(0.0f, maxX - minX);
    float heightNorm = std::max(0.0f, maxYTop - minYTop);

    // OpenCV uses top-left origin. SwiftUI overlay expects bottom-left normalized origin.
    float minYBottom = 1.0f - maxYTop;
    CGRect bbox = CGRectMake(minX, minYBottom, widthNorm, heightNorm);

    OpenCVArUcoDetection *detection = [[OpenCVArUcoDetection alloc] initWithMarkerId:ids[i]
                                                                normalizedBoundingBox:bbox
                                                                           confidence:1.0f];
    [results addObject:detection];
  }

  return results;
#endif
}

@end
