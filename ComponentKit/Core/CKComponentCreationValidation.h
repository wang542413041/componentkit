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

#import <Foundation/Foundation.h>

#import <RenderCore/RCAssert.h>
#import <ComponentKit/CKComponentContext.h>

#if CK_ASSERTIONS_ENABLED

typedef NS_ENUM(NSUInteger, CKComponentCreationValidationSource) {
  CKComponentCreationValidationSourceBuild,
  CKComponentCreationValidationSourceLayout,
};

/**
 This is used for assertion if component is created outside of component provider function.
 */
@interface CKComponentCreationValidationContext : NSObject

/**
 This flag indicates where this context is pushed from.
 */
@property (nonatomic, readonly, assign) CKComponentCreationValidationSource source;

- (instancetype)initWithSource:(CKComponentCreationValidationSource)source NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end


#define CKValidateComponentCreation() \
  do { \
    RCAssertWithCategory(CKComponentContext<CKComponentCreationValidationContext>::get() != nil, \
                         NSStringFromClass(self.class), \
                         @"Component should not be created outside of component provider function."); \
  } while (0)
#define CKValidateRenderComponentCreation() \
  do { \
    const auto validationContext = CKComponentContext<CKComponentCreationValidationContext>::get(); \
    if (!validationContext) { \
      RCFailAssertWithCategory(NSStringFromClass(self.class), \
                               @"Component should not be created outside of component provider function."); \
    } else {\
      RCAssertWithCategory(validationContext.source != CKComponentCreationValidationSourceLayout, \
                           NSStringFromClass(self.class), \
                           @"Render component shouldn't be created during component layout"); \
    } \
  } while (0)
#else
#define CKValidateComponentCreation() do {} while (0)
#define CKValidateRenderComponentCreation() do {} while (0)
#endif

#endif
