// Copyright 2018 Semmle Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

/**
 * INTERNAL: Do not use directly; use `semmle.javascript.dataflow.TypeInference` instead.
 *
 * Provides classes implementing type inference across function calls.
 */

import javascript
import AbstractValuesImpl

/**
 * Flow analysis for immediately-invoked function expressions (IIFEs).
 */
private class IifeReturnFlow extends DataFlow::AnalyzedValueNode {
  ImmediatelyInvokedFunctionExpr iife;

  IifeReturnFlow() {
    astNode = (CallExpr)iife.getInvocation()
  }

  override AbstractValue getALocalValue() {
    result = getAReturnValue(iife)
  }
}

/**
 * Gets a return value for the immediately-invoked function expression `f`.
 */
private AbstractValue getAReturnValue(ImmediatelyInvokedFunctionExpr f) {
  // explicit return value
  result = f.getAReturnedExpr().analyze().getALocalValue()
  or
  // implicit return value
  (
    // either because execution of the function may terminate normally
    mayReturnImplicitly(f)
    or
    // or because there is a bare `return;` statement
    exists (ReturnStmt ret | ret = f.getAReturnStmt() | not exists(ret.getExpr()))
  ) and
  result = getDefaultReturnValue(f)
}


/**
 * Holds if the execution of function `f` may complete normally without
 * encountering a `return` or `throw` statement.
 *
 * Note that this is an overapproximation, that is, the predicate may hold
 * of functions that cannot actually complete normally, since it does not
 * account for `finally` blocks and does not check reachability.
 */
private predicate mayReturnImplicitly(Function f) {
  exists (ConcreteControlFlowNode final |
    final.getContainer() = f and
    final.isAFinalNode() and
    not final instanceof ReturnStmt and
    not final instanceof ThrowStmt
  )
}

/**
 * Gets the default return value for immediately-invoked function expression `f`,
 * that is, the value that `f` returns if its execution terminates without
 * encountering an explicit `return` statement.
 */
private AbstractValue getDefaultReturnValue(ImmediatelyInvokedFunctionExpr f) {
  if f.isGenerator() or f.isAsync() then
    result = TAbstractOtherObject()
  else
    result = TAbstractUndefined()
}

/**
 * Flow analysis for `this` expressions inside functions.
 */
private abstract class AnalyzedThisExpr extends DataFlow::AnalyzedValueNode {
  Function binder;

  AnalyzedThisExpr() {
    binder = astNode.(ThisExpr).getBinder()
  }
}


/**
 * Flow analysis for `this` expressions that are bound with
 * `Function.prototype.bind`, `Function.prototype.call`,
 * `Function.prototype.apply`, or the `::`-operator.
 *
 * However, since the function could be invoked without being `this` being
 * "inherited", we additionally still infer the ordinary abstract value.
 */
private class AnalyzedThisInBoundFunction extends AnalyzedThisExpr {

  AnalyzedValueNode thisSource;

  AnalyzedThisInBoundFunction() {
    exists(MethodCallExpr bindingCall, Expr binderRef, string name |
      name = "bind" or
      name = "call" or
      name = "apply" |
      binderRef.(DataFlowNode).getALocalSource() = binder and
      bindingCall.calls(binderRef, name) and
      thisSource.asExpr() = bindingCall.getArgument(0)
    ) or
    exists(FunctionBindExpr binding |
      binding.getCallee().(DataFlowNode).getALocalSource() = binder and
      thisSource.asExpr() = binding.getObject()
    )
  }

  override AbstractValue getALocalValue() {
    result = thisSource.getALocalValue() or
    result = AnalyzedThisExpr.super.getALocalValue()
  }

}

/**
 * Flow analysis for `this` expressions inside a function that is instantiated.
 *
 * These expressions are assumed to refer to an instance of that function. Since
 * this is only a heuristic, however, we additionally still infer an indefinite
 * abstract value.
 */
private class AnalyzedThisInConstructorFunction extends AnalyzedThisExpr {
  AbstractValue value;

  AnalyzedThisInConstructorFunction() {
    value = TAbstractInstance(TAbstractFunction(binder))
  }

  override AbstractValue getALocalValue() {
    result = value or
    result = AnalyzedThisExpr.super.getALocalValue()
  }
}

/**
 * Flow analysis for `this` expressions inside an instance member of a class.
 *
 * These expressions are assumed to refer to an instance of that class. This
 * is a safe assumption in practice, but to guard against corner cases we still
 * additionally infer an indefinite abstract value.
 */
private class AnalyzedThisInInstanceMember extends AnalyzedThisExpr {
  ClassDefinition c;

  AnalyzedThisInInstanceMember() {
    exists (MemberDefinition m |
      m = c.getAMember() and
      not m.isStatic() and
      binder = c.getAMember().getInit()
    )
  }

  override AbstractValue getALocalValue() {
    result = TAbstractInstance(TAbstractClass(c)) or
    result = AnalyzedThisExpr.super.getALocalValue()
  }
}

/**
 * Flow analysis for `this` expressions inside a function that is assigned to a property.
 *
 * These expressions are assumed to refer to the object to whose property the function
 * is assigned. Since this is only a heuristic, however, we additionally still infer an
 * indefinite abstract value.
 *
 * The following code snippet shows an example:
 *
 * ```
 * var o = {
 *   p: function() {
 *     this;  // assumed to refer to object literal `o`
 *   }
 * };
 * ```
 */
private class AnalyzedThisInPropertyFunction extends AnalyzedThisExpr {
  DataFlow::AnalyzedNode base;

  AnalyzedThisInPropertyFunction() {
    exists (PropWriteNode pwn |
      pwn.getRhs() = binder and
      base = pwn.getBase().analyze()
    )
  }

  override AbstractValue getALocalValue() {
    result = base.getALocalValue() or
    result = AnalyzedThisExpr.super.getALocalValue()
  }
}
