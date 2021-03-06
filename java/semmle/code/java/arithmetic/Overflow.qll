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

import java

/** A subclass of `PrimitiveType` with width-based ordering methods. */
class OrdPrimitiveType extends PrimitiveType {

  predicate widerThan(OrdPrimitiveType that) {
    getWidthRank() > that.getWidthRank()
  }

  predicate widerThanOrEqualTo(OrdPrimitiveType that) {
    getWidthRank() >= that.getWidthRank()
  }

  OrdPrimitiveType maxType(OrdPrimitiveType that) {
    (this.widerThan(that) and result = this)
    or
    (not this.widerThan(that) and result = that)
  }
  
  int getWidthRank() {
    (this.getName() = "byte" and result = 1)
    or
    (this.getName() = "short" and result = 2)
    or
    (this.getName() = "int" and result = 3)
    or
    (this.getName() = "long" and result = 4)
    or
    (this.getName() = "float" and result = 5)
    or
    (this.getName() = "double" and result = 6)
  }
  
  float getMaxValue() {
    (this.getName() = "byte" and result = 127.0)
    or
    (this.getName() = "short" and result = 32767.0)
    or
    (this.getName() = "int" and result = 2147483647.0)
    or
    (this.getName() = "long" and result = 9223372036854775807.0)
    // don't try for floats and doubles
  }

  float getMinValue() {
    (this.getName() = "byte" and result = -128.0)
    or
    (this.getName() = "short" and result = -32768.0)
    or
    (this.getName() = "int" and result = -2147483648.0)
    or
    (this.getName() = "long" and result = -9223372036854775808.0)
    // don't try for floats and doubles
  }
}

class NumType extends Type {
  NumType() {
    this instanceof PrimitiveType or
    this instanceof BoxedType
  }

  /** The width-ordered primitive type corresponding to this type. */
  OrdPrimitiveType getOrdPrimitiveType() {
    (this instanceof PrimitiveType and result = this)
    or
    (this instanceof BoxedType and result = this.(BoxedType).getPrimitiveType())
  }
  
  predicate widerThan(NumType that) {
    this.getOrdPrimitiveType().widerThan(that.getOrdPrimitiveType())
  }
  
  predicate widerThanOrEqualTo(NumType that) {
    this.getOrdPrimitiveType().widerThanOrEqualTo(that.getOrdPrimitiveType())
  }

  int getWidthRank() {
    result = this.getOrdPrimitiveType().getWidthRank()
  }
}

class ArithExpr extends BinaryExpr {
  ArithExpr() {
    (this instanceof AddExpr or this instanceof MulExpr
    or this instanceof SubExpr or this instanceof DivExpr)
    and forall(Expr e | e = this.getAnOperand() | e.getType() instanceof NumType)
  }
  
  OrdPrimitiveType getOrdPrimitiveType() {
    exists(OrdPrimitiveType t1, OrdPrimitiveType t2 |
      t1 = this.getLeftOperand().getType().(NumType).getOrdPrimitiveType() and
      t2 = this.getRightOperand().getType().(NumType).getOrdPrimitiveType() and
      result = t1.maxType(t2)
    )
  }
}
