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
 * @name Inefficient regular expression
 * @description A regular expression that requires exponential time to match certain inputs
 *              can be a performance bottleneck, and may be vulnerable to denial-of-service
 *              attacks.
 * @kind problem
 * @problem.severity error
 * @precision medium
 * @id js/redos
 * @tags security
 *       external/cwe/cwe-730
 *       external/cwe/cwe-400
 */

import javascript

/*
 * This query implements the analysis described in the following two papers:
 *
 *   James Kirrage, Asiri Rathnayake, Hayo Thielecke: Static Analysis for
 *     Regular Expression Denial-of-Service Attacks. NSS 2013.
 *     (http://www.cs.bham.ac.uk/~hxt/research/reg-exp-sec.pdf)
 *   Asiri Rathnayake, Hayo Thielecke: Static Analysis for Regular Expression
 *     Exponential Runtime via Substructural Logics. 2014.
 *     (https://www.cs.bham.ac.uk/~hxt/research/redos_full.pdf)
 *
 * The basic idea is to search for overlapping cycles in the NFA, that is,
 * states `q` such that there are two distinct paths from `q` to itself
 * that consume the same word `w`.
 *
 * For any such state `q`, an attack string can be constructed as follows:
 * concatenate a prefix `v` that takes the NFA to `q` with `n` copies of
 * the word `w` that leads back to `q` along two different paths, followed
 * by a suffix `x` that is _not_ accepted in state `q`. A backtracking
 * implementation will need to explore at least 2^n different ways of going
 * from `q` back to itself while trying to match the `n` copies of `w`
 * before finally giving up.
 *
 * Now in order to identify overlapping cycles, all we have to do is find
 * pumpable forks, that is, states `q` that can transition to two different
 * states `r1` and `r2` on the same input symbol `c`, such that there are
 * paths from both `r1` and `r2` to `q` that consume the same word. The latter
 * condition is equivalent to saying that `(q, q)` is reachable from `(r1, r2)`
 * in the product NFA.
 *
 * This is what the query does. It makes no attempt to construct a prefix
 * leading into `q`, and only a weak one to construct a suffix that ensures
 * rejection; this causes some false positives. Also, the query does not fully
 * handle character classes and does not handle various other features at all;
 * this causes false negatives.
 *
 * Finally, sometimes it depends on the translation whether the NFA generated
 * for a regular expression has a pumpable fork or not. We implement one
 * particular translation, which may result in false positives or negatives
 * relative to some particular JavaScript engine.
 *
 * More precisely, the query constructs an NFA from a regular expression `r`
 * as follows:
 *
 *   * Every sub-term `t` gives rise to an NFA state `Match(t)`, representing
 *     the state of the automaton before attempting to match `t`.
 *   * There is one additional accepting state `Accept(r)`.
 *   * Transitions between states may be labelled with epsilon, or an abstract
 *     input symbol.
 *   * Each abstract input symbol represents a set of concrete input characters:
 *     either a single character, a set of characters represented by a (positive)
 *     character class, or the set of all characters.
 *   * The product automaton is constructed lazily, starting with pair states
 *     `(q, q)` where `q` is a fork, and proceding along an over-approximate
 *     step relation.
 *   * The over-approximate step relation allows transitions along pairs of
 *     abstract input symbols as long as the symbols are not trivially incompatible.
 *   * Once a trace of pairs of abstract input symbols that leads from a fork
 *     back to itself has been identified, we attempt to construct a concrete
 *     string corresponding to it, which may fail.
 *   * Instead of trying to construct a suffix that makes the automaton fail,
 *     we ensure that it isn't possible to reach the accepting state from the
 *     fork along epsilon transitions. In this case, it is very likely (though
 *     not guaranteed) that a rejecting suffix exists.
 */

/**
 * An abstract input symbol, representing a set of concrete characters.
 */
