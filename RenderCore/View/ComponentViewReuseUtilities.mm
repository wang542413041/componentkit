/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "ComponentViewReuseUtilities.h"

#import <objc/runtime.h>
#import <unordered_map>

#import <RenderCore/RCAssert.h>
#import <RenderCore/RCAssociatedObject.h>

#import "CKComponentViewClass.h"

using namespace CK::Component;

static char const kViewReuseInfoKey = ' ';

@interface CKComponentViewReuseInfo : NSObject
- (instancetype)initWithView:(UIView *)view
      didEnterReusePoolBlock:(void (^)(UIView *))didEnterReusePoolBlock
     willLeaveReusePoolBlock:(void (^)(UIView *))willLeaveReusePoolBlock;
- (void)registerChildViewInfo:(CKComponentViewReuseInfo *)info;
- (void)didHide:(CK::Component::MountAnalyticsContext *)mountAnalyticsContext;
- (void)willUnhide:(CK::Component::MountAnalyticsContext *)mountAnalyticsContext;
- (void)ancestorDidHide;
- (void)ancestorWillUnhide;
@end

void ViewReuseUtilities::mountingInRootView(UIView *rootView) noexcept
{
  // If we already mounted in this root view, it will already have a reuse info struct.
  if (RCGetAssociatedObject_MainThreadAffined(rootView, &kViewReuseInfoKey)) {
    return;
  }

  CKComponentViewReuseInfo *info = [[CKComponentViewReuseInfo alloc] initWithView:rootView
                                                           didEnterReusePoolBlock:nil
                                                          willLeaveReusePoolBlock:nil];
  RCSetAssociatedObject_MainThreadAffined(rootView, &kViewReuseInfoKey, info);
}

void ViewReuseUtilities::createdView(UIView *view, const CKComponentViewClass &viewClass, UIView *parent) noexcept
{
  RCCAssertNil(RCGetAssociatedObject_MainThreadAffined(view, &kViewReuseInfoKey),
               @"Didn't expect reuse info on just-created view %@", view);

  CKComponentViewReuseInfo *info = [[CKComponentViewReuseInfo alloc] initWithView:view
                                                           didEnterReusePoolBlock:viewClass.didEnterReusePool
                                                          willLeaveReusePoolBlock:viewClass.willLeaveReusePool];
  RCSetAssociatedObject_MainThreadAffined(view, &kViewReuseInfoKey, info);

  CKComponentViewReuseInfo *parentInfo = RCGetAssociatedObject_MainThreadAffined(parent, &kViewReuseInfoKey);
  RCCAssertNotNil(parentInfo, @"Expected parentInfo but found none on %@", parent);
  [parentInfo registerChildViewInfo:info];
}

void ViewReuseUtilities::mountingInChildContext(UIView *view, UIView *parent) noexcept
{
  // If this view was created by the components infrastructure, or if we've
  // mounted in it before, it will already have a reuse info struct.
  if (RCGetAssociatedObject_MainThreadAffined(view, &kViewReuseInfoKey)) {
    return;
  }

  CKComponentViewReuseInfo *info = [[CKComponentViewReuseInfo alloc] initWithView:view
                                                           didEnterReusePoolBlock:nil
                                                          willLeaveReusePoolBlock:nil];
  RCSetAssociatedObject_MainThreadAffined(view, &kViewReuseInfoKey, info);

  CKComponentViewReuseInfo *parentInfo = RCGetAssociatedObject_MainThreadAffined(parent, &kViewReuseInfoKey);
  RCCAssertNotNil(parentInfo, @"Expected parentInfo but found none on %@", parent);
  [parentInfo registerChildViewInfo:info];
}

void ViewReuseUtilities::didHide(UIView *view, CK::Component::MountAnalyticsContext *mountAnalyticsContext) noexcept
{
  CKComponentViewReuseInfo *info = RCGetAssociatedObject_MainThreadAffined(view, &kViewReuseInfoKey);
  RCCAssertNotNil(info, @"Expect to find reuse info on all components-managed views but found none on %@", view);
  [info didHide:mountAnalyticsContext];
}

