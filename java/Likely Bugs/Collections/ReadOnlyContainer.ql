// Copyright 2017 Semmle Ltd.
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
 * @name Container contents are never initialized
 * @description Querying the contents of a collection or map that is never initialized is not normally useful.
 * @kind problem
 * @problem.severity error
 * @tags reliability
 *       maintainability
 *       useless-code
 *       external/cwe/cwe-561
 */

import java
import semmle.code.java.Reflection
import Containers

from Variable v
where v.fromSource() and
      v.getType() instanceof ContainerType and
      // Exclude parameters and non-private fields.
      (v instanceof LocalVariableDecl or v.(Field).isPrivate()) and
      // Exclude fields that may be written to reflectively.
      not reflectivelyWritten(v) and
      // Every access to `v` is either...
      forall (VarAccess va | va = v.getAnAccess() |
        // ...an assignment storing a fresh container into `v`,
        exists (AssignExpr assgn | va = assgn.getDest() | assgn.getSource() instanceof FreshContainer) or
        /// ...a return (but only if `v` is a local variable)
        (v instanceof LocalVariableDecl and exists (ReturnStmt ret | ret.getResult() = va)) or
        // ...or a call to a query method on `v`.
        exists (MethodAccess ma | va = ma.getQualifier() | ma.getMethod() instanceof ContainerQueryMethod)
      ) and
      // There is at least one call to a query method.
      exists (MethodAccess ma | v.getAnAccess() = ma.getQualifier() |
        ma.getMethod() instanceof ContainerQueryMethod
      ) and
      // Also, any value that `v` is initialized to is a fresh container,
      forall (Expr e | e = v.getAnAssignedValue() | e instanceof FreshContainer) and
      // and `v` is not implicitly initialized by a for-each loop.
      not exists (EnhancedForStmt efs | efs.getVariable().getVariable() = v)
select v, "The contents of this container are never initialized."
