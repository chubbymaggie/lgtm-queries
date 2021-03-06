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
 * @name Suspicious 'sizeof' use
 * @description Taking 'sizeof' of an array parameter is often mistakenly thought
 *              to yield the size of the underlying array, but it always yields
 *              the machine pointer size.
 * @kind problem
 * @problem.severity warning
 * @precision medium
 * @id cpp/suspicious-sizeof
 * @tags reliability
 *       correctness
 *       external/cwe/cwe-467
 */
import cpp

class CandidateParameter extends Parameter {
  CandidateParameter() {
      // an array parameter
      getType().getUnspecifiedType() instanceof ArrayType
      or
      (
        // a pointer parameter
        getType().getUnspecifiedType() instanceof PointerType and
        
        // whose address is never taken (rules out common
        // false positive patterns)
        not exists(AddressOfExpr aoe | aoe.getAddressable() = this)
      )
  }
}

from SizeofExprOperator seo, VariableAccess va
where seo.getExprOperand() = va and
      va.getTarget() instanceof CandidateParameter and
      not va.isAffectedByMacro() and
      not va.isCompilerGenerated()
select seo, "This evaluates to the size of the pointer type, which may not be what you want."
