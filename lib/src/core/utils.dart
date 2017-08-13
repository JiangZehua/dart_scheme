library cs61a_scheme.core.utils;

import 'expressions.dart';
import 'logging.dart';
import 'procedures.dart';

void checkForm(Expression expressions, int min, [int max = -1]) {
  if (expressions is PairOrEmpty && expressions.isWellFormedList()) {
    int length = expressions.length;
    if (length < min) throw new SchemeException("$expressions must contain at least $min items.");
    if (max > -1 && length > max) {
      throw new SchemeException("$expressions may contain at most $max items.");
    }
    return;
  } 
  throw new SchemeException("$expressions is not a valid list.");
}

void checkFormals(Expression formals) {
  var symbols = new Set<SchemeSymbol>();
  void checkAndAdd(Expression symbol) {
    if (symbol is! SchemeSymbol) {
      throw new SchemeException("Non-symbol: $symbol");
    } else if (symbols.contains(symbol)) {
      throw new SchemeException("Duplicate symbol: $symbol");
    }
    symbols.add(symbol);
  }
  while (formals is Pair) {
    checkAndAdd(formals.pair.first);
    formals = formals.pair.second;
  }
  if (!formals.isNil) checkAndAdd(formals);
}

Expression schemeEval(Expression expr, Frame env) {
  return completeEval(expr.evaluate(env));
}

Expression schemeApply(Procedure procedure, PairOrEmpty args, Frame env) {
  return completeEval(procedure.apply(args, env));
}

Expression evalCallExpression(Pair expr, Frame env) {
  if (!expr.isWellFormedList()) {
    throw new SchemeException("Malformed list: $expr");
  }
  Expression first = expr.first;
  Expression rest = expr.second;
  if (first is SchemeSymbol && env.interpreter.specialForms.containsKey(first)) {
    var result = env.interpreter.specialForms[first](rest, env);
    env.interpreter.triggerEvent(first, new Pair(rest, env));
    return result;
  }
  return env.interpreter.implementation.evalProcedureCall(first, rest, env);
}

Expression completeEval(val) => val is Thunk ? val.evaluate(null) : val;

addPrimitive(Frame env, SchemeSymbol name, SchemePrimitive fn, int args) {
  env.define(name, new PrimitiveProcedure.fixed(name, fn, args), true);
}

addVariablePrimitive(Frame env, SchemeSymbol name, SchemePrimitive fn,
    int minArgs, [int maxArgs = -1]) {
  var p = new PrimitiveProcedure.variable(name, fn, minArgs, maxArgs);
  env.define(name, p, true);
}

Boolean b(bool val) => val ? schemeTrue : schemeFalse;
Number n(num dartNum) => dartNum is double ? d(dartNum) : i(dartNum as int);
Number i(int dartInt) => new Number.fromInteger(dartInt);
Number d(double dartDouble) => new Number.fromDouble(dartDouble);
Iterable<Number> allNumbers(List<Expression> expr) {
  return expr.map((ex) => ex is Number ? ex : throw new SchemeException("$ex is not a number."));
}
