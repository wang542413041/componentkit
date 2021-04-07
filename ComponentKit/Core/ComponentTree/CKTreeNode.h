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

#import <Foundation/Foundation.h>

#import <ComponentKit/CKComponentScopeTypes.h>
#import <ComponentKit/CKComponentScopeRoot.h>
#import <ComponentKit/CKComponentScopeHandle.h>
#import <ComponentKit/CKTreeNodeProtocol.h>
#import <ComponentKit/CKTreeNodeComponentKey.h>

@protocol CKRenderComponentProtocol;

#if CK_NOT_SWIFT

namespace CK {
namespace TreeNode {
  /**
  This function looks to see if the currently defined scope matches that of the given component; if so it returns the
  node corresponding to the current scope. Otherwise it returns nil.
  This is only meant to be called when constructing a component and as part of the implementation itself.
  */
  CKTreeNode *nodeForComponent(id<CKComponentProtocol> component);
}
}

struct CKComponentScopePair {
  CKTreeNode *node;
  CKTreeNode *previousNode;
};

#endif

/**
 This object represents a node in the component tree.

 Each component has a corresponding CKTreeNode; this node holds the component's state.

 CKTreeNode is the base class of a tree node. It will be attached non-render components (CKComponent & CKCompositeComponent).
 */
@interface CKTreeNode : NSObject
#if CK_NOT_SWIFT
{
  @package
  CKTreeNodeComponentKey _componentKey;
  std::vector<CKTreeNodeComponentKeyToNode> _children;
}

- (instancetype)init NS_UNAVAILABLE;

/** Base initializer */
- (instancetype)initWithPreviousNode:(CKTreeNode *)previousNode
                         scopeHandle:(CKComponentScopeHandle *)scopeHandle;

/** Scope initializer */
- (instancetype)initWithOwner:(CKTreeNode *)owner
                 previousNode:(CKTreeNode *)previousNode
                    scopeRoot:(CKComponentScopeRoot *)scopeRoot
                 componentKey:(const CKTreeNodeComponentKey&)componentKey
          initialStateCreator:(id (^)(void))initialStateCreator
                 stateUpdates:(const CKComponentStateUpdateMap &)stateUpdates
          requiresScopeHandle:(BOOL)requiresScopeHandle;

/** Render initializer */
- (instancetype)initWithComponent:(id<CKRenderComponentProtocol>)component
                           parent:(CKTreeNode *)parent
                     previousNode:(CKTreeNode *)previousNode
                        scopeRoot:(CKComponentScopeRoot *)scopeRoot
                     componentKey:(const CKTreeNodeComponentKey&)componentKey
                     stateUpdates:(const CKComponentStateUpdateMap &)stateUpdates;

#endif

@property (nonatomic, strong, readonly) CKComponentScopeHandle *scopeHandle;

#if CK_NOT_SWIFT

@property (nonatomic, weak, readonly) id<CKComponentProtocol> component;

@property (nonatomic, assign, readonly) CKTreeNodeIdentifier nodeIdentifier;

/** Returns the component's state */
@property (nonatomic, strong, readonly) id state;

/** Returns the componeny key according to its current owner */
@property (nonatomic, assign, readonly) const CKTreeNodeComponentKey &componentKey;

- (void)reusePreviousNode:(CKTreeNode *)node inScopeRoot:(CKComponentScopeRoot *)scopeRoot;

/** This method should be called after a node has been reused */
- (void)didReuseWithParent:(CKTreeNode *)parent
               inScopeRoot:(CKComponentScopeRoot *)scopeRoot;

/** This method should be called on nodes that have been created from CKComponentScope */
- (void)linkComponent:(id<CKComponentProtocol>)component
             toParent:(CKTreeNode *)parent
          inScopeRoot:(CKComponentScopeRoot *)scopeRoot;

+ (instancetype)rootNode;

+ (CKComponentScopePair)childPairForPair:(const CKComponentScopePair &)pair
                                 newRoot:(CKComponentScopeRoot *)newRoot
                       componentTypeName:(const char *)componentTypeName
                              identifier:(id)identifier
                                    keys:(const std::vector<id<NSObject>> &)keys
                     initialStateCreator:(id (^)(void))initialStateCreator
                            stateUpdates:(const CKComponentStateUpdateMap &)stateUpdates
                     requiresScopeHandle:(BOOL)requiresScopeHandle;

+ (CKComponentScopePair)childPairForComponent:(id<CKRenderComponentProtocol>)component
                                       parent:(CKTreeNode *)parent
                               previousParent:(CKTreeNode *)previousParent
                                     scopeRoot:(CKComponentScopeRoot *)scopeRoot
                                  stateUpdates:(const CKComponentStateUpdateMap &)stateUpdates;

- (std::vector<CKTreeNode *>)children;

- (size_t)childrenSize;
/** Returns a component tree node according to its component key */
- (CKTreeNode *)childForComponentKey:(const CKTreeNodeComponentKey &)key;

- (CKTreeNodeComponentKey)createKeyForComponentTypeName:(const char *)componentTypeName
                                             identifier:(id<NSObject>)identifier
                                                   keys:(const std::vector<id<NSObject>> &)keys
                                                   type:(CKTreeNodeComponentKey::Type)type;

/** Save a child node in the parent node according to its component key; this method is being called once during the component tree creation */
- (void)setChild:(CKTreeNode *)child forComponentKey:(const CKTreeNodeComponentKey &)componentKey;

#endif

#if DEBUG
/** Returns a multi-line string describing this node and its children nodes */
@property (nonatomic, copy, readonly) NSString *debugDescription;
@property (nonatomic, copy, readonly) NSArray<NSString *> *debugDescriptionNodes;
@property (nonatomic, copy, readonly) NSArray<NSString *> *debugDescriptionComponents;
#endif

@end
