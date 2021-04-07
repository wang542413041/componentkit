/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKRenderHelpers.h"

#import <ComponentKit/CKAnalyticsListener.h>
#import <ComponentKit/CKRenderComponent.h>
#import <ComponentKit/CKComponentContextHelper.h>
#import <ComponentKit/CKComponentInternal.h>
#import <ComponentKit/CKComponentScopeRoot.h>
#import <ComponentKit/CKMutex.h>
#import <ComponentKit/CKOptional.h>
#import <ComponentKit/CKTreeNode.h>
#import <ComponentKit/CKThreadLocalComponentScope.h>
#import <ComponentKit/CKCoalescedSpecSupport.h>

#import "CKTreeNode.h"

namespace CKRenderInternal {

  // Reuse the previous component generation and its component tree and notify the previous component about it.
  static auto reusePreviousComponent(id<CKRenderComponentProtocol> component,
                                     __strong id<CKComponentProtocol> *childComponent,
                                     CKTreeNode *node,
                                     CKTreeNode *previousNode,
                                     const CKBuildComponentTreeParams &params,
                                     CKRenderDidReuseComponentBlock didReuseBlock) -> void {

    // Update the previous component.
    auto const previousComponent = (id<CKRenderWithChildComponentProtocol>)previousNode.component;

    // Update the render node of the component reuse.
    [node reusePreviousNode:previousNode inScopeRoot:params.scopeRoot];

    if (childComponent != nullptr) {
      // Link the previous child component to the the new component.
      *childComponent = previousComponent.child;
    }

    if (didReuseBlock) {
      didReuseBlock(previousComponent);
    }
    // Notify the new component about the reuse of the previous component.
    [component didReuseComponent:previousComponent];

    // Notify scope root listener
    [params.scopeRoot.analyticsListener didReuseNode:node inScopeRoot:params.scopeRoot fromPreviousScopeRoot:params.previousScopeRoot];
  }

  // Reuse the previous component generation and its component tree and notify the previous component about it.
  static auto reusePreviousComponent(id<CKRenderComponentProtocol> component,
                                     __strong id<CKComponentProtocol> *childComponent,
                                     CKTreeNode *node,
                                     CKTreeNode *parent,
                                     CKTreeNode *previousParent,
                                     const CKBuildComponentTreeParams &params,
                                     CKRenderDidReuseComponentBlock didReuseBlock) -> BOOL {
    auto const previousNode = [previousParent childForComponentKey:node.componentKey];
    if (previousNode) {
      CKRenderInternal::reusePreviousComponent(component, childComponent, node, previousNode, params, didReuseBlock);
      return YES;
    }
    return NO;
  }

  // Check if shouldComponentUpdate returns `NO`; if it does, reuse the previous component generation and its component tree and notify the previous component about it.
  static auto reusePreviousComponentIfComponentsAreEqual(id<CKRenderComponentProtocol> component,
                                                         __strong id<CKComponentProtocol> *childComponent,
                                                         CKTreeNode *node,
                                                         CKTreeNode *parent,
                                                         CKTreeNode *previousParent,
                                                         const CKBuildComponentTreeParams &params,
                                                         CKRenderDidReuseComponentBlock didReuseBlock) -> BOOL {
    auto const previousNode = [previousParent childForComponentKey:node.componentKey];
    auto const previousComponent = (id<CKRenderComponentProtocol>)previousNode.component;
    // If there is no previous compononet, there is nothing to reuse.
    if (previousComponent) {
      // We check if the component node is dirty in the **previous** scope root.
      auto const& dirtyNodeIdsForPropsUpdates = params.previousScopeRoot.rootNode.dirtyNodeIdsForPropsUpdates();
      auto const dirtyNodeId = dirtyNodeIdsForPropsUpdates.find(node.nodeIdentifier);
      if (dirtyNodeId == dirtyNodeIdsForPropsUpdates.end()) {
        [params.systraceListener willCheckShouldComponentUpdate:component.typeName];
        auto const shouldComponentUpdate = [component shouldComponentUpdate:previousComponent];
        [params.systraceListener didCheckShouldComponentUpdate:component.typeName];
        if (!shouldComponentUpdate) {
          CKRenderInternal::reusePreviousComponent(component, childComponent, node, previousNode, params, didReuseBlock);
          return YES;
        }
      }
    }
    return NO;
  }

