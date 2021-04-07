/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

import Foundation
import ComponentKit

@propertyWrapper
public class ViewModelState<Value> : ScopeHandleAssignable {
  private var handle: CKComponentScopeHandle?

  public init(wrappedValue valueProvider: @escaping @autoclosure () -> Value) {
    self.wrappedValue = valueProvider()
  }

  /// Should only be called during component build or on the main thread thereafter
  public var wrappedValue: Value {
    didSet {
      // Permit changing the view model state's value before it is linked.
      // which would be the case if the view model state is re-assigned before
      // its owning view has rendered (and thus read the values).
      handle.flatMap(CKSwiftUpdateViewModelState)
    }
  }

  public var projectedValue: Binding<Value> {
    Binding(get: { self.wrappedValue }, set: { self.wrappedValue = $0 })
  }

  // MARK: ScopeHandleAssignable

  func assign(handle: CKComponentScopeHandle) {
    // Storing the handle would result in a retain cycle (@ViewModelState -> @ViewModel -> Component ->
    // State which it turn is owned by CKComponentScopeHandle). Keeping a weak reference would also not work since
    // after a few generations the the scope handle wouldn't be owned by anyone else. @ViewModelState only gets
    // assigned the first time around as it's only created once. As soon as D21332674 lands we can refactor this.
    self.handle = handle.newStateless()
  }
}

extension ViewModelState : Equatable where Value : Equatable {
  static public func ==(lhs: ViewModelState, rhs: ViewModelState) -> Bool {
    lhs.wrappedValue == rhs.wrappedValue
  }
}