newtype TInputSymbol =
  /** An input symbol corresponding to character `c`. */
  Char(string c) { c = any(RegExpConstant cc).getValue() }
  or
  /**
   * An input symbol representing all characters matched by
   * (positive, non-universal) character class `recc`.
   */
  CharClass(RegExpCharacterClass recc) {
    not recc.isInverted() and not isUniversalClass(recc)
  }
  or
  /** An input symbol representing all characters matched by `.`. */
  Dot()
  or
  /** An input symbol representing all characters. */
  Any()

/**
 * Holds if character class `cc` matches all characters.
 */
predicate isUniversalClass(RegExpCharacterClass cc) {
  // [^]
  cc.isInverted() and not exists(cc.getAChild())
  or
  // [\w\W] and similar
  not cc.isInverted() and
  exists (string cce1, string cce2 |
    cce1 = cc.getAChild().(RegExpCharacterClassEscape).getValue() and
    cce2 = cc.getAChild().(RegExpCharacterClassEscape).getValue() |
    cce1 != cce2 and cce1.toLowerCase() = cce2.toLowerCase()
  )
}

/**
 * An abstract input symbol, representing a set of concrete characters.
 */
class InputSymbol extends TInputSymbol {
  string toString() {
    this = Char(result) or
    result = any(RegExpCharacterClass recc | this = CharClass(recc)).toString() or
    this = Dot() and result = "." or
    this = Any() and result = "[^]"
  }
}

/**
 * Holds if `s` belongs to `l` and is of the form `[lo-hi]`, that is, a character
 * class containing exactly one range with lower bound `lo` and higher bound `hi`.
 */
predicate isRange(RegExpLiteral l, InputSymbol s, string lo, string hi) {
  exists (RegExpCharacterClass cc, RegExpCharacterRange cr |
    s = CharClass(cc) and cr = cc.getAChild() and cc.getNumChild() = 1 and
    cr.isRange(lo, hi) and l = cc.getLiteral()
  )
}

/**
 * Holds if `s1` and `s2` have an empty intersection.
 *
 * This predicate is incomplete; it is only used for pruning the search space.
 */
predicate incompatible(InputSymbol s1, InputSymbol s2) {
  exists (string c, string d |
    s1 = Char(c) and s2 = Char(d) and c != d
  ) or
  s1 = Dot() and (s2 = Char("\n") or s2 = Char("\r")) or
  s2 = Dot() and (s1 = Char("\n") or s1 = Char("\r")) or
  exists (RegExpLiteral l, string b1, string b2 |
    isRange(l, s1, _, b1) and isRange(l, s2, b2, _) and b1 < b2 or
    isRange(l, s1, b1, _) and isRange(l, s2, _, b2) and b2 < b1
  )
}

newtype TState =
  Match(RegExpTerm t) or
  Accept(RegExpLiteral l)

/**
 * A state in the NFA corresponding to a regular expression.
 *
 * Each regular expression literal `l` has one accepting state
 * `Accept(l)` and one state `Match(t)` for every subterm `t`,
 * which represents the state of the NFA before starting to
 * match `t`.
 */
class State extends TState {
  RegExpParent repr;

  State() {
    this = Match(repr) or this = Accept(repr)
  }

  string toString() {
    result = "Match(" + (RegExpTerm)repr + ")" or
    result = "Accept(" + (RegExpLiteral)repr + ")"
  }

  Location getLocation() {
    result = repr.getLocation()
  }

  /** Gets the regular expression this state is associated with. */
  RegExpLiteral getLiteral() {
    result = repr or
    result = repr.(RegExpTerm).getLiteral()
  }
}

/**
 * An edge label in the NFA, that is, either an input symbol or
 * the epsilon symbol.
 */
newtype TEdgeLabel =
  Epsilon() or
  Consume(InputSymbol s)

class EdgeLabel extends TEdgeLabel {
  string toString() {
    this = Epsilon() and result = "" or
    exists (InputSymbol s | this = Consume(s) and result = s.toString())
  }
}

