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

import python
import semmle.python.GuardedControlFlow
import semmle.python.dataflow.SsaDefinitions
import semmle.python.pointsto.Filters

/** Holds if `open` is a call that returns a newly opened file */
predicate call_to_open(ControlFlowNode open) {
    exists(FunctionObject f |
        function_opens_file(f) and
        f.getACall() = open
    ) and
    /* If in `with` statement, then it will be automatically closed. So just treat as not opened */
    not exists(With w | w.getContextExpr() = open.getNode())
}

/** Holds if `n` refers to a file opened at `open` */
predicate expr_is_open(ControlFlowNode n, ControlFlowNode open) {
    call_to_open(open) and open = n
    or
    exists(EssaVariable v |
        n instanceof NameNode and
        var_is_open(v, open) |
        n = v.getAUse()
        or
        wraps_file(n, v)
    )
}

/** Holds if `call` wraps the object referred to by `v` and returns it */
private predicate wraps_file(CallNode call, EssaVariable v) {
    exists(ClassObject cls |
        call.getFunction().refersTo(cls) and
        call.getAnArg() = v.getAUse()
    )
}

/** Holds if `var` refers to a file opened at `open` */
predicate var_is_open(EssaVariable v, ControlFlowNode open) {
    def_is_open(v.getDefinition(), open) and
    /* If use in context expression in `with` statement, then it will be automatically closed. */
    not exists(With w | w.getContextExpr() = v.getAUse().getNode())
}

/** Holds if `test` will pass through an open file in variable `v` for the `sense` successor */
predicate passes_open_files(Variable v, ControlFlowNode test, boolean sense) {
    // `if fd.closed:`
    exists(AttrNode closed |
        closed = test and
        closed.getObject("closed") = v.getAUse()
    ) and sense = false
    or
    // `if fd ==/is ...:` most commonly `if fd is None:`
    equality_test(test, v.getAUse(), sense.booleanNot(), _)
    or
    // `if fd:`
    test = v.getAUse() and sense = true
    or
    exists(UnaryExprNode n |
        n = test and
        n.getNode().getOp() instanceof Not |
        passes_open_files(v, n.getOperand(), sense.booleanNot())
    )
}

/* Helper for `def_is_open` to give better join order */
private predicate passes_open_files(PyEdgeRefinement refinement) {
    passes_open_files(refinement.getSourceVariable(), refinement.getPredecessor().getLastNode(), refinement.getSense())
}

/** Holds if `def` refers to a file opened at `open` */
predicate def_is_open(EssaDefinition def, ControlFlowNode open) {
    expr_is_open(def.(AssignmentDefinition).getValue(), open)
    or
    exists(PyEdgeRefinement refinement |
        refinement = def |
        var_is_open(refinement.getInput(), open) and 
        passes_open_files(refinement)
    )
    or
    exists(PyNodeRefinement refinement |
        refinement = def |
        not closes_file(def) and not wraps_file(refinement.getDefiningNode(), refinement.getInput()) and
        var_is_open(refinement.getInput(), open)
    )
    or
    var_is_open(def.(PhiFunction).getAnInput(), open)
}

/** Holds if `call` closes a file */
predicate closes_file(EssaNodeRefinement call) {
    closes_arg(call.(ArgumentRefinement).getDefiningNode(), call.getSourceVariable()) or
    close_method_call(call.(MethodCallsiteRefinement).getCall(), call.getSourceVariable().(Variable).getAUse())
}

/** Holds if `call` closes its argument, which is an open file referred to by `v` */
predicate closes_arg(CallNode call, Variable v) {
    call.getAnArg() = v.getAUse() and
    (
        exists(FunctionObject close |
            call = close.getACall() and function_closes_file(close)
        )
        or
        call.getFunction().(NameNode).getId() = "close"
    )
}

/** Holds if `call` closes its 'self' argument, which is an open file referred to by `v` */
predicate close_method_call(CallNode call, ControlFlowNode self) {
    call.getFunction().(AttrNode).getObject() = self and
    exists(FunctionObject close |
        call = close.getACall() and function_closes_file(close)
    )
    or
    call.getFunction().(AttrNode).getObject("close") = self
}

predicate function_closes_file(FunctionObject close) {
    close.hasLongName("os.close")
    or
    function_should_close_parameter(close.getFunction())
}

predicate function_should_close_parameter(Function func) {
    exists(EssaDefinition def |
        closes_file(def) and
        def.getSourceVariable().(Variable).getScope() = func
    )
}

predicate function_opens_file(FunctionObject f) {
    f = theOpenFunction()
    or
    exists(EssaVariable v, Return ret |
        ret.getScope() = f.getFunction() |
        ret.getValue().getAFlowNode() = v.getAUse() and 
        var_is_open(v, _)
    )
    or
    exists(Return ret, FunctionObject callee | 
        ret.getScope() = f.getFunction() |
        ret.getValue().getAFlowNode() = callee.getACall() and 
        function_opens_file(callee)
    )
}

predicate file_is_returned(EssaVariable v, ControlFlowNode open) {
    exists(NameNode n, Return ret |
        var_is_open(v, open) and
        v.getAUse() = n |
        ret.getValue() = n.getNode()
        or
        ret.getValue().(Tuple).getAnElt() = n.getNode()
        or
        ret.getValue().(List).getAnElt() = n.getNode()
    )
}
