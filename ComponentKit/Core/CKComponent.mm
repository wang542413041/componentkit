/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKComponent.h"
#import "CKComponentControllerInternal.h"
#import "CKComponentInternal.h"
#import "CKComponentSubclass.h"

#import <ComponentKit/CKAnalyticsListener.h>
#import <ComponentKit/CKAssert.h>
#import <ComponentKit/CKArgumentPrecondition.h>
#import <ComponentKit/CKBuildComponent.h>
#import <ComponentKit/CKComponentScopeEnumeratorProvider.h>
#import <ComponentKit/CKComponentContextHelper.h>
#import <ComponentKit/CKFatal.h>
#import <ComponentKit/CKInternalHelpers.h>
#import <ComponentKit/CKMacros.h>
#import <ComponentKit/CKTreeNodeProtocol.h>
#import <ComponentKit/CKInternalHelpers.h>
#import <ComponentKit/CKWeakObjectContainer.h>
#import <ComponentKit/CKComponentDescriptionHelper.h>
#import <ComponentKit/CKMountableHelpers.h>
#import <ComponentKit/CKComponentSize_SwiftBridge+Internal.h>
#import <ComponentKit/CKComponentViewConfiguration_SwiftBridge+Internal.h>

#import "CKComponent+UIView.h"
#import "CKComponentAccessibility.h"
#import "CKComponentAnimation.h"
#import "CKComponentController.h"
#import "CKComponentDebugController.h"
#import "CKComponentLayout.h"
#import "CKComponentScopeHandle.h"
#import "CKComponentViewConfiguration.h"
#import "CKMountAnimationGuard.h"
#import "ComponentLayoutContext.h"
#import "CKThreadLocalComponentScope.h"
#import "CKComponentScopeRoot.h"
#import "CKRenderHelpers.h"
#import "CKComponentCreationValidation.h"
#import "CKSizeAssert.h"

CGFloat const kCKComponentParentDimensionUndefined = NAN;
CGSize const kCKComponentParentSizeUndefined = {kCKComponentParentDimensionUndefined, kCKComponentParentDimensionUndefined};

@implementation CKComponent
{
  id<CKTreeNodeProtocol> _treeNode;
  CKComponentViewConfiguration _viewConfiguration;

  /** Only non-null while mounted. */
  std::unique_ptr<CKMountInfo> _mountInfo;
}

#if DEBUG
+ (void)initialize
{
  if (self != [CKComponent class]) {
    CKAssert(!CKSubclassOverridesInstanceMethod([CKComponent class], self, @selector(layoutThatFits:parentSize:)),
             @"%@ overrides -layoutThatFits:parentSize: which is not allowed. Override -computeLayoutThatFits: "
             "or -computeLayoutThatFits:restrictedToSize:relativeToParentSize: instead.",
             self);
  }
}
#endif

+ (instancetype)newWithView:(const CKComponentViewConfiguration &)view size:(const CKComponentSize &)size
{
  return [[self alloc] initWithView:view size:size];
}

+ (instancetype)new
{
  return [self newWithView:{} size:{}];
}

- (instancetype)init
{
  return [self initWithView:{} size:{}];
}

- (instancetype)initWithViewConfig:(CKComponentViewConfiguration_SwiftBridge *)viewConfig
                     componentSize:(CKComponentSize_SwiftBridge *)size
{
  return [self initWithView:viewConfig.viewConfig size:size.componentSize];
}

- (instancetype)initWithView:(const CKComponentViewConfiguration &)view
                        size:(const CKComponentSize &)size
{
  if (self = [super init]) {
    _viewConfiguration = view;
    _size = size;

    [self didFinishComponentInitialization];
  }
  return self;
}

- (void)dealloc
{
  // Since the component and its view hold strong references to each other, this should never happen!
  CKAssert(_mountInfo == nullptr, @"%@ must be unmounted before dealloc", self.className);
}

- (NSString *)description
{
  const char *const className = class_getName(self.class);
  const char *const typeName = self.typeName;
  return (strcmp(className, self.typeName) == 0)
  ? [NSString stringWithFormat:@"<%s: %p>", className, self]
  : [NSString stringWithFormat:@"<%s: %p (%s)>", typeName, self, className];
}

- (void)didFinishComponentInitialization
{
  CKValidateComponentCreation();
  _treeNode = CK::TreeNode::nodeForComponent(self);
}

- (BOOL)hasAnimations
{
  return CKSubclassOverridesInstanceMethod([CKComponent class], [self class], @selector(animationsFromPreviousComponent:));
}