/**
 * Gets a state the NFA may be in after matching `t`.
 */
State after(RegExpTerm t) {
  exists (RegExpAlt alt | t = alt.getAChild() |
    result = after(alt)
  )
  or
  exists (RegExpSequence seq, int i | t = seq.getChild(i) |
    result = Match(seq.getChild(i+1)) or
    i+1 = seq.getNumChild() and result = after(seq)
  )
  or
  exists (RegExpGroup grp | t = grp.getAChild() |
    result = after(grp)
  )
  or
  exists (RegExpStar star | t = star.getAChild() |
    result = Match(star)
  )
  or
  exists (RegExpPlus plus | t = plus.getAChild() |
    result = Match(plus) or
    result = after(plus)
  )
  or
  exists (RegExpOpt opt | t = opt.getAChild() |
    result = after(opt)
  )
  or
  exists (RegExpLiteral l | l = t.getParent() |
    result = Accept(l)
  )
}

/**
 * Holds if the NFA has a transition from `q1` to `q2` labelled with `lbl`.
 */
predicate delta(State q1, EdgeLabel lbl, State q2) {
  exists (RegExpConstant s |
    q1 = Match(s) and lbl = Consume(Char(s.getValue())) and q2 = after(s)
  )
  or
  exists (RegExpDot dot |
    q1 = Match(dot) and lbl = Consume(Dot()) and q2 = after(dot)
  )
  or
  exists (RegExpCharacterClass cc |
    isUniversalClass(cc) and q1 = Match(cc) and lbl = Consume(Any()) and q2 = after(cc) or
    q1 = Match(cc) and lbl = Consume(CharClass(cc)) and q2 = after(cc)
  )
  or
  exists (RegExpAlt alt | lbl = Epsilon() |
    q1 = Match(alt) and q2 = Match(alt.getAChild())
  )
  or
  exists (RegExpSequence seq | lbl = Epsilon() |
    q1 = Match(seq) and q2 = Match(seq.getChild(0))
  )
  or
  exists (RegExpGroup grp | lbl = Epsilon() |
    q1 = Match(grp) and q2 = Match(grp.getChild(0))
  )
  or
  exists (RegExpStar star | lbl = Epsilon() |
    q1 = Match(star) and q2 = Match(star.getChild(0)) or
    q1 = Match(star) and q2 = after(star)
  )
  or
  exists (RegExpPlus plus | lbl = Epsilon() |
    q1 = Match(plus) and q2 = Match(plus.getChild(0))
  )
  or
  exists (RegExpOpt opt | lbl = Epsilon() |
    q1 = Match(opt) and q2 = Match(opt.getChild(0)) or
    q1 = Match(opt) and q2 = after(opt)
  )
}

/**
 * Gets a state that `q` has an epsilon transition to.
 */
State epsilonSucc(State q) {
  delta(q, Epsilon(), result)
}

/**
 * Gets a state that has an epsilon transition to `q`.
 */
State epsilonPred(State q) {
  q = epsilonSucc(result)
}

/**
 * Holds if there is a state `q` that can be reached from `q1`
 * along epsilon edges, such that there is a transition from
 * `q` to `q2` that consumes symbol `s`.
 */
predicate deltaClosed(State q1, InputSymbol s, State q2) {
  delta(epsilonSucc*(q1), Consume(s), q2)
}

/**
 * Holds if `l` contains a repetition (star, plus or range) quantifier.
 */
private predicate hasRepetition(RegExpLiteral l) {
  exists (RegExpQuantifier q |
    q instanceof RegExpStar or
    q instanceof RegExpPlus or
    q instanceof RegExpRange |
    l = q.getLiteral()
  )
}

/**
 * A state in the product automaton.
 *
 * We lazily only construct those states that we are actually
 * going to need: `(q, q)` for every fork state `q`, and any
 * pair of states that can be reached from a pair that we have
 * already constructed. To cut down on the number of states,
 * we only represent states `(q1, q2)` where `q1` is lexicographically
 * no bigger than `q2`.
 */
