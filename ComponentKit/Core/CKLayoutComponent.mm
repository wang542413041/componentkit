/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKLayoutComponent.h"

#import "CKComponentInternal.h"
#import "CKComponentSubclass.h"
#import "CKRenderHelpers.h"

@implementation CKLayoutComponent

#pragma mark - CKMountable

- (unsigned int)numberOfChildren
{
  RCFailAssert(@"%@ MUST override the '%@' method.", self.className, NSStringFromSelector(_cmd));
  return 0;
}

- (id<CKMountable>)childAtIndex:(unsigned int)index
{
  RCFailAssert(@"%@ MUST override the '%@' method.", self.className, NSStringFromSelector(_cmd));
  return nil;
}

- (RCLayout)computeLayoutThatFits:(CKSizeRange)constrainedSize
{
  RCFailAssert(@"%@ MUST override the '%@' method.", self.className, NSStringFromSelector(_cmd));
  return [super computeLayoutThatFits:constrainedSize];
}

@end