  static auto reusePreviousComponentForSingleChild(CKTreeNode *node,
                                                   id<CKRenderWithChildComponentProtocol> component,
                                                   __strong id<CKComponentProtocol> *childComponent,
                                                   CKTreeNode *parent,
                                                   CKTreeNode *previousParent,
                                                   const CKBuildComponentTreeParams &params,
                                                   BOOL parentHasStateUpdate,
                                                   CKRenderDidReuseComponentBlock didReuseBlock) -> BOOL {

    // If there is no previous parent or no childComponent, we bail early.
    if (previousParent == nil || childComponent == nullptr) {
      return NO;
    }

    // Disable any sort of reuse when environmental changes
    if (params.buildTrigger & CKBuildTriggerEnvironmentUpdate) {
      return NO;
    }

    if (params.buildTrigger & CKBuildTriggerStateUpdate) {
      // State update branch - only state updates or coalesced state & props update.
      // Check if the tree node is not dirty (not in a branch of a state update).
      auto const dirtyNodeId = params.treeNodeDirtyIds.find(node.nodeIdentifier);
      if (dirtyNodeId == params.treeNodeDirtyIds.end()) {
        // We reuse the component without checking `shouldComponentUpdate:` in the following conditions:
        // 1. The component is not dirty (on a state update branch)
        // 2. No direct parent has a state update
        // 3. Not a coalesced state & props update.
        if (!parentHasStateUpdate &&
            (params.buildTrigger & CKBuildTriggerPropsUpdate) == 0) {
          // Faster state update optimizations.
          return CKRenderInternal::reusePreviousComponent(component, childComponent, node, parent, previousParent, params, didReuseBlock);
        }
        // We fallback to the props update optimization in the follwing case:
        // - The component is not dirty, but the parent has a state update or tree props were updated.
        return (CKRenderInternal::reusePreviousComponentIfComponentsAreEqual(component, childComponent, node, parent, previousParent, params, didReuseBlock));
      }
    } else if (params.buildTrigger & CKBuildTriggerPropsUpdate) {
      // Will be used for coalesced props & state updates too.
      return CKRenderInternal::reusePreviousComponentIfComponentsAreEqual(component, childComponent, node, parent, previousParent, params, didReuseBlock);
    }

    return NO;
  }


static auto didBuildComponentTree(CKTreeNode *node,
                                  id<CKComponentProtocol> component,
                                  const CKBuildComponentTreeParams &params) -> void {

    // Context support
    CKComponentContextHelper::didBuildComponentTree(component);

    // Props updates and context support
    params.scopeRoot.rootNode.didBuildComponentTree();

    // Systrace logging
    [params.systraceListener didBuildComponent:component.typeName];
  }

}

namespace CKRender {
  namespace ComponentTree {
    namespace Iterable {
    auto build(id<CKComponentProtocol> component,
               CKTreeNode *parent,
               CKTreeNode *_Nullable previousParent,
               const CKBuildComponentTreeParams &params,
               BOOL parentHasStateUpdate) -> void
    {
      RCCAssertNotNil(component, @"component cannot be nil");
      RCCAssertNotNil(parent, @"parent cannot be nil");

      // Check if the component already has a tree node.
      CKTreeNode *node = component.treeNode;

      [node linkComponent:component toParent:parent inScopeRoot:params.scopeRoot];

      unsigned int numberOfChildren = [component numberOfChildren];
      if (numberOfChildren == 0) {
        return;
      }

      // The assumption was that if there was no previous parent this node couldn't
      // possibly have a state update. In reality this can happen if the previous generation
      // didn't contain a render component (thus the second phase wouldn't have been performed
      // and component aren't linked). A state update on a first generation's non reusable
      // component introducing a reusable component would lead to an incorrect `parentHasStateUpdate`
      // value.
      id previousParentOrComponent = params.previousScopeRoot.hasRenderComponentInTree == NO ? (id)component : previousParent;

      // Update the `parentHasStateUpdate` param for Faster state/props updates.
      // TODO: Share this value with the value precomputed in the scope
      parentHasStateUpdate = parentHasStateUpdate ||
      (params.buildTrigger == CKBuildTriggerStateUpdate &&
       CKRender::componentHasStateUpdate(node,
                                         previousParentOrComponent,
                                         params.buildTrigger,
                                         params.stateUpdates));

      // If there is a node, we update the parents' pointers to the next level in the tree.
      if (node) {
        parent = node;
        previousParent = [previousParent childForComponentKey:[node componentKey]];

        // Report information to `debugAnalyticsListener`.
        if (numberOfChildren == 1 && params.shouldCollectTreeNodeCreationInformation) {
          [params.scopeRoot.analyticsListener didBuildTreeNodeForPrecomputedChild:component
                                                                             node:node
                                                                           parent:parent
                                                                           params:params
                                                             parentHasStateUpdate:parentHasStateUpdate];
        }
      }

      for (int i=0; i<numberOfChildren; i++) {
        auto const childComponent = (id<CKComponentProtocol>)[component childAtIndex:i];
        if (childComponent) {
          [childComponent buildComponentTree:parent
                              previousParent:previousParent
                                      params:params
                        parentHasStateUpdate:parentHasStateUpdate];
        }
      }
    }
  }

