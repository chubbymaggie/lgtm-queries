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
 * Provides classes implementing type inference for variables.
 */

import javascript
private import AbstractValuesImpl
private import semmle.javascript.dataflow.InferredTypes
private import semmle.javascript.dataflow.Refinements

/**
 * Flow analysis for captured variables.
 */
private class AnalyzedCapturedVariable extends @variable {
  AnalyzedCapturedVariable() {
    this.(Variable).isCaptured()
  }

  /**
   * Gets an abstract value that may be assigned to this variable.
   */
  pragma[nomagic]
  AbstractValue getALocalValue() {
    result = getADef().getAnAssignedValue()
  }

  /**
   * Gets a definition of this variable.
   */
  AnalyzedVarDef getADef() {
    this = result.getAVariable()
  }

  /** Gets a textual representation of this element. */
  string toString() {
    result = this.(Variable).toString()
  }
}

/**
 * Flow analysis for accesses to SSA variables.
 */
private class SsaVarAccessAnalysis extends DataFlow::AnalyzedValueNode {
  AnalyzedSsaDefinition def;

  SsaVarAccessAnalysis() {
    astNode = def.getVariable().getAUse()
  }

  override AbstractValue getALocalValue() {
    result = def.getAnRhsValue()
  }
}

/**
 * Flow analysis for `VarDef`s.
 */
class AnalyzedVarDef extends VarDef {
  /**
   * Gets an abstract value that this variable definition may assign
   * to its target, including indefinite values if this definition
   * cannot be analyzed completely.
   */
  AbstractValue getAnAssignedValue() {
    result = getAnRhsValue() or
    exists (DataFlow::Incompleteness cause |
      isIncomplete(cause) and result = TIndefiniteAbstractValue(cause)
    )
  }

  /**
   * Gets an abstract value that the right hand side of this `VarDef`
   * may evaluate to.
   */
  AbstractValue getAnRhsValue() {
    result = getRhs().getALocalValue() or
    this = any(ForInStmt fis).getIteratorExpr() and result = abstractValueOfType(TTString()) or
    this = any(EnumMember member | not exists(member.getInitializer())).getIdentifier() and result = abstractValueOfType(TTNumber())
  }

  /**
   * Gets a node representing the value of the right hand side of
   * this `VarDef`.
   */
  DataFlow::AnalyzedNode getRhs() {
    result = getSource().analyze() and getTarget() instanceof VarRef or
    result.asExpr() = (CompoundAssignExpr)this or
    result.asExpr() = (UpdateExpr)this
  }

  /**
   * Holds if flow analysis results for this node may be incomplete
   * due to the given `cause`.
   */
  predicate isIncomplete(DataFlow::Incompleteness cause) {
    this instanceof Parameter and cause = "call" or
    this instanceof ImportSpecifier and cause = "import" or
    exists (EnhancedForLoop efl | efl instanceof ForOfStmt or efl instanceof ForEachStmt |
      this = efl.getIteratorExpr()
    ) and cause = "heap" or
    exists (ComprehensionBlock cb | this = cb.getIterator()) and cause = "yield" or
    getTarget() instanceof DestructuringPattern and cause = "heap"
  }

  /**
   * Gets the toplevel syntactic unit to which this definition belongs.
   */
  TopLevel getTopLevel() {
    result = this.(ASTNode).getTopLevel()
  }
}

/**
 * Flow analysis for simple IIFE parameters.
 */
private class AnalyzedIIFEParameter extends AnalyzedVarDef, @vardecl {
  AnalyzedIIFEParameter() {
    exists (ImmediatelyInvokedFunctionExpr iife, int parmIdx |
      this = iife.getParameter(parmIdx) |
      // we cannot track flow into rest parameters...
      not this.(Parameter).isRestParameter() and
      // ...nor flow out of spread arguments
      exists (int argIdx | argIdx = parmIdx + iife.getArgumentOffset() |
        not iife.isSpreadArgument([0..argIdx])
      )
    )
  }

  /** Gets the IIFE this is a parameter of. */
  ImmediatelyInvokedFunctionExpr getIIFE() {
    this = result.getAParameter()
  }

  override DataFlow::AnalyzedNode getRhs() {
    getIIFE().argumentPassing(this, result.asExpr()) or
    result = this.(Parameter).getDefault().analyze()
  }

  override AbstractValue getAnRhsValue() {
    result = AnalyzedVarDef.super.getAnRhsValue() or
    not getIIFE().argumentPassing(this, _) and result = TAbstractUndefined()
  }

