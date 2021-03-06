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

import semmle.python.security.TaintTracking
import semmle.python.security.strings.Basic

/** A kind of taint representing an externally controlled string containing
 * a potentially malicious path.
 */
class PathInjection extends ExternalStringKind {

    PathInjection() {
        this = "path.injection"
    }

    override TaintKind getTaintForFlowStep(ControlFlowNode fromnode, ControlFlowNode tonode) {
        result = super.getTaintForFlowStep(fromnode, tonode)
        or
        abspath_call(tonode, fromnode) and result instanceof NormalizedPath
    }

}

/** Prevents taint flowing through ntpath.normpath()
 * NormalizedPath below handles that case.
 */
private class PathSanitizer extends Sanitizer {

    PathSanitizer() {
        this = "path.sanitizer"
    }

    override predicate sanitizingNode(TaintKind taint, ControlFlowNode node) {
        taint instanceof PathInjection and
        abspath_call(node, _)
    }

}

private FunctionObject abspath() {
    exists(ModuleObject os, ModuleObject os_path |
        os.getName() = "os" and
        os.getAttribute("path") = os_path |
        os_path.getAttribute("abspath") = result
        or
        os_path.getAttribute("normpath") = result
    )
}

private predicate abspath_call(CallNode call, ControlFlowNode arg) {
    call.getFunction().refersTo(abspath()) and
    arg = call.getArg(0)
}

/** A path that has been normalized, but not verified to be safe */
class NormalizedPath extends TaintKind {

    NormalizedPath() {
        this = "normalized.path.injection"
    }

}

class NormalizedPathSanitizer extends Sanitizer {

    NormalizedPathSanitizer() {
        this = "normalized.path.sanitizer"
    }

    override predicate sanitizingEdge(TaintKind taint, PyEdgeRefinement test) {
        taint instanceof NormalizedPath and
        test.getTest().(CallNode).getFunction().(AttrNode).getName() = "startswith" and
        test.getSense() = true
    }

}

/** A taint sink that is vulnerable to malicious paths.
 * The `vuln` in `open(vuln)` and similar.
 */
class OpenNode extends TaintSink {

    string toString() { result = "argument to open()" }

    OpenNode() {
        exists(CallNode call |
            call.getFunction().refersTo(builtin_object("open")) and
            call.getAnArg() = this
        )
    }

    predicate sinks(TaintKind kind) {
        kind instanceof PathInjection
        or
        kind instanceof NormalizedPath
    }

}





