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
 * Provides classes and predicates for working with the SnakeYaml serialization framework.
 */

import java
import semmle.code.java.dataflow.DataFlow
import semmle.code.java.dataflow.DataFlow2

/**
 * The class `org.yaml.snakeyaml.constructor.Constructor`.
 */
class SnakeYamlConstructor extends RefType {
  SnakeYamlConstructor() {
    this.hasQualifiedName("org.yaml.snakeyaml.constructor", "Constructor")
  }
}

/**
 * The class `org.yaml.snakeyaml.constructor.SafeConstructor`.
 */
class SnakeYamlSafeConstructor extends RefType {
  SnakeYamlSafeConstructor() {
    this.hasQualifiedName("org.yaml.snakeyaml.constructor", "SafeConstructor")
  }
}

/**
 * An instance of `SafeConstructor` or a `Constructor` that only allows the type that is passed into its argument.
 */
class SafeSnakeYamlConstruction extends ClassInstanceExpr {
  SafeSnakeYamlConstruction() {
    this.getConstructedType() instanceof SnakeYamlSafeConstructor or
    (
      this.getConstructedType() instanceof SnakeYamlConstructor and
      this.getNumArgument() > 0
    )
  }
}

/**
 * The class `org.yaml.snakeyaml.Yaml`.
 */
class Yaml extends RefType {
  Yaml() {
    this.hasQualifiedName("org.yaml.snakeyaml", "Yaml")
  }
}

private class SafeYamlConstructionFlowConfig extends DataFlow2::Configuration {
  SafeYamlConstructionFlowConfig() { this = "SnakeYaml::SafeYamlConstructionFlowConfig" }
  override predicate isSource(DataFlow::Node src) { src.asExpr() instanceof SafeSnakeYamlConstruction }
  override predicate isSink(DataFlow::Node sink) { sink = yamlClassInstanceExprArgument(_) }
  private DataFlow::ExprNode yamlClassInstanceExprArgument(ClassInstanceExpr cie) {
    cie.getConstructedType() instanceof Yaml and
    result.getExpr() = cie.getArgument(0)
  }
  ClassInstanceExpr getSafeYaml() { hasFlowTo(yamlClassInstanceExprArgument(result)) }
}

/**
 * An instance of `Yaml` that does not allow arbitrary constructor to be called.
 */
private class SafeYaml extends ClassInstanceExpr {
  SafeYaml() {
    exists(SafeYamlConstructionFlowConfig conf | conf.getSafeYaml() = this)
  }
}

/** A call to a parse method of `Yaml`. */
private class SnakeYamlParse extends MethodAccess {
  SnakeYamlParse() {
    exists(Method m | m.getDeclaringType() instanceof Yaml and
      (m.hasName("load") or m.hasName("loadAll") or m.hasName("loadAs") or m.hasName("parse")) and
      m = this.getMethod()
    )
  }
}

private class SafeYamlFlowConfig extends DataFlow::Configuration {
  SafeYamlFlowConfig() { this = "SnakeYaml::SafeYamlFlowConfig" }
  override predicate isSource(DataFlow::Node src) { src.asExpr() instanceof SafeYaml }
  override predicate isSink(DataFlow::Node sink) { sink = yamlParseQualifier(_) }
  private DataFlow::ExprNode yamlParseQualifier(SnakeYamlParse syp) { result.getExpr() = syp.getQualifier() }
  SnakeYamlParse getASafeSnakeYamlParse() { hasFlowTo(yamlParseQualifier(result)) }
}

/**
 * A call to a parse method of `Yaml` that allows arbitrary constructor to be called.
 */
class UnsafeSnakeYamlParse extends SnakeYamlParse {
  UnsafeSnakeYamlParse() {
    not exists(SafeYamlFlowConfig sy | sy.getASafeSnakeYamlParse() = this)
  }
}