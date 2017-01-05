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
 * @name Property in old-style class
 * @description Using property descriptors in old-style classes does not work from Python 2.1 onward.
 * @kind problem
 * @problem.severity error
 * @tags portability
 *       correctness
 */

import python

from PropertyObject prop, ClassObject cls
where cls.declaredAttribute(_) = prop and not cls.failedInference() and not cls.isNewStyle()
select prop, "Property " + prop.getName() + " will not work properly, as class " + cls.getName() + " is an old-style class."
