#include "ApplePlatformContext.h"

#include <TargetConditionals.h>

#import <React/RCTBlobManager.h>
#import <React/RCTBridge+Private.h>
#import <ReactCommon/RCTTurboModule.h>

#include "RNWebGPUManager.h"
#include "WebGPUModule.h"

namespace rnwgpu {

void checkIfUsingSimulatorWithAPIValidation() {
#if TARGET_OS_SIMULATOR
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *metalDeviceWrapperType = environment[@"METAL_DEVICE_WRAPPER_TYPE"];

  if ([metalDeviceWrapperType isEqualToString:@"1"]) {
    throw std::runtime_error(
        "To use React Native WebGPU project on the iOS simulator, you need to "
        "disable the Metal validation API. In 'Edit Scheme,' uncheck 'Metal "
        "Validation.'");
  }
#endif
}

ApplePlatformContext::ApplePlatformContext() {
  checkIfUsingSimulatorWithAPIValidation();
}

wgpu::Surface ApplePlatformContext::makeSurface(wgpu::Instance instance,
                                                void *surface, int width,
                                                int height) {
  wgpu::SurfaceSourceMetalLayer metalSurfaceDesc;
  metalSurfaceDesc.layer = surface;
  wgpu::SurfaceDescriptor surfaceDescriptor;
  surfaceDescriptor.nextInChain = &metalSurfaceDesc;
  return instance.CreateSurface(&surfaceDescriptor);
}

ImageData ApplePlatformContext::createImageBitmap(std::string blobId,
                                                  double offset, double size) {
  RCTBlobManager *blobManager =
      [[RCTBridge currentBridge] moduleForClass:RCTBlobManager.class];
  NSData *blobData =
      [blobManager resolve:[NSString stringWithUTF8String:blobId.c_str()]
                    offset:(long)offset
                      size:(long)size];

  if (!blobData) {
    throw std::runtime_error("Couldn't retrive blob data");
  }

#if !TARGET_OS_OSX
  UIImage *image = [UIImage imageWithData:blobData];
#else
  NSImage *image = [[NSImage alloc] initWithData:blobData];
#endif
  if (!image) {
    throw std::runtime_error("Couldn't decode image");
  }

#if !TARGET_OS_OSX
  CGImageRef cgImage = image.CGImage;
#else
  CGImageRef cgImage = [image CGImageForProposedRect:NULL
                                             context:NULL
                                               hints:NULL];
#endif
  size_t width = CGImageGetWidth(cgImage);
  size_t height = CGImageGetHeight(cgImage);
  size_t bitsPerComponent = 8;
  size_t bytesPerRow = width * 4;
  std::vector<uint8_t> imageData(height * bytesPerRow);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(
      imageData.data(), width, height, bitsPerComponent, bytesPerRow,
      colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

  CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);

  // Now imageData contains a copy of the bitmap data

  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);

  // Use the copied data
  ImageData result;
  result.width = static_cast<int>(width);
  result.height = static_cast<int>(height);
  result.data = imageData;
  result.format = wgpu::TextureFormat::RGBA8Unorm;
  return result;
}

} // namespace rnwgpu
