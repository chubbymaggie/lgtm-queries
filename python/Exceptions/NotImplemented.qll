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

/** Holds if `notimpl` refers to `NotImplemented` or `NotImplemented()` in the `raise` statement */
predicate use_of_not_implemented_in_raise(Raise raise, Expr notimpl) {
    notimpl.refersTo(theNotImplementedObject()) and
    (
        notimpl = raise.getException() or 
        notimpl = raise.getException().(Call).getFunc()
    )
}
