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
 * Provides a taint tracking configuration for reasoning about cleartext storage of sensitive information.
 */
import javascript
private import semmle.javascript.security.SensitiveActions

/**
 * A data flow source for cleartext storage of sensitive information.
 */
abstract class CleartextStorageSource extends DataFlow::Node { }

/**
 * A data flow sink for cleartext storage of sensitive information.
 */
abstract class CleartextStorageSink extends DataFlow::Node { }

/**
 * A sanitizer for cleartext storage of sensitive information.
 */
abstract class CleartextStorageSanitizer extends DataFlow::Node { }

/**
 * A taint tracking configuration for cleartext storage of sensitive information.
 *
 * This configuration identifies flows from `CleartextStorageSource`s, which are sources of
 * sensitive data, to `CleartextStorageSink`s, which is an abstract class representing all
 * the places sensitive data may be stored in cleartext. Additional sources or sinks can be
 * added either by extending the relevant class, or by subclassing this configuration itself,
 * and amending the sources and sinks.
 */
class CleartextStorageDataFlowConfiguration extends TaintTracking::Configuration {
  CleartextStorageDataFlowConfiguration() {
    this = "ClearTextStorage"
  }

  override
  predicate isSource(DataFlow::Node source) {
    source instanceof CleartextStorageSource or
    source.asExpr() instanceof SensitiveExpr
  }

  override
  predicate isSink(DataFlow::Node sink) {
    sink instanceof CleartextStorageSink
  }

  override
  predicate isSanitizer(DataFlow::Node node) {
    node instanceof CleartextStorageSanitizer
  }
}

/** A call to any method whose name suggests that it encodes or encrypts the parameter. */
class ProtectSanitizer extends CleartextStorageSanitizer, DataFlow::ValueNode {
  ProtectSanitizer() {
    exists(string s |
      astNode.(CallExpr).getCalleeName().regexpMatch("(?i).*" + s + ".*") |
      s = "protect" or s = "encode" or s = "encrypt"
    )
  }
}

/**
 * An expression set as a value on a cookie instance.
 */
class CookieStorageSink extends CleartextStorageSink {
  CookieStorageSink() {
    exists (HTTP::CookieDefinition cookieDef |
      this.asExpr() = cookieDef.getValueArgument() or
      this.asExpr() = cookieDef.getHeaderArgument()
    )
  }
}

/**
 * An expression set as a value of localStorage or sessionStorage.
 */
class WebStorageSink extends CleartextStorageSink {
  WebStorageSink() {
    this.asExpr() instanceof WebStorageWrite
  }
}

/**
 * An expression stored by AngularJS.
 */
class AngularJSStorageSink extends CleartextStorageSink {
  AngularJSStorageSink() {
    any(AngularJS::AngularJSCall call).storesArgumentGlobally(this.asExpr())
  }
}