  override predicate isIncomplete(DataFlow::Incompleteness cause) {
    exists (ImmediatelyInvokedFunctionExpr iife | iife = getIIFE() |
      // if the IIFE has a name and that name is referenced, we conservatively
      // assume that there may be other calls than the direct one
      exists (iife.getVariable().getAnAccess()) and cause = "call" or
      // if the IIFE is non-strict and its `arguments` object is accessed, we
      // also assume that there may be other calls (through `arguments.callee`)
      not iife.isStrict() and
      exists (iife.getArgumentsVariable().getAnAccess()) and cause = "call"
    )
  }
}

/**
 * Flow analysis for simple rest parameters.
 */
private class AnalyzedRestParameter extends AnalyzedVarDef, @vardecl {
  AnalyzedRestParameter() {
    this.(Parameter).isRestParameter()
  }

  override AbstractValue getAnRhsValue() {
    result = TAbstractOtherObject()
  }

  override predicate isIncomplete(DataFlow::Incompleteness cause) {
    none()
  }
}

/**
 * Flow analysis for `module` and `exports` parameters of AMD modules.
 */
private class AnalyzedAmdParameter extends AnalyzedVarDef {
  AbstractValue implicitInitVal;

  AnalyzedAmdParameter() {
    exists (AMDModule m, AMDModuleDefinition mdef | mdef = m.getDefine() |
      this = mdef.getModuleParameter() and
      implicitInitVal = TAbstractModuleObject(m)
      or
      this = mdef.getExportsParameter() and
      implicitInitVal = TAbstractExportsObject(m)
    )
  }

  override AbstractValue getAnAssignedValue() {
    result = super.getAnAssignedValue() or
    result = implicitInitVal
  }
}

/**
 * Flow analysis for SSA definitions.
 */
abstract class AnalyzedSsaDefinition extends SsaDefinition {
  /**
   * Gets an abstract value that the right hand side of this definition
   * may evaluate to at runtime.
   */
  abstract AbstractValue getAnRhsValue();
}

/**
 * Flow analysis for SSA definitions corresponding to `VarDef`s.
 */
private class AnalyzedExplicitDefinition extends AnalyzedSsaDefinition, SsaExplicitDefinition {
  override AbstractValue getAnRhsValue() {
    result = getDef().(AnalyzedVarDef).getAnAssignedValue()
  }
}

/**
 * Flow analysis for SSA definitions corresponding to implicit variable initialization.
 */
private class AnalyzedImplicitInit extends AnalyzedSsaDefinition, SsaImplicitInit {
  override AbstractValue getAnRhsValue() {
    result = getImplicitInitValue(getSourceVariable())
  }
}

/**
 * Flow analysis for SSA definitions corresponding to implicit variable capture.
 */
private class AnalyzedVariableCapture extends AnalyzedSsaDefinition, SsaVariableCapture {
  override AbstractValue getAnRhsValue() {
    exists (LocalVariable v | v = getSourceVariable() |
      result = v.(AnalyzedCapturedVariable).getALocalValue() or
      not guaranteedToBeInitialized(v) and result = getImplicitInitValue(v)
    )
  }
}

/**
 * Flow analysis for SSA phi nodes.
 */
private class AnalyzedPhiNode extends AnalyzedSsaDefinition, SsaPhiNode {
  override AbstractValue getAnRhsValue() {
    result = getAnInput().(AnalyzedSsaDefinition).getAnRhsValue()
  }
}

/**
 * Flow analysis for refinement nodes.
 */
class AnalyzedRefinement extends AnalyzedSsaDefinition, SsaRefinementNode {
  override AbstractValue getAnRhsValue() {
    // default implementation: don't refine
    result = getAnInputRhsValue()
  }

  /**
   * Gets an abstract value that one of the inputs of this refinement may evaluate to.
   */
  AbstractValue getAnInputRhsValue() {
    result = getAnInput().(AnalyzedSsaDefinition).getAnRhsValue()
  }
}

/**
 * Flow analysis for refinement nodes where the guard is a condition.
 *
 * For such nodes, we want to split any indefinite abstract values flowing into the node
 * into sets of more precise abstract values to enable them to be refined.
 */
class AnalyzedConditionGuard extends AnalyzedRefinement {
  AnalyzedConditionGuard() {
    getGuard() instanceof ConditionGuardNode
  }

  override AbstractValue getAnInputRhsValue() {
    exists (AbstractValue input | input = super.getAnInputRhsValue() |
      result = input.(IndefiniteAbstractValue).split()
      or
      not input instanceof IndefiniteAbstractValue and result = input
    )
  }
}

