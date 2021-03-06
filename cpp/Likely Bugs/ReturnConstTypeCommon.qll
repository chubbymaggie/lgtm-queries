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

import cpp

private predicate mightHaveConstMethods(Type t) {
  t instanceof Class
  or t instanceof TemplateParameter
}

predicate hasSuperfluousConstReturn(Function f) {
  exists(Type t | t = f.getType() |
    // This is the primary thing we're testing for,
    t instanceof SpecifiedType
    and t.hasSpecifier("const")
    and (not affectedByMacro(t))
    // but "const" is meaningful when applied to user defined types,
    and not mightHaveConstMethods(t.getUnspecifiedType())
  )
  // and therefore "const T" might be meaningful for other values of "T".
  and not exists(TemplateFunction t | f = t.getAnInstantiation() |
    t.getType().involvesTemplateParameter()
  )
}
