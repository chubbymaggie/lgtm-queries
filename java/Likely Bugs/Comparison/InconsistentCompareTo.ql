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
 * @name Inconsistent compareTo
 * @description If a class overrides 'compareTo' but not 'equals', it may mean that 'compareTo'
 *              and 'equals' are inconsistent.
 * @kind problem
 * @problem.severity warning
 * @tags reliability
 *       correctness
 */
import java
import semmle.code.java.frameworks.Lombok

/** Whether `t` implements `Comparable` on `typeArg`. */
predicate implementsComparableOn(RefType t, RefType typeArg) {
  exists (RefType cmp |
    t.getAnAncestor() = cmp and
    cmp.getSourceDeclaration().hasQualifiedName("java.lang", "Comparable") |
    // Either `t` extends `Comparable<T>`, in which case `typeArg` is `T`, ...
    typeArg = cmp.(ParameterizedType).getATypeArgument() and not typeArg instanceof Wildcard or
    // ... or it extends the raw type `Comparable`, in which case `typeArg` is `Object`.
    cmp instanceof RawType and typeArg instanceof TypeObject
  )
}

class CompareToMethod extends Method {
  CompareToMethod() {
    this.hasName("compareTo") and
    this.isPublic() and
    this.getNumberOfParameters() = 1 and
    // To implement `Comparable<T>.compareTo`, the parameter must either have type `T` or `Object`.
    exists (RefType typeArg, Type firstParamType |
      implementsComparableOn(this.getDeclaringType(), typeArg) and
      firstParamType = getParameter(0).getType() and
      (firstParamType = typeArg or firstParamType instanceof TypeObject)
    )
  }
}

from Class c, CompareToMethod compareToMethod
where c.fromSource() and
      compareToMethod.fromSource() and
      not exists(EqualsMethod em | em.getDeclaringType().getSourceDeclaration() = c) and
      compareToMethod.getDeclaringType().getSourceDeclaration() = c and
      // Exclude classes annotated with relevant Lombok annotations.
      not c instanceof LombokEqualsAndHashCodeGeneratedClass
select c, "This class declares $@ but inherits equals; the two could be inconsistent.",
       compareToMethod, "compareTo"