- (BOOL)hasBoundsAnimations
{
  return CKSubclassOverridesInstanceMethod([CKComponent class], [self class], @selector(boundsAnimationFromPreviousComponent:));
}

- (BOOL)controllerOverridesDidPrepareLayout
{
  const Class<CKComponentControllerProtocol> controllerClass = [[self class] controllerClass];
  return CKSubclassOverridesInstanceMethod([CKComponentController class],
                                  controllerClass,
                                  @selector(didPrepareLayout:forComponent:));
}

- (id<CKComponentControllerProtocol>)buildController
{
  return [[(Class)[self.class controllerClass] alloc] initWithComponent:self];
}

- (const CKComponentViewConfiguration &)viewConfiguration
{
  return _viewConfiguration;
}

- (void)setViewConfiguration:(const CKComponentViewConfiguration &)viewConfiguration
{
  CKAssert(_viewConfiguration.isDefaultConfiguration(), @"Component(%@) already has '_viewConfiguration'.", self);
  _viewConfiguration = viewConfiguration;
}

- (CKComponentScopeHandle *)scopeHandle
{
  return _treeNode.scopeHandle;
}

- (CKComponentViewContext)viewContext
{
  CKAssertMainThread();
  return _mountInfo ? _mountInfo->viewContext : CKComponentViewContext();
}

- (void)acquireTreeNode:(id<CKTreeNodeProtocol>)treeNode
{
  _treeNode = treeNode;
}

- (id<CKTreeNodeProtocol>)treeNode
{
  return _treeNode;
}

#pragma mark - ComponentTree

- (void)buildComponentTree:(id<CKTreeNodeWithChildrenProtocol>)parent
            previousParent:(id<CKTreeNodeWithChildrenProtocol> _Nullable)previousParent
                    params:(const CKBuildComponentTreeParams &)params
      parentHasStateUpdate:(BOOL)parentHasStateUpdate
{
  CKRender::ComponentTree::Iterable::build(self, parent, previousParent, params, parentHasStateUpdate);
}

#pragma mark - Mounting and Unmounting

- (CK::Component::MountResult)mountInContext:(const CK::Component::MountContext &)context
                                      layout:(const CKComponentLayout &)layout
                              supercomponent:(CKComponent *)supercomponent
{
  CKCAssertWithCategory([NSThread isMainThread], self.className, @"This method must be called on the main thread");

  // Taking a const ref to a temporary extends the lifetime of the temporary to the lifetime of the const ref
  const CKComponentViewConfiguration &viewConfiguration = CK::Component::Accessibility::IsAccessibilityEnabled() ? CK::Component::Accessibility::AccessibleViewConfiguration(_viewConfiguration) : _viewConfiguration;

  if (_mountInfo == nullptr) {
    _mountInfo.reset(new CKMountInfo());
  }
  _mountInfo->supercomponent = supercomponent;

  CKComponentController *controller = _treeNode.scopeHandle.controller;
  [controller componentWillMount:self];

  const CK::Component::MountContext &effectiveContext = [CKComponentDebugController debugMode]
  ? CKDebugMountContext([self class], context, _viewConfiguration, layout.size) : context;

  UIView *v = effectiveContext.viewManager->viewForConfiguration([self class], viewConfiguration);
  if (v) {
    CKComponent *currentMountedComponent = CKMountedComponentForView(v);
    CKMountAnimationGuard g(currentMountedComponent, self, context, _viewConfiguration);
    if (_mountInfo->view != v) {
      [self _relinquishMountedView];     // First release our old view
      [currentMountedComponent unmount]; // Then unmount old component (if any) from the new view
      CKSetMountedComponentForView(v, self);
      CK::Component::AttributeApplicator::apply(v, viewConfiguration);
      [controller component:self didAcquireView:v];
      _mountInfo->view = v;
    } else {
      CKAssert(currentMountedComponent == self, @"");
    }

    @try {
      CKSetViewPositionAndBounds(v, context, layout.size);
    } @catch (NSException *exception) {
      CKCFatalWithCategory(self.className,
                           @"Raised %@ during mount: %@\nBacktrace: %@\nChildren: %@",
                           exception.name,
                           exception.reason,
                           CKComponentBacktraceDescription(CKComponentGenerateBacktrace(supercomponent)),
                           CKComponentChildrenDescription(layout.children));
    }

    _mountInfo->viewContext = {v, {{0,0}, v.bounds.size}};

    return {.mountChildren = YES, .contextForChildren = effectiveContext.childContextForSubview(v, g.didBlockAnimations)};
  } else {
    CKCAssertWithCategory(_mountInfo->view == nil, self.className,
                          @"%@ should not have a mounted %@ after previously being mounted without a view.\n%@",
                          self.className, [_mountInfo->view class], CKComponentBacktraceDescription(CKComponentGenerateBacktrace(self)));
    _mountInfo->viewContext = {effectiveContext.viewManager->view, {effectiveContext.position, layout.size}};

    return {.mountChildren = YES, .contextForChildren = effectiveContext};
  }
}