    namespace Render {

      struct ThreadLocalStorageSupport {
        ThreadLocalStorageSupport(const CKComponentScopePair& pair) : _pair(pair), _threadLocalScope(CKThreadLocalComponentScope::currentScope()) {
          if (auto const threadLocalScope = _threadLocalScope) {
            // Push the new pair into the thread local.
            threadLocalScope->push(_pair);
          } else {
            RCCFailAssert(@"No TLS while building a render component!?");
          }
        }
        ~ThreadLocalStorageSupport() {
          if (auto const threadLocalScope = _threadLocalScope) {
            RCCAssert(!threadLocalScope->stack.empty() && threadLocalScope->stack.top().node == _pair.node, @"top.node (%@) is not equal to node (%@)", threadLocalScope->stack.top().node, _pair.node);

            // Pop the top element of the stack.
            threadLocalScope->pop();
          }
        }

        ThreadLocalStorageSupport(const ThreadLocalStorageSupport&) = delete;

       private:
        const CKComponentScopePair& _pair;
        CKThreadLocalComponentScope *_threadLocalScope;
      };

      auto build(id<CKRenderWithChildComponentProtocol> component,
                 __strong id<CKComponentProtocol> *childComponent,
                 CKTreeNode *parent,
                 CKTreeNode *_Nullable previousParent,
                 const CKBuildComponentTreeParams &params,
                 BOOL parentHasStateUpdate,
                 CKRenderDidReuseComponentBlock didReuseBlock) -> CKTreeNode *
      {
        RCCAssertNotNil(component, @"component cannot be nil");
        RCCAssertNotNil(parent, @"parent cannot be nil");

        // Context support
        CKComponentContextHelper::willBuildComponentTree(component);

        const auto pair = [CKTreeNode childPairForComponent:component
                                                     parent:parent
                                             previousParent:previousParent
                                                  scopeRoot:params.scopeRoot
                                               stateUpdates:params.stateUpdates];

        ThreadLocalStorageSupport tlsSupport(pair);

        auto const node = pair.node;

        // Faster Props updates and context support
        params.scopeRoot.rootNode.willBuildComponentTree(node);

        // Systrace logging
        [params.systraceListener willBuildComponent:component.typeName];

        // Faster state/props optimizations require previous parent.
        if (CKRenderInternal::reusePreviousComponentForSingleChild(node, component, childComponent, parent, previousParent, params, parentHasStateUpdate, didReuseBlock)) {
          CKRenderInternal::didBuildComponentTree(node, component, params);
          return node;
        }

        // Update the `parentHasStateUpdate` param for Faster state/props updates.
        parentHasStateUpdate = parentHasStateUpdate ||
        (params.buildTrigger == CKBuildTriggerStateUpdate &&
         CKRender::componentHasStateUpdate(node,
                                           previousParent,
                                           params.buildTrigger,
                                           params.stateUpdates));

        CK::CoalescedWillRenderRenderComponent(parentHasStateUpdate);

        auto const child = [component render:node.state];
        if (child) {
          if (childComponent != nullptr) {
            // Set the link between the parent to its child.
            *childComponent = child;
          }
          // Call build component tree on the child component.
          [child buildComponentTree:node
                     previousParent:[previousParent childForComponentKey:[node componentKey]]
                             params:params
               parentHasStateUpdate:parentHasStateUpdate];
        }

        CK::CoalescedDidRenderRenderComponent();
        CKRenderInternal::didBuildComponentTree(node, component, params);

        return node;
      }
    }

