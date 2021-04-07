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
#import <ComponentKit/CKBuildTrigger.h>
#import <ComponentKit/RCLayout.h>
#import <ComponentKit/CKOptional.h>
#import <ComponentKit/CKComponentScopeTypes.h>
#import <RenderCoreLayoutCaching/RCComputeRootLayout.h>

@protocol CKAnalyticsListener;
@class CKComponentScopeRoot;

struct RCLayoutResult;
struct RCLayoutCache;

struct CKTreeLayoutCache {
  std::shared_ptr<RCLayoutCache> find(CKComponentScopeRootIdentifier key) const
  {
    auto match = map.find(key);
    if (match != map.end()) {
      return match->second;
    }
    return nullptr;
  }

  void update(CKComponentScopeRootIdentifier key, std::shared_ptr<RCLayoutCache> layoutCache)
  {
    map.emplace(std::make_pair(key, std::move(layoutCache)));
  }
  
private:
  std::unordered_map<CKComponentScopeRootIdentifier, std::shared_ptr<RCLayoutCache>, RC::hash<CKComponentScopeRootIdentifier>> map;
};

/**
 Recursively mounts the layout in the view, returning a set of the mounted components.
 This function is not for a generic use case of mounting every implementation of `CKMountable`, instead it's only for `CKComponent`.
 @param layout The layout to mount, usually returned from a call to -layoutThatFits:parentSize:
 @param view The view in which to mount the layout.
 @param previouslyMountedComponents If a previous layout was mounted, pass the return value of the previous call to
        CKMountComponentLayout; any components that are not present in the new layout will be unmounted.
 @param supercomponent Usually pass nil; if you are mounting a subtree of a layout, pass the parent component so the
        component responder chain can be connected correctly.
 @param analyticsListener analytics listener used to log mount time.
 */
NSSet<id<CKMountable>> *CKMountComponentLayout(const RCLayout &layout,
                                               UIView *view,
                                               NSSet<id<CKMountable>> *previouslyMountedComponents,
                                               id<CKMountable> supercomponent,
                                               id<CKAnalyticsListener> analyticsListener = nil);

struct CKComponentRootLayout { // This is pending renaming
  /** Layout cache for components that have controller. */
  using ComponentLayoutCache = std::unordered_map<id<CKMountable>, RCLayout, RC::hash<id<CKMountable>>, RC::is_equal<id<CKMountable>>>;
  using ComponentsByPredicateMap = std::unordered_map<CKMountablePredicate, std::vector<id<CKMountable>>>;

  CKComponentRootLayout() {}
  explicit CKComponentRootLayout(RCLayout layout)
  : CKComponentRootLayout({layout, nil}, {}, {}) {}
  explicit CKComponentRootLayout(RCLayoutResult layoutResult, ComponentLayoutCache layoutCache, ComponentsByPredicateMap componentsByPredicate)
  : _layoutResult(std::move(layoutResult)), _layoutCache(std::move(layoutCache)), _componentsByPredicate(std::move(componentsByPredicate)) {}

  /**
   This method returns a RCLayout from the cache for the component if it has a controller.
   @param component The component to look for the layout with.
   */
  auto cachedLayoutForComponent(id<CKMountable> component) const
  {
    const auto it = _layoutCache.find(component);
    return it != _layoutCache.end() ? it->second : RCLayout {};
  }

  auto componentsMatchingPredicate(const CKMountablePredicate p) const
  {
    const auto it = _componentsByPredicate.find(p);
    return it != _componentsByPredicate.end() ? it->second : std::vector<id<CKMountable>> {};
  }

  void enumerateCachedLayout(void(^block)(const RCLayout &layout)) const;

  const auto &layout() const { return _layoutResult.layout; }
  const auto &cache() const { return _layoutResult.cache; }
  auto component() const { return _layoutResult.layout.component; }
  auto size() const { return _layoutResult.layout.size; }

private:
  RCLayoutResult _layoutResult;
  ComponentLayoutCache _layoutCache;
  ComponentsByPredicateMap _componentsByPredicate;
};

/**
 Safely computes the layout of the given root component by guarding against nil components.
 @param rootComponent The root component to compute the layout for.
 @param sizeRange The size range to compute the component layout within.
 @param analyticsListener analytics listener used to log layout time.
 @param buildTrigger Indicates the source that triggers this layout computation.
 @param scopeRoot The scope root of the current tree.
 @param layoutCache An optional layout cache for the current tree.

 */
CKComponentRootLayout CKComputeRootComponentLayout(id<CKMountable> rootComponent,
                                                   const CKSizeRange &sizeRange,
                                                   id<CKAnalyticsListener> analyticsListener = nil,
                                                   CK::Optional<CKBuildTrigger> buildTrigger = CK::none,
                                                   CKComponentScopeRoot *scopeRoot = nil,
                                                   std::shared_ptr<RCLayoutCache> layoutCache = nullptr);

/**
 Safely computes the layout of the given component by guarding against nil components.
 @param component The component to compute the layout for.
 @param sizeRange The size range to compute the component layout within.
 @param parentSize The parent size of the component to compute the layout for.
 */
RCLayout CKComputeComponentLayout(id<CKMountable> component,
                                           const CKSizeRange &sizeRange,
                                           const CGSize parentSize);

#endif