- (NSString *)backtraceStackDescription
{
  return CKComponentBacktraceStackDescription(CKComponentGenerateBacktrace(self));
}

- (void)unmount
{
  CKAssertMainThread();
  if (_mountInfo != nullptr) {
    CKComponentController *const controller = _treeNode.scopeHandle.controller;
    [controller componentWillUnmount:self];
    [self _relinquishMountedView];
    _mountInfo.reset();
    [controller componentDidUnmount:self];
  }
}

- (void)_relinquishMountedView
{
  CKAssertMainThread();
  CKAssert(_mountInfo != nullptr, @"_mountInfo should not be null");
  if (_mountInfo != nullptr) {
    UIView *view = _mountInfo->view;
    if (view) {
      CKAssert(CKMountedComponentForView(view) == self, @"");
      [(CKComponentController *)_treeNode.scopeHandle.controller component:self willRelinquishView:view];
      CKSetMountedComponentForView(view, nil);
      _mountInfo->view = nil;
    }
  }
}

- (void)childrenDidMount
{
  [(CKComponentController *)_treeNode.scopeHandle.controller componentDidMount:self];
}

#pragma mark - Animation

- (std::vector<CKComponentAnimation>)animationsOnInitialMount
{
  return {};
}

- (std::vector<CKComponentAnimation>)animationsFromPreviousComponent:(CKComponent *)previousComponent
{
  return {};
}

- (CKComponentBoundsAnimation)boundsAnimationFromPreviousComponent:(CKComponent *)previousComponent
{
  return {};
}

- (std::vector<CKComponentFinalUnmountAnimation>)animationsOnFinalUnmount
{
  return {};
}

- (UIView *)viewForAnimation
{
  CKAssertMainThread();
  return _mountInfo ? _mountInfo->view : nil;
}

#pragma mark - Layout

- (CKComponentLayout)layoutThatFits:(CKSizeRange)constrainedSize parentSize:(CGSize)parentSize
{
#if CK_ASSERTIONS_ENABLED
  const CKComponentContext<CKComponentCreationValidationContext> validationContext([[CKComponentCreationValidationContext alloc] initWithSource:CKComponentCreationValidationSourceLayout]);
#endif

  CKAssertSizeRange(constrainedSize);
  CK::Component::LayoutContext context(self, constrainedSize);
  auto const systraceListener = context.systraceListener;
  [systraceListener willLayoutComponent:self];

  CKComponentLayout layout = [self computeLayoutThatFits:constrainedSize
                                        restrictedToSize:_size
                                    relativeToParentSize:parentSize];

#if CK_ASSERTIONS_ENABLED
  // If this component has children in its layout, this means that it's not a real leaf component.
  // As a result, the infrastructure won't call `buildComponentTree:` on the component's children and can affect the render process.
  if (self.superclass == [CKComponent class] && layout.children != nullptr && layout.children->size() > 0) {
    const auto overridesIterableMethods =
    CKSubclassOverridesInstanceMethod([CKComponent class], self.class, @selector(childAtIndex:)) &&
    CKSubclassOverridesInstanceMethod([CKComponent class], self.class, @selector(numberOfChildren));
    CKAssertWithCategory(overridesIterableMethods,
                         self.className,
                         @"%@ is subclassing CKComponent directly, you need to subclass CKLayoutComponent instead. "
                         "Context: we’re phasing out CKComponent subclasses for in favor of CKLayoutComponent subclasses. "
                         "While this is still kinda OK for leaf components, things start to break when you introduce a CKComponent subclass with children.",
                         self.className);
  }

  CKAssert(layout.component == self, @"Layout computed by %@ should return self as component, but returned %@",
           self.className, layout.component.className);

  CKAssertResolvedSize(_size, parentSize);
  CKSizeRange resolvedRange __attribute__((unused)) = constrainedSize.intersect(_size.resolve(parentSize));
  CKAssertSizeRange(resolvedRange);
  CKAssertWithCategory(CKIsGreaterThanOrEqualWithTolerance(resolvedRange.max.width, layout.size.width)
                       && CKIsGreaterThanOrEqualWithTolerance(layout.size.width, resolvedRange.min.width)
                       && CKIsGreaterThanOrEqualWithTolerance(resolvedRange.max.height,layout.size.height)
                       && CKIsGreaterThanOrEqualWithTolerance(layout.size.height,resolvedRange.min.height),
                       self.className,
                       @"Computed size %@ for %@ does not fall within constrained size %@\n%@",
                       NSStringFromCGSize(layout.size), self.className, resolvedRange.description(),
                       CK::Component::LayoutContext::currentStackDescription());
#endif

  [systraceListener didLayoutComponent:self];

  return layout;
}