    namespace Root {
      auto build(id<CKComponentProtocol> component, const CKBuildComponentTreeParams &params) -> void {
        auto const rootNode = params.scopeRoot.rootNode.node();

        if (component) {
          // Build the component tree from the render function.
          [component buildComponentTree:rootNode
                         previousParent:params.previousScopeRoot.rootNode.node()
                                 params:params
                   parentHasStateUpdate:NO];
        }
      }
    }
  }

  namespace ScopeHandle {
    namespace Render {
      auto create(id<CKRenderComponentProtocol> component,
                  CKTreeNode *previousNode,
                  CKComponentScopeRoot *scopeRoot,
                  const CKComponentStateUpdateMap &stateUpdates) -> CKComponentScopeHandle*
      {
        // If there is a previous node, we just duplicate the scope handle.
        if (previousNode) {
          return [previousNode.scopeHandle newHandleWithStateUpdates:stateUpdates];
        } else {
          // The component needs a scope handle in few cases:
          // 1. Has an initial state
          // 2. Returns `YES` from `requiresScopeHandle`
          id initialState = [component initialState];
          if (initialState != CKTreeNodeEmptyState() || component.requiresScopeHandle) {
            return [[CKComponentScopeHandle alloc] initWithListener:scopeRoot.listener
                                                     rootIdentifier:scopeRoot.globalIdentifier
                                                  componentTypeName:component.typeName
                                                       initialState:initialState];
          }
        }
        return nil;
      }
    }
  }

  auto componentHasStateUpdate(__unsafe_unretained CKTreeNode *node,
                               __unsafe_unretained id previousParent,
                               CKBuildTrigger buildTrigger,
                               const CKComponentStateUpdateMap& stateUpdates) -> BOOL {
    const auto scopeHandle = node.scopeHandle;
    if (scopeHandle != nil && previousParent != nil && buildTrigger == CKBuildTriggerStateUpdate) {
      return stateUpdates.find(scopeHandle) != stateUpdates.end();
    }
    return NO;
  }

  auto markTreeNodeDirtyIdsFromNodeUntilRoot(CKTreeNodeIdentifier nodeIdentifier,
                                             const CKRootTreeNode &previousRootNode,
                                             CKTreeNodeDirtyIds &treeNodesDirtyIds) -> void
  {
    CKTreeNodeIdentifier currentNodeIdentifier = nodeIdentifier;
    while (currentNodeIdentifier != 0) {
      auto const insertPair = treeNodesDirtyIds.insert(currentNodeIdentifier);
      // If we got to a node that is already in the set, we can stop as the path to the root is already dirty.
      if (insertPair.second == false) {
        break;
      }
      auto const parentNode = previousRootNode.parentForNodeIdentifier(currentNodeIdentifier);
      RCCAssert((parentNode || nodeIdentifier == currentNodeIdentifier),
                @"The next parent cannot be nil unless it's a root component.");
      currentNodeIdentifier = parentNode.nodeIdentifier;
    }
  }


  auto treeNodeDirtyIdsFor(CKComponentScopeRoot *previousRoot,
                           const CKComponentStateUpdateMap &stateUpdates,
                           CKBuildTrigger buildTrigger) -> CKTreeNodeDirtyIds
  {
    CKTreeNodeDirtyIds treeNodesDirtyIds;
    // Compute the dirtyNodeIds in case of a state update only.
    if (buildTrigger == CKBuildTriggerStateUpdate) {
      for (auto const & stateUpdate : stateUpdates) {
        CKRender::markTreeNodeDirtyIdsFromNodeUntilRoot(stateUpdate.first.treeNodeIdentifier, previousRoot.rootNode, treeNodesDirtyIds);
      }
    }
    return treeNodesDirtyIds;
  }
}
