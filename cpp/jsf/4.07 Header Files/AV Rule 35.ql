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
 * @name Missing header guard
 * @description Header files should contain header guards (#defines to prevent
 *              the file from being included twice). This prevents errors and
 *              inefficiencies caused by repeated inclusion.
 * @kind problem
 * @problem.severity warning
 * @precision high
 * @id cpp/missing-header-guard
 * @tags efficiency
 *       maintainability
 *       modularity
 */
import cpp
import semmle.code.cpp.headers.MultipleInclusion

string possibleGuard(HeaderFile hf, string body) {
  exists(Macro m | m.getFile() = hf and m.getBody() = body | result = m.getHead())
}

/**
 * Option type for preprocessor directives so we can produce a variable number
 * of links in the result
 */
newtype TMaybePreprocessorDirective =
  TSomePreprocessorDirective(PreprocessorDirective pd) or
  TNoPreprocessorDirective()

abstract class MaybePreprocessorDirective extends TMaybePreprocessorDirective {
  abstract string toString();
  abstract Location getLocation();
}

class NoPreprocessorDirective extends TNoPreprocessorDirective, MaybePreprocessorDirective {
  string toString() {
    result = ""
  }
  
  Location getLocation() {
    result instanceof UnknownDefaultLocation
  }
}

class SomePreprocessorDirective extends TSomePreprocessorDirective, MaybePreprocessorDirective {
  PreprocessorDirective pd;

  SomePreprocessorDirective() {
    this = TSomePreprocessorDirective(pd)
  }

  string toString() {
    result = pd.toString()
  }
  
  Location getLocation() {
    result = pd.getLocation()
  }
  
  PreprocessorDirective getPreprocessorDirective() {
    result = pd
  }
}

/**
 * Provides additional detail when there is an incorrect header guard.
 * The second and third parameters are option typed, and are only present
 * when there are additional links in the detail string.
 */
string extraDetail(HeaderFile hf, SomePreprocessorDirective detail1, SomePreprocessorDirective detail2) {
  exists(string s, PreprocessorEndif endif, PreprocessorDirective ifndef | startsWithIfndef(hf, ifndef, s) and endif.getIf() = ifndef |
    detail1.getPreprocessorDirective() = endif and
    detail2.getPreprocessorDirective() = ifndef and
    if not endsWithEndif(hf, endif) then
      result = " ($@ matching $@ occurs before the end of the file)."
    else if exists(Macro m | m.getFile() = hf and m.getHead() = s) then
      result = " (#define " + s + " needs to appear immediately after #ifndef " + s + ")."
    else if strictcount(possibleGuard(hf, _)) = 1 then
      result = " (" + possibleGuard(hf, _) + " should appear in the #ifndef rather than " + s + ")."
    else if strictcount(possibleGuard(hf, "")) = 1 then
      result = " (" + possibleGuard(hf, "") + " should appear in the #ifndef rather than " + s + ")."
    else
      result = " (the macro " + s + " is checked for, but is not defined)."
  )
}

from HeaderFile hf, string detail, MaybePreprocessorDirective detail1, MaybePreprocessorDirective detail2
where not hf instanceof IncludeGuardedHeader
  and (if exists(extraDetail(hf, _, _))
    then detail = extraDetail(hf, detail1, detail2)
    else (detail = "." and
      detail1 instanceof NoPreprocessorDirective and
      detail2 instanceof NoPreprocessorDirective))
  // Exclude files which consist purely of preprocessor directives.
  and not hf.(MetricFile).getNumberOfLinesOfCode() = strictcount(PreprocessorDirective ppd | ppd.getFile() = hf)
  // Exclude files which are always #imported.
  and not forex(Include i | i.getIncludedFile() = hf | i instanceof Import)
  // Exclude files which are only included once.
  and not strictcount(Include i | i.getIncludedFile() = hf) = 1
select hf, "This header file should contain a header guard to prevent multiple inclusion" + detail, detail1, detail1.toString(), detail2, detail2.toString()
