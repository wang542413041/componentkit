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

#import <ComponentKit/CKBuildComponent.h>
#import <ComponentKit/CKComponentInternal.h>
#import <ComponentKit/CKRootTreeNode.h>

@protocol CKRenderWithChildComponentProtocol;

using CKRenderDidReuseComponentBlock = void(^)(id<CKRenderComponentProtocol>);

namespace CKRender {
  namespace ComponentTree {

    namespace Iterable {
    /**
     Build component tree for a `CKComponentProtocol` component.
     This should be called when a component, on initialization, receives its child component from the outside and it's not meant to be converted to a render component.

     @param component The component at the head of the component tree.
     @param parent The current parent tree node of the component in input.
     @param previousParent The previous generation of the parent tree node of the component in input.
     @param params Collection of parameters to use to properly setup build component tree step.
     @param parentHasStateUpdate Flag used to run optimizations at component tree build time. `YES` if the input parent received a state update.
     */
      auto build(id<CKComponentProtocol> component,
                 CKTreeNode *parent,
                 CKTreeNode *previousParent,
                 const CKBuildComponentTreeParams &params,
                 BOOL parentHasStateUpdate) -> void;
  }

    namespace Render {
      /**
       Build component tree for *render* component.

       @param component The *render* component at the head of the component tree.
       @param childComponent The child component owned by the component in input.
       @param parent The current parent tree node of the component in input.
       @param previousParent The previous generation of the parent tree node of the component in input.
       @param params Collection of parameters to use to properly setup build component tree step.
       @param parentHasStateUpdate Flag used to run optimizations at component tree build time. `YES` if the input parent received a state update.
       @param didReuseBlock Will be called in case that the component from the previous generation has been reused.
       */
      auto build(id<CKRenderWithChildComponentProtocol> component,
                 __strong id<CKComponentProtocol> *childComponent,
                 CKTreeNode *parent,
                 CKTreeNode *previousParent,
                 const CKBuildComponentTreeParams &params,
                 BOOL parentHasStateUpdate,
                 CKRenderDidReuseComponentBlock didReuseBlock = nil) -> CKTreeNode *;
    }

    namespace Root {
      /**
      Builds the component tree from a root component.

      @param component The root component of the tree.
      @param params Collection of parameters to use to properly setup build component tree step.
      */
      auto build(id<CKComponentProtocol> component, const CKBuildComponentTreeParams &params) -> void;
    }
  }

  namespace ScopeHandle {
    namespace Render {
      /**
       Create a scope handle for Render component (if needed).

       @param component Render component which the scope handle will be created for.
       @param previousNode The prevoious equivalent tree node.
       @param stateUpdates The state updates map of this component generation.
       */
      auto create(id<CKRenderComponentProtocol> component,
                  CKTreeNode *previousNode,
                  CKComponentScopeRoot *scopeRoot,
                  const CKComponentStateUpdateMap &stateUpdates) -> CKComponentScopeHandle*;
    }
  }

  /**
   @return `YES` if the component of the node has a state update, `NO` otherwise.
   */
  auto componentHasStateUpdate(__unsafe_unretained CKTreeNode *node,
                               __unsafe_unretained id previousParent,
                               CKBuildTrigger buildTrigger,
                               const CKComponentStateUpdateMap& stateUpdates) -> BOOL;

  /**
   Mark all the dirty nodes, on a path from an existing node up to the root node in the passed CKTreeNodeDirtyIds set.
   */
  auto markTreeNodeDirtyIdsFromNodeUntilRoot(CKTreeNodeIdentifier nodeIdentifier,
                                             const CKRootTreeNode &previousRootNode,
                                             CKTreeNodeDirtyIds &treeNodesDirtyIds) -> void;

  /**
   @return A collection of tree node marked as dirty if any. An empty collection otherwise.
   */
  auto treeNodeDirtyIdsFor(CKComponentScopeRoot *previousRoot,
                           const CKComponentStateUpdateMap &stateUpdates,
                           CKBuildTrigger buildTrigger) -> CKTreeNodeDirtyIds;
}

#endif