newtype TStatePair =
  MkStatePair(State q1, State q2) {
    isFork(q1, _, _, _, _) and q2 = q1
    or
    step(_, _, _, q1, q2) and q1.toString() <= q2.toString()
  }

class StatePair extends TStatePair {
  State q1;
  State q2;

  StatePair() { this = MkStatePair(q1, q2) }

  string toString() { result = "(" + q1 + ", " + q2 + ")" }
}

/**
 * Gets the state pair `(q1, q2)` or `(q2, q1)`; note that only
 * one or the other is defined.
 */
StatePair mkStatePair(State q1, State q2) {
  result = MkStatePair(q1, q2) or result = MkStatePair(q2, q1)
}

predicate isStatePair(StatePair p) { any() }

predicate delta2(StatePair q, StatePair r) { step(q, _, _, r) }

/**
 * Gets the minimum length of a path from `q` to `r` in the
 * product automaton.
 */
int statePairDist(StatePair q, StatePair r) =
  shortestDistances(isStatePair/1, delta2/2)(q, r, result)

/**
 * Holds if there are transitions from `q` to `r1` and from `q` to `r2`
 * labelled with `s1` and `s2`, respectively, where `s1` and `s2` do not
 * trivially have an empty intersection.
 *
 * This predicate only holds for states associated with regular expressions
 * that have at least one repetition quantifier in them (otherwise the
 * expression cannot be vulnerable to ReDoS attacks anyway).
 */
predicate isFork(State q, InputSymbol s1, InputSymbol s2, State r1, State r2) {
  hasRepetition(q.getLiteral()) and
  exists (State q1, State q2 |
    q1 = epsilonSucc*(q) and delta(q1, Consume(s1), r1) and
    q2 = epsilonSucc*(q) and delta(q2, Consume(s2), r2) and
    not incompatible(s1, s2) |
    s1 != s2 or
    r1 != r2 or
    r1 = r2 and q1 != q2
  )
}

/**
 * Holds if there are transitions from the components of `q` to the corresponding
 * components of `r` labelled with `s1` and `s2`, respectively.
 */
predicate step(StatePair q, InputSymbol s1, InputSymbol s2, StatePair r) {
  exists (State r1, State r2 |
    step(q, s1, s2, r1, r2) and r = mkStatePair(r1, r2)
  )
}

/**
 * Holds if there are transitions from the components of `q` to `r1` and `r2`
 * labelled with `s1` and `s2`, respectively.
 */
predicate step(StatePair q, InputSymbol s1, InputSymbol s2, State r1, State r2) {
  exists (State q1, State q2 | q = MkStatePair(q1, q2) |
    deltaClosed(q1, s1, r1) and deltaClosed(q2, s2, r2) and
    not incompatible(s1, s2)
  )
}

/**
 * A list of pairs of input symbols that describe a path in the product automaton
 * starting from some fork state.
 */
newtype Trace =
  Nil() or
  Step(InputSymbol s1, InputSymbol s2, Trace t) {
    exists (StatePair p |
      isReachableFromFork(_, p, t, _) and
      step(p, s1, s2, _)
    ) or
    t = Nil() and isFork(_, s1, s2, _, _)
  }

/**
 * Gets a character that is represented by both `c` and `d`.
 */
string intersect(InputSymbol c, InputSymbol d) {
  c = Char(result) and (
    d = Char(result) or
    exists (RegExpCharacterClass cc | d = CharClass(cc) |
      exists (RegExpTerm child | child = cc.getAChild() |
        result = child.(RegExpConstant).getValue() or
        exists (string lo, string hi | child.(RegExpCharacterRange).isRange(lo, hi) |
          lo <= result and result <= hi
        )
      )
    ) or
    d = Dot() and not (result = "\n" or result = "\r") or
    d = Any()
  ) or
  exists (RegExpCharacterClass cc | c = CharClass(cc) and result = choose(cc) |
    d = CharClass(cc) or
    d = Dot() and not (result = "\n" or result = "\r") or
    d = Any()
  ) or
  c = Dot() and (
    d = Dot() and result = "a" or
    d = Any() and result = "a"
  ) or
  c = Any() and d = Any() and result = "a"
  or
  result = intersect(d, c)
}