/**
 * Flow analysis for condition guards with an outcome of `true`.
 *
 * For example, in `if(x) s; else t;`, this will restrict the possible values of `x` at
 * the beginning of `s` to those that are truthy.
 */
class AnalyzedPositiveConditionGuard extends AnalyzedRefinement {
  AnalyzedPositiveConditionGuard() {
    getGuard().(ConditionGuardNode).getOutcome() = true
  }

  override AbstractValue getAnRhsValue() {
    result = getAnInputRhsValue() and
    exists (RefinementContext ctxt |
      ctxt = TVarRefinementContext(this, getSourceVariable(), result) and
      getRefinement().eval(ctxt).getABooleanValue() = true
    )
  }
}

/**
 * Flow analysis for condition guards with an outcome of `false`.
 *
 * For example, in `if(x) s; else t;`, this will restrict the possible values of `x` at
 * the beginning of `t` to those that are falsy.
 */
class AnalyzedNegativeConditionGuard extends AnalyzedRefinement {
  AnalyzedNegativeConditionGuard() {
    getGuard().(ConditionGuardNode).getOutcome() = false
  }

  override AbstractValue getAnRhsValue() {
    result = getAnInputRhsValue() and
    exists (RefinementContext ctxt |
      ctxt = TVarRefinementContext(this, getSourceVariable(), result) and
      getRefinement().eval(ctxt).getABooleanValue() = false
    )
  }
}

/**
 * Gets the abstract value representing the initial value of variable `v`.
 *
 * Most variables are implicitly initialized to `undefined`, except
 * for `arguments` (which is initialized to the arguments object),
 * and special Node.js variables such as `module` and `exports`.
 */
private AbstractValue getImplicitInitValue(LocalVariable v) {
  if v instanceof ArgumentsVariable then
    exists (Function f | v = f.getArgumentsVariable() |
      result = TAbstractArguments(f)
    )
  else if nodeBuiltins(v, _) then
    nodeBuiltins(v, result)
  else
    result = TAbstractUndefined()
}

/**
 * Holds if `v` is a local variable that can never be observed in its uninitialized state.
 */
private predicate guaranteedToBeInitialized(LocalVariable v) {
  // function declarations can never be uninitialized due to hoisting
  exists (FunctionDeclStmt fd | v = fd.getVariable()) or
  // parameters also can never be uninitialized
  exists (Parameter p | v = p.getAVariable())
}

/**
 * Holds if `av` represents an initial value of CommonJS variable `var`.
 */
private predicate nodeBuiltins(Variable var, AbstractValue av) {
  exists (Module m, string name | var = m.getScope().getVariable(name) |
    name = "require" and av = TIndefiniteAbstractValue("heap")
    or
    name = "module" and av = TAbstractModuleObject(m)
    or
    name = "exports" and av = TAbstractExportsObject(m)
    or
    name = "arguments" and av = TAbstractOtherObject()
    or
    (name = "__filename" or name = "__dirname") and
    (av = TAbstractNumString() or av = TAbstractOtherString())
  )
}

/**
 * Flow analysis for global variables.
 */
private class AnalyzedGlobalVarUse extends DataFlow::AnalyzedValueNode {
  GlobalVariable gv;
  TopLevel tl;

  AnalyzedGlobalVarUse() {
    useIn(gv, astNode, tl)
  }

  /** Gets the name of this global variable. */
  string getVariableName() { result = gv.getName() }

  /**
   * Gets a property write that may assign to this global variable as a property
   * of the global object.
   */
  private PropWriteNode getAnAssigningPropWrite() {
    result.getPropertyName() = getVariableName() and
    result.getBase().analyze().getALocalValue() instanceof AbstractGlobalObject
  }

  override predicate isIncomplete(DataFlow::Incompleteness reason) {
    DataFlow::AnalyzedValueNode.super.isIncomplete(reason)
    or
    clobberedProp(gv, reason)
  }

  override AbstractValue getALocalValue() {
    result = DataFlow::AnalyzedValueNode.super.getALocalValue()
    or
    result = getAnAssigningPropWrite().getRhs().analyze().getALocalValue()
    or
    // prefer definitions within the same toplevel
    exists (AnalyzedVarDef def | defIn(gv, def, tl) |
      result = def.getAnAssignedValue()
    )
    or
    // if there aren't any, consider all definitions as sources
    not defIn(gv, _, tl) and
    result = gv.(AnalyzedCapturedVariable).getALocalValue()
  }
}