void ViewReuseUtilities::willUnhide(UIView *view, CK::Component::MountAnalyticsContext *mountAnalyticsContext) noexcept
{
  CKComponentViewReuseInfo *info = RCGetAssociatedObject_MainThreadAffined(view, &kViewReuseInfoKey);
  RCCAssertNotNil(info, @"Expect to find reuse info on all components-managed views but found none on %@", view);
  [info willUnhide:mountAnalyticsContext];
}

@implementation CKComponentViewReuseInfo
{
  // Weak to prevent a retain cycle since the view holds the info strongly via associated objects
  UIView *__weak _view;
  void (^_didEnterReusePoolBlock)(UIView *);
  void (^_willLeaveReusePoolBlock)(UIView *);
  NSMutableArray *_childViewInfos;
  BOOL _hidden;
  BOOL _ancestorHidden;
}

- (instancetype)initWithView:(UIView *)view
      didEnterReusePoolBlock:(void (^)(UIView *))didEnterReusePoolBlock
     willLeaveReusePoolBlock:(void (^)(UIView *))willLeaveReusePoolBlock
{
  if (self = [super init]) {
    _view = view;
    _didEnterReusePoolBlock = didEnterReusePoolBlock;
    _willLeaveReusePoolBlock = willLeaveReusePoolBlock;
  }
  return self;
}

- (void)registerChildViewInfo:(CKComponentViewReuseInfo *)info
{
  if (_childViewInfos == nil) {
    _childViewInfos = [[NSMutableArray alloc] init];
  }
  [_childViewInfos addObject:info];
}

- (void)didHide:(CK::Component::MountAnalyticsContext *)mountAnalyticsContext
{
  if (_hidden) {
    return;
  }
  if (_ancestorHidden == NO && _didEnterReusePoolBlock) {
    _didEnterReusePoolBlock(_view);
  }
  _hidden = YES;

  for (CKComponentViewReuseInfo *descendantInfo in _childViewInfos) {
    [descendantInfo ancestorDidHide];
  }

  if (auto mac = mountAnalyticsContext) {
    mac->viewHides++;
  }
}

- (void)willUnhide:(CK::Component::MountAnalyticsContext *)mountAnalyticsContext
{
  if (!_hidden) {
    return;
  }
  if (_ancestorHidden == NO && _willLeaveReusePoolBlock) {
    _willLeaveReusePoolBlock(_view);
  }
  _hidden = NO;

  for (CKComponentViewReuseInfo *descendantInfo in _childViewInfos) {
    [descendantInfo ancestorWillUnhide];
  }

  if (auto mac = mountAnalyticsContext) {
    mac->viewUnhides++;
  }
}

- (void)ancestorDidHide
{
  if (_ancestorHidden) {
    return;
  }
  if (_hidden == NO && _didEnterReusePoolBlock) {
    _didEnterReusePoolBlock(_view);
  }
  _ancestorHidden = YES;

  if (_hidden) {
    // Since this view is itself already hidden, no need to notify children. They already have _ancestorHidden = YES.
    return;
  }

  for (CKComponentViewReuseInfo *descendantInfo in _childViewInfos) {
    [descendantInfo ancestorDidHide];
  }
}

- (void)ancestorWillUnhide
{
  if (!_ancestorHidden) {
    return;
  }
  if (_hidden == NO && _willLeaveReusePoolBlock) {
    _willLeaveReusePoolBlock(_view);
  }
  _ancestorHidden = NO;

  if (_hidden) {
    // If this view is itself still hidden, the unhiding of an ancestor changes nothing for children.
    return;
  }

  for (CKComponentViewReuseInfo *descendantInfo in _childViewInfos) {
    [descendantInfo ancestorWillUnhide];
  }
}

@end