/**
 * Gets a character matched by character class `cc`.
 */
string choose(RegExpCharacterClass cc) {
  result = min(string c |
    exists (RegExpTerm child | child = cc.getAChild() |
      c = child.(RegExpConstant).getValue() or
      child.(RegExpCharacterRange).isRange(c, _)
    )
  )
}

/**
 * Gets a string corresponding to the trace `t`.
 */
string concretise(Trace t) {
  t = Nil() and result = ""
  or
  exists (InputSymbol s1, InputSymbol s2, Trace rest | t = Step(s1, s2, rest) |
    result = concretise(rest) + intersect(s1, s2)
  )
}

/**
 * Holds if `r` is reachable from `(fork, fork)` under input `w`, and there is
 * a path from `r` back to `(fork, fork)` with `rem` steps.
 */
predicate isReachableFromFork(State fork, StatePair r, Trace w, int rem) {
  exists (InputSymbol s1, InputSymbol s2, State q1, State q2 |
    isFork(fork, s1, s2, q1, q2) and
    r = MkStatePair(q1, q2) and
    w = Step(s1, s2, Nil()) and
    rem = statePairDist(r, MkStatePair(fork, fork))
  )
  or
  exists (StatePair p, Trace v, InputSymbol s1, InputSymbol s2 |
    isReachableFromFork(fork, p, v, rem+1) and
    step(p, s1, s2, r) and
    w = Step(s1, s2, v) and
    rem > 0
  )
}

/**
 * Gets a state in the product automaton from which `(fork, fork)` is
 * reachable in zero or more epsilon transitions.
 */
StatePair getAForkPair(State fork) {
  isFork(fork, _, _, _, _) and
  result = mkStatePair(epsilonPred*(fork), epsilonPred*(fork))
}

/**
 * Holds if `fork` is a pumpable fork with word `w`.
 */
predicate isPumpable(State fork, string w) {
  exists (StatePair q, Trace t |
    isReachableFromFork(fork, q, t, _) and
    (
      q = getAForkPair(fork) and w = concretise(t)
      or
      exists (InputSymbol s1, InputSymbol s2 |
        step(q, s1, s2, getAForkPair(fork)) and
        w = concretise(Step(s1, s2, t))
      )
    )
  )
}

/**
 * Gets a state that can be reached from pumpable `fork` consuming
 * the first `i+1` characters of `w`.
 */
State process(State fork, string w, int i) {
  isPumpable(fork, w) and
  exists (State prev | i = 0 and prev = fork or prev = process(fork, w, i-1) |
    exists (InputSymbol s, string c | deltaClosed(prev, s, result) and c = w.charAt(i) |
      s = Char(c) or
      s = Dot() and c != "\n" and c != "\r" or
      s = Any()
    )
  )
}

/**
 * Gets the result of backslash-escaping newlines, carriage-returns and
 * backslashes in `s`.
 */
bindingset[s]
string escape(string s) {
  result = s.replaceAll("\\", "\\\\").replaceAll("\n", "\\n").replaceAll("\r", "\\r")
}

from RegExpTerm t, string c
where c = min(string w | isPumpable(Match(t), w)) and not isPumpable(epsilonSucc+(Match(t)), _) and
      not epsilonSucc*(process(Match(t), c, c.length()-1)) = Accept(_)
select t, "This part of the regular expression may cause exponential backtracking on strings " +
          "containing many repetitions of '" + escape(c) + "'."