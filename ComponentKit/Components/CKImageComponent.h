/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <ComponentKit/CKDefines.h>

#if CK_NOT_SWIFT

#import <ComponentKit/CKComponent.h>

struct RCComponentSize;

/**
 A component that displays an image using UIImageView.
 */
@interface CKImageComponent : CKComponent

CK_COMPONENT_INIT_UNAVAILABLE;

/**
 Uses a static layout with the given image size and applies additional attributes.
 */
- (instancetype)initWithImage:(UIImage *)image
                  attributes:(const CKViewComponentAttributeValueMap &)attributes
                        size:(const RCComponentSize &)size NS_DESIGNATED_INITIALIZER;

@end

#import <ComponentKit/ImageComponentBuilder.h>

#endif
