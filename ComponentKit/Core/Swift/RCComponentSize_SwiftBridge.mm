/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <ComponentKit/RCComponentSize_SwiftBridge.h>
#import <ComponentKit/RCComponentSize_SwiftBridge+Internal.h>

#import <ComponentKit/CKCasting.h>
#import <ComponentKit/RCDimension_SwiftBridge+Internal.h>

static auto toRelativeDimention(RCDimension_SwiftBridge *_Nullable swiftDimension) {
  return swiftDimension != nil ? swiftDimension.dimension : RCRelativeDimension();
}

@implementation RCComponentSize_SwiftBridge {
  RCComponentSize _size;
}

- (instancetype)initWithComponentSize:(const RCComponentSize &)componentSize
{
  if (self = [super init]) {
    _size = componentSize;
  }
  return self;
}

- (instancetype)init
{
  return [self initWithComponentSize:{}];
}

- (instancetype)initWithSize:(CGSize)size
{
  return [self initWithComponentSize:RCComponentSize::fromCGSize(size)];
}

- (instancetype)initWithWidth:(RCDimension_SwiftBridge *)width
                       height:(RCDimension_SwiftBridge *)height
                     minWidth:(RCDimension_SwiftBridge *)minWidth
                    minHeight:(RCDimension_SwiftBridge *)minHeight
                     maxWidth:(RCDimension_SwiftBridge *)maxWidth
                    maxHeight:(RCDimension_SwiftBridge *)maxHeight
{
  return
  [self initWithComponentSize:{
    .width = toRelativeDimention(width),
    .height = toRelativeDimention(height),
    .minWidth = toRelativeDimention(minWidth),
    .minHeight = toRelativeDimention(minHeight),
    .maxWidth = toRelativeDimention(maxWidth),
    .maxHeight = toRelativeDimention(maxHeight),
  }];
}

- (const RCComponentSize &)componentSize
{
  return _size;
}

- (BOOL)isEqual:(id)other
{
  if (other == nil) {
    return NO;
  } else if (other == self) {
    return YES;
  } else {
    // Intentionally treat passing a different type as a programming error
    return _size == CK::objCForceCast<RCComponentSize_SwiftBridge>(other)->_size;
  }
}

- (NSUInteger)hash
{
  return std::hash<RCComponentSize>{}(_size);
}

- (NSString *)description
{
  return _size.description();
}

@end
