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
 * @name Empty except
 * @description Except doesn't do anything and has no comment
 * @kind problem
 * @tags reliability
 *       maintainability
 *       external/cwe/cwe-390
 * @problem.severity recommendation
 * @sub-severity high
 * @precision high
 * @id py/empty-except
 */

import python

predicate
empty_except(ExceptStmt ex) {
    not exists(Stmt s | s = ex.getAStmt() and not s instanceof Pass)
}

predicate no_else(ExceptStmt ex) {
    not exists(ex.getTry().getOrelse())
}

predicate no_comment(ExceptStmt ex) {
   not exists(Comment c |
      c.getLocation().getFile() = ex.getLocation().getFile() and
      c.getLocation().getStartLine() >= ex.getLocation().getStartLine() and
      c.getLocation().getEndLine() <= ex.getBody().getLastItem().getLocation().getEndLine()
   )
}

predicate non_local_control_flow(ExceptStmt ex) {
    ex.getType().refersTo(theStopIterationType())
}

predicate try_has_normal_exit(Try try) {
    exists(ControlFlowNode pred, ControlFlowNode succ |
        /* Exists a non-exception predecessor, successor pair */
        pred.getASuccessor() = succ and
        not pred.getAnExceptionalSuccessor() = succ |
        /* Successor is either a normal flow node or a fall-through exit */
        not exists(Scope s | s.getReturnNode() = succ) and
        /* Predecessor is in try body and successor is not */
        pred.getNode().getParentNode*() = try.getAStmt() and
        not succ.getNode().getParentNode*() = try.getAStmt()
    )
}

predicate attribute_access(Stmt s) {
    s.(ExprStmt).getValue() instanceof Attribute
    or
    exists(string name |
        s.(ExprStmt).getValue().(Call).getFunc().(Name).getId() = name |
        name = "getattr" or name = "setattr" or name = "delattr"
    )
    or
    s.(Delete).getATarget() instanceof Attribute
}

predicate subscript(Stmt s) {
    s.(ExprStmt).getValue() instanceof Subscript
    or
    s.(Delete).getATarget() instanceof Subscript
}

predicate encode_decode(Expr ex, ClassObject type) {
    exists(string name |
        ex.(Call).getFunc().(Attribute).getName() = name |
        name = "encode" and type = builtin_object("UnicodeEncodeError")
        or
        name = "decode" and type = builtin_object("UnicodeDecodeError")
    )
}

predicate small_handler(ExceptStmt ex, Stmt s, ClassObject type) {
    not exists(ex.getTry().getStmt(1)) and
    s = ex.getTry().getStmt(0) and
    ex.getType().refersTo(type)
}

/** Holds if this exception handler is sufficiently small in scope to not need a comment
 * as to what it is doing.
 */
predicate focussed_handler(ExceptStmt ex) {
    exists(Stmt s, ClassObject type |
        small_handler(ex, s, type) |
        subscript(s) and type.getAnImproperSuperType() = theLookupErrorType()
        or
        attribute_access(s) and type = theAttributeErrorType()
        or
        s.(ExprStmt).getValue() instanceof Name and type = theNameErrorType()
        or
        encode_decode(s.(ExprStmt).getValue(), type)
    )
}

Try try_return() {
   not exists(result.getStmt(1)) and result.getStmt(0) instanceof Return
}

from ExceptStmt ex
where empty_except(ex) and no_else(ex) and no_comment(ex) and not non_local_control_flow(ex)
  and not ex.getTry() = try_return() and try_has_normal_exit(ex.getTry()) and
  not focussed_handler(ex)
select ex, "'except' clause does nothing but pass and there is no explanatory comment."