/**
 * Holds if `gva` is a use of `gv` in `tl`.
 */
private predicate useIn(GlobalVariable gv, GlobalVarAccess gva, TopLevel tl) {
  gva = gv.getAnAccess() and
  gva instanceof RValue and
  gva.getTopLevel() = tl
}

/**
 * Holds if `def` is a definition of `gv` in `tl`.
 */
private predicate defIn(GlobalVariable gv, AnalyzedVarDef def, TopLevel tl) {
  def.getTarget().(VarRef).getVariable() = gv and
  def.getTopLevel() = tl
}

/**
 * Holds if there is a write to a property with the same name as `gv` on an object
 * for which the analysis is incomplete due to the given `reason`.
 */

private predicate clobberedProp(GlobalVariable gv, DataFlow::Incompleteness reason) {
  exists (PropWriteNode pwn, AbstractValue baseVal |
    pwn.getPropertyName() = gv.getName() and
    baseVal = pwn.getBase().analyze().getALocalValue() and
    baseVal.isIndefinite(reason) and
    baseVal.getType() = TTObject()
  )
}

/**
 * Flow analysis for `undefined`.
 */
private class AnalyzedUndefinedUse extends AnalyzedGlobalVarUse {
  AnalyzedUndefinedUse() { getVariableName() = "undefined" }

  override AbstractValue getALocalValue() { result = TAbstractUndefined() }
}

/**
 * Holds if there might be indirect assignments to `v` through an `arguments` object.
 *
 * This predicate is conservative (that is, it may hold even for variables that cannot,
 * in fact, be assigned in this way): it checks if `v` is a parameter of a function
 * with a mapped `arguments` variable, and either there is a property write on `arguments`,
 * or we lose track of `arguments` (for example, because it is passed to another function).
 *
 * Here is an example with a property write on `arguments`:
 *
 * ```
 * function f1(x) {
 *   for (var i=0; i<arguments.length; ++i)
 *     arguments[i]++;
 * }
 * ```
 *
 * And here is an example where `arguments` escapes:
 *
 * ```
 * function f2(x) {
 *   [].forEach.call(arguments, function(_, i, args) {
 *     args[i]++;
 *   });
 * }
 * ```
 *
 * In both cases `x` is assigned through the `arguments` object.
 */
private predicate maybeModifiedThroughArguments(LocalVariable v) {
  exists (Function f, ArgumentsVariable args |
    v = f.getAParameter().(SimpleParameter).getVariable() and
    f.hasMappedArgumentsVariable() and args = f.getArgumentsVariable() |
    exists (VarAccess acc | acc = args.getAnAccess() |
      // `acc` is a use of `arguments` that isn't a property access
      // (like `arguments[0]` or `arguments.length`), so we conservatively
      // consider `arguments` to have escaped
      not exists (PropAccess pacc | acc = pacc.getBase())
      or
      // acc is a write to a property of `arguments` other than `length`,
      // so we conservatively consider it a possible write to `v`
      exists (PropAccess pacc | acc = pacc.getBase() |
        not pacc.getPropertyName() = "length" and
        pacc instanceof LValue
      )
    )
  )
}

/**
 * Flow analysis for variables that may be mutated reflectively through `eval`
 * or via the `arguments` array, and for variables that may refer to properties
 * of a `with` scope object.
 *
 * Note that this class overlaps with the other classes for handling variable
 * accesses, notably `VarAccessAnalysis`: its implementation of `getALocalValue`
 * does not replace the implementations in other classes, but complements
 * them by injecting additional values into the analysis.
 */
private class ReflectiveVarFlow extends DataFlow::AnalyzedValueNode {
  ReflectiveVarFlow() {
    exists (Variable v | v = astNode.(VarAccess).getVariable() |
      any(DirectEval de).mayAffect(v)
      or
      maybeModifiedThroughArguments(v)
      or
      any(WithStmt with).mayAffect(astNode)
    )
  }

  override AbstractValue getALocalValue() { result = TIndefiniteAbstractValue("eval") }
}

/**
 * Flow analysis for variables exported from a TypeScript namespace.
 *
 * These are translated to property accesses by the TypeScript compiler and
 * can thus be mutated indirectly through the heap.
 */
private class NamespaceExportVarFlow extends DataFlow::AnalyzedValueNode {
  NamespaceExportVarFlow() {
    astNode.(VarAccess).getVariable().isNamespaceExport()
  }

  override AbstractValue getALocalValue() { result = TIndefiniteAbstractValue("namespace") }
}