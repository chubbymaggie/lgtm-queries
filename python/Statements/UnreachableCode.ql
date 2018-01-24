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
 * @name Unreachable code
 * @description Code is unreachable
 * @kind problem
 * @tags maintainability
 *       useless-code
 *       external/cwe/cwe-561
 * @problem.severity warning
 * @sub-severity low
 * @precision very-high
 * @id py/unreachable-statement
 */

import python

predicate typing_import(ImportingStmt is) {
    exists(Module m |
        is.getScope() = m and
        exists(TypeHintComment tc |
            tc.getLocation().getFile() = m.getFile()
        )
    )
}

/** Holds if `s` contains the only `yield` in scope */
predicate unique_yield(Stmt s) {
    exists(Yield y | s.contains(y)) and
    exists(Function f |
        f = s.getScope() and
        strictcount(Yield y | f.containsInScope(y)) = 1
    )
}

predicate reportable_unreachable(Stmt s) {
    s.isUnreachable() and
    not typing_import(s) and
    not exists(Stmt other | other.isUnreachable() |
        other.contains(s)
        or
        exists(StmtList l, int i, int j | 
            l.getItem(i) = other and l.getItem(j) = s and i < j
        )
    ) and
    not unique_yield(s)
}

from Stmt s
where reportable_unreachable(s)
select s, "Unreachable statement."