- (CKComponentLayout)computeLayoutThatFits:(CKSizeRange)constrainedSize
                          restrictedToSize:(const CKComponentSize &)size
                      relativeToParentSize:(CGSize)parentSize
{
  CKAssertResolvedSize(_size, parentSize);
  CKSizeRange resolvedRange = constrainedSize.intersect(_size.resolve(parentSize));
  return [self computeLayoutThatFits:resolvedRange];
}

- (CKComponentLayout)computeLayoutThatFits:(CKSizeRange)constrainedSize
{
  return {self, constrainedSize.min};
}

#pragma mark - Responder

- (id)nextResponder
{
  return _treeNode.scopeHandle.controller ?: [self nextResponderAfterController];
}

- (id)nextResponderAfterController
{
  CKAssertMainThread();
  if (_mountInfo && _mountInfo->supercomponent) {
    return _mountInfo->supercomponent;
  }
  return [self rootComponentMountedView];
}

- (id)targetForAction:(SEL)action withSender:(id)sender
{
  return [self canPerformAction:action withSender:sender] ? self : [[self nextResponder] targetForAction:action withSender:sender];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
  return [self respondsToSelector:action];
}

// Because only the root component in each mounted tree will have a non-nil rootComponentMountedView, we use Obj-C
// associated objects to save the memory overhead of storing such a pointer on every single CKComponent instance in
// the app. With tens of thousands of component instances, this adds up to several KB.
static void *kRootComponentMountedViewKey = &kRootComponentMountedViewKey;

- (void)setRootComponentMountedView:(UIView *)rootComponentMountedView
{
  ck_objc_setNonatomicAssociatedWeakObject(self, kRootComponentMountedViewKey, rootComponentMountedView);
}

- (UIView *)rootComponentMountedView
{
  return ck_objc_getAssociatedWeakObject(self, kRootComponentMountedViewKey);
}

#pragma mark - CKMountable

- (unsigned int)numberOfChildren
{
  return 0;
}

- (id<CKMountable>)childAtIndex:(unsigned int)index
{
  return nil;
}

#pragma mark - CKComponentProtocol

+ (CKComponentCoalescingMode)coalescingMode {
  return CKComponentCoalescingModeNone;
}

+ (Class<CKComponentControllerProtocol>)controllerClass
{
  const Class componentClass = self;

  if (componentClass == [CKComponent class]) {
    return Nil; // Don't create root CKComponentControllers as it does nothing interesting.
  }

  CKAssertWithCategory(!NSClassFromString([NSStringFromClass(componentClass) stringByAppendingString:@"Controller"]),
                       [self class], @"Should override + (Class<CKComponentControllerProtocol>)controllerClass to return its controllerClass");
  return Nil;
}

+ (id)initialState
{
  return nil;
}

#pragma mark - State

- (void)updateState:(id (^)(id))updateBlock mode:(CKUpdateMode)mode
{
  CKAssertWithCategory(_treeNode.scopeHandle != nil, self.className, @"A component without state cannot update its state.");
  CKAssertWithCategory(updateBlock != nil, self.className, @"Cannot enqueue component state modification with a nil update block.");
  [_treeNode.scopeHandle updateState:updateBlock metadata:{} mode:mode];
}

- (CKComponentController *)controller
{
  return _treeNode.scopeHandle.controller;
}

- (id<NSObject>)uniqueIdentifier
{
  return _treeNode ? @(_treeNode.scopeHandle.globalIdentifier) : nil;
}

-(id<CKComponentScopeEnumeratorProvider>)scopeEnumeratorProvider
{
  CKThreadLocalComponentScope *currentScope = CKThreadLocalComponentScope::currentScope();
  if (currentScope == nullptr) {
    return nil;
  }

  return currentScope->newScopeRoot;
}

- (UIView *)mountedView
{
  return _mountInfo ? _mountInfo->view : nil;
}

- (CKMountInfo)mountInfo
{
  if (_mountInfo) {
    return *_mountInfo.get();
  }
  return {};
}

- (id)state
{
  return _treeNode.scopeHandle.state;
}

- (NSString *)className
{
  return [NSString stringWithUTF8String:self.typeName];
}

- (const char *)typeName
{
  return class_getName(self.class);
}

@end
