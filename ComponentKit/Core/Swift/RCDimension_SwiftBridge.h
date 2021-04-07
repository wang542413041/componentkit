/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

__attribute__((objc_subclassing_restricted))
NS_SWIFT_NAME(DimensionSwiftBridge)
@interface RCDimension_SwiftBridge : NSObject

- (instancetype)initWithPoints:(CGFloat)points;
- (instancetype)initWithPercent:(CGFloat)percent;

+ (instancetype)autoInstance;

@end

NS_ASSUME_NONNULL_END
