/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <UIKit/UIKit.h>
#import <ComponentKit/CKDefines.h>

#if !defined(__cplusplus) && CK_NOT_SWIFT
#error This file must be compiled Obj-C++ or imported from Swift. Objective-C files should have their extension changed to .mm.
#endif

#if defined(__has_feature) && !__has_feature(objc_arc_fields)
#error "ComponentKit requires compiler to support objc pointers in C structures"
#endif

#if defined(__has_feature) && !__has_feature(objc_arc)
#error "ComponentKit requires ARC (Automatic Reference Counting)"
#endif

#import <ComponentKit/CKComponentProtocol.h>
#import <ComponentKit/RCComponentSize.h>
#import <ComponentKit/RCComponentSize_SwiftBridge.h>
#import <ComponentKit/CKComponentViewConfiguration.h>
#import <ComponentKit/CKComponentViewConfiguration_SwiftBridge.h>
#import <ComponentKit/CKMountable.h>

NS_ASSUME_NONNULL_BEGIN

/** A component is an immutable object that specifies how to configure a view, loosely inspired by React. */
NS_SWIFT_NAME(Component)
@interface CKComponent : NSObject <CKMountable, CKComponentProtocol>

#if CK_SWIFT

- (instancetype)initWithSwiftView:(CKComponentViewConfiguration_SwiftBridge *_Nullable)swiftView
                        swiftSize:(RCComponentSize_SwiftBridge *_Nullable)swiftSize NS_REFINED_FOR_SWIFT NS_DESIGNATED_INITIALIZER;

#else

/**
 @param view A struct describing the view for this component. Pass {} to specify that no view should be created.
 @param size A size constraint that should apply to this component. Pass {} to specify no size constraint.

 @example A component that renders a red square:
 [CKComponent newWithView:{[UIView class], {{@selector(setBackgroundColor:), [UIColor redColor]}}} size:{100, 100}]
*/
- (instancetype)initWithView:(const CKComponentViewConfiguration &)view
                        size:(const RCComponentSize &)size NS_DESIGNATED_INITIALIZER;

/**
 DEPRECATED - Do not use. Use CK::ComponentBuilder instead.
 @param view A struct describing the view for this component. Pass {} to specify that no view should be created.
 @param size A size constraint that should apply to this component. Pass {} to specify no size constraint.

 @example A component that renders a red square:
 [CKComponent newWithView:{[UIView class], {{@selector(setBackgroundColor:), [UIColor redColor]}}} size:{100, 100}]
 */
+ (instancetype)newWithView:(const CKComponentViewConfiguration &)view
                       size:(const RCComponentSize &)size;

#endif

/**
 While the component is mounted, returns its next responder. This is the first of:
 - Its component controller, if it has one;
 - Its supercomponent;
 - The view the component is mounted within, if it is the root component.
 */
- (id _Nullable)nextResponder;

@end

#if CK_SWIFT
#define CK_COMPONENT_INIT_UNAVAILABLE \
  - (instancetype)initWithSwiftView:(CKComponentViewConfiguration_SwiftBridge *_Nullable)swiftView \
                          swiftSize:(RCComponentSize_SwiftBridge *_Nullable)swiftSize NS_UNAVAILABLE;
#else
#define CK_COMPONENT_INIT_UNAVAILABLE \
  + (instancetype)newWithView:(const CKComponentViewConfiguration &)view \
                         size:(const RCComponentSize &)size NS_UNAVAILABLE; \
  - (instancetype)initWithView:(const CKComponentViewConfiguration &)view \
                          size:(const RCComponentSize &)size NS_UNAVAILABLE;
#endif

NS_ASSUME_NONNULL_END

#import <ComponentKit/ComponentBuilder.h>
