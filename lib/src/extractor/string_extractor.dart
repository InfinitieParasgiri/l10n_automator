import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config/config.dart';
import 'candidate.dart';
import 'classifier.dart';
import 'interpolation_handler.dart';

/// Walks a parsed Dart file and emits a [Candidate] for every string literal
/// encountered, with full call-site context attached.
class StringExtractor {
  StringExtractor(this.config) : classifier = Classifier(config);

  final Config config;
  final Classifier classifier;

  List<Candidate> extract(String filePath, String source, CompilationUnit unit) {
    final visitor = _Visitor(filePath, source, config, classifier);
    unit.accept(visitor);
    return visitor.candidates;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.filePath, this.source, this.config, this.classifier);

  final String filePath;
  final String source;
  final Config config;
  final Classifier classifier;
  final List<Candidate> candidates = [];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _handle(node);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    // Treat the adjacent group as one literal. Skip the children to avoid
    // double-emitting.
    _handle(node);
    // Intentionally not calling super to avoid revisiting children.
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    _handle(node);
    // Visit only the interpolation expressions, not the literal pieces.
    for (final element in node.elements) {
      if (element is InterpolationExpression) {
        element.expression.accept(this);
      }
    }
  }

  void _handle(StringLiteral node) {
    // 1) Comment directives on the line before.
    final directives = _readDirectives(node);
    if (directives.ignore) return;

    // 2) Interpolation handling.
    InterpolationConversion conv;
    var hasInterp = false;
    if (node is SimpleStringLiteral) {
      conv = InterpolationHandler.fromSimple(node);
    } else if (node is AdjacentStrings) {
      conv = InterpolationHandler.fromAdjacent(node);
      hasInterp = node.strings.any((s) => s is StringInterpolation);
    } else if (node is StringInterpolation) {
      conv = InterpolationHandler.fromInterpolation(node);
      hasInterp = true;
    } else {
      return;
    }

    // 3) Gather call-site context.
    final ctx = _gatherContext(node);

    // 4) BuildContext availability.
    final hasContext = _hasBuildContextInScope(node);

    // 5) Classify.
    final result = classifier.classify(
      value: conv.arbValue,
      context: ctx,
      hasInterpolation: hasInterp,
    );

    // Always emit — the pipeline filters by decision later. The reporter
    // needs to know about skipped strings too.
    candidates.add(Candidate(
      filePath: filePath,
      source: source,
      node: node,
      literalValue: conv.arbValue,
      hasInterpolation: hasInterp,
      interpolationPlaceholders: conv.placeholders,
      parentContextDescription: ctx.parentDescription,
      hasBuildContextInScope: hasContext,
      decision: result.decision,
      reason: result.reason,
      overrideKey: directives.keyOverride,
    ));
  }

  // ---------------------------------------------------------------------------
  // Context gathering
  // ---------------------------------------------------------------------------

  CallSiteContext _gatherContext(StringLiteral node) {
    String? methodName;
    String? constructorName;
    String? namedArgument;
    int? positionalIndex;
    var isInAnnotation = false;
    var isInAssertMessage = false;
    var isInThrow = false;
    var isInMapKey = false;
    var isInIndex = false;
    var isInImport = false;
    var isInLog = false;
    var isTopLevelConst = false;
    var isInBinaryConcat = false;
    var isInRouteNamedArg = false;
    var isInConstContext = false;
    var parentDesc = 'unknown';

    AstNode? cur = node.parent;
    AstNode? child = node;
    while (cur != null) {
      if (cur is NamedExpression) {
        namedArgument = cur.name.label.name;
        if (namedArgument == 'name' || namedArgument == 'routeName') {
          // Could be route — let context above (Navigator/GoRoute) confirm.
          isInRouteNamedArg = true;
        }
      } else if (cur is ArgumentList) {
        // Determine positional index by counting prior positional args.
        if (namedArgument == null) {
          var idx = 0;
          for (final arg in cur.arguments) {
            if (arg == child || _wraps(arg, child!)) break;
            if (arg is! NamedExpression) idx++;
          }
          positionalIndex = idx;
        }
      } else if (cur is MethodInvocation) {
        methodName = cur.methodName.name;
        final target = cur.target?.toSource();
        if (target != null) methodName = '$target.$methodName';
        parentDesc = '$methodName(...)';
        if (methodName == 'pushNamed' ||
            methodName == 'pushReplacementNamed' ||
            methodName == 'pushNamedAndRemoveUntil' ||
            (methodName?.endsWith('.pushNamed') ?? false)) {
          isInRouteNamedArg = true;
        }
        if (methodName == 'print' ||
            methodName == 'debugPrint' ||
            (methodName?.endsWith('.log') ?? false)) {
          isInLog = true;
        }
        break;
      } else if (cur is InstanceCreationExpression) {
        final ctorName = cur.constructorName;
        final type = ctorName.type.qualifiedName;
        final name = ctorName.name?.name;
        constructorName = name == null ? type : '$type.$name';
        parentDesc = '$constructorName(...)';
        if (cur.keyword?.lexeme == 'const' || cur.isConst) {
          isInConstContext = true;
        } else {
          // Walk above this ctor to find an enclosing const literal/ctor
          // that would force this expression into a const context too.
          isInConstContext = _enclosingConstContext(cur);
        }
        break;
      } else if (cur is Annotation) {
        isInAnnotation = true;
        parentDesc = '@${cur.name.name}(...)';
        break;
      } else if (cur is AssertInitializer || cur is AssertStatement) {
        isInAssertMessage = true;
        parentDesc = 'assert(...)';
        break;
      } else if (cur is ThrowExpression) {
        isInThrow = true;
        parentDesc = 'throw ...';
        // Don't break — keep going to capture inner ctor name (Exception, etc.)
      } else if (cur is MapLiteralEntry && child == cur.key) {
        isInMapKey = true;
        parentDesc = 'map literal key';
        break;
      } else if (cur is IndexExpression && child == cur.index) {
        isInIndex = true;
        parentDesc = 'index lookup';
        break;
      } else if (cur is ImportDirective ||
          cur is ExportDirective ||
          cur is PartDirective) {
        isInImport = true;
        parentDesc = 'import/export directive';
        break;
      } else if (cur is BinaryExpression && cur.operator.lexeme == '+') {
        isInBinaryConcat = true;
        // Continue walking up for outer context.
      } else if (cur is TopLevelVariableDeclaration) {
        if (cur.variables.isConst) {
          isTopLevelConst = true;
          parentDesc = 'top-level const';
        }
        break;
      } else if (cur is FieldDeclaration && cur.fields.isConst) {
        isTopLevelConst = true; // class-level const, same review treatment
        parentDesc = 'class-level const';
        break;
      }
      child = cur;
      cur = cur.parent;
    }

    return CallSiteContext(
      methodName: methodName,
      constructorName: constructorName,
      namedArgument: namedArgument,
      positionalIndex: positionalIndex,
      isInAnnotation: isInAnnotation,
      isInAssertMessage: isInAssertMessage,
      isInThrow: isInThrow,
      isInMapLiteralKey: isInMapKey,
      isInIndexExpression: isInIndex,
      isInImport: isInImport,
      isInLogCall: isInLog,
      isTopLevelConst: isTopLevelConst,
      isInBinaryConcat: isInBinaryConcat,
      isInRouteNamedArg: isInRouteNamedArg,
      isInConstContext: isInConstContext,
      parentDescription: parentDesc,
    );
  }

  /// Returns true if any ancestor of [node] is a const expression that
  /// would force [node] (and its arguments) to be evaluated as const too.
  bool _enclosingConstContext(AstNode node) {
    AstNode? cur = node.parent;
    while (cur != null) {
      if (cur is InstanceCreationExpression &&
          (cur.keyword?.lexeme == 'const' || cur.isConst)) {
        return true;
      }
      if (cur is ListLiteral && cur.constKeyword?.lexeme == 'const') {
        return true;
      }
      if (cur is SetOrMapLiteral && cur.constKeyword?.lexeme == 'const') {
        return true;
      }
      // Stop at function/method boundaries — once we cross a closure, the
      // outer const-ness no longer cascades.
      if (cur is FunctionBody || cur is BlockFunctionBody) return false;
      cur = cur.parent;
    }
    return false;
  }

  bool _wraps(AstNode container, AstNode target) {
    AstNode? n = target;
    while (n != null) {
      if (n == container) return true;
      n = n.parent;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // BuildContext availability
  // ---------------------------------------------------------------------------

  bool _hasBuildContextInScope(AstNode node) {
    AstNode? cur = node.parent;
    while (cur != null) {
      if (cur is FunctionExpression) {
        if (_paramsContainBuildContext(cur.parameters)) return true;
      } else if (cur is MethodDeclaration) {
        if (_paramsContainBuildContext(cur.parameters)) return true;
      } else if (cur is FunctionDeclaration) {
        if (_paramsContainBuildContext(
            cur.functionExpression.parameters)) {
          return true;
        }
      } else if (cur is ConstructorDeclaration) {
        if (_paramsContainBuildContext(cur.parameters)) return true;
      } else if (cur is ClassDeclaration) {
        // If the surrounding class extends State<...>, it has `context` getter.
        final ext = cur.extendsClause?.superclass.qualifiedName ?? '';
        if (ext == 'State' || ext.startsWith('State<')) return true;
      }
      cur = cur.parent;
    }
    return false;
  }

  bool _paramsContainBuildContext(FormalParameterList? params) {
    if (params == null) return false;
    for (final p in params.parameters) {
      final type = _paramTypeName(p);
      if (type != null && type.contains('BuildContext')) return true;
    }
    return false;
  }

  String? _paramTypeName(FormalParameter param) {
    final inner = param is DefaultFormalParameter ? param.parameter : param;
    if (inner is SimpleFormalParameter) return inner.type?.toSource();
    if (inner is FieldFormalParameter) return inner.type?.toSource();
    if (inner is SuperFormalParameter) return inner.type?.toSource();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Comment directives
  // ---------------------------------------------------------------------------

  _Directives _readDirectives(AstNode node) {
    var ignore = false;
    String? keyOverride;
    // Walk preceding comments on the begin token.
    Token? comment = node.beginToken.precedingComments;
    while (comment != null) {
      final lex = comment.lexeme;
      if (lex.contains('l10n:ignore')) ignore = true;
      final keyMatch = RegExp(r'l10n:key=([A-Za-z_][A-Za-z0-9_]*)')
          .firstMatch(lex);
      if (keyMatch != null) keyOverride = keyMatch.group(1);
      comment = comment.next;
    }
    // Also check the parent statement's preceding comments (a directive on the
    // line above the statement applies to anything inside).
    final stmt = _enclosingStatement(node);
    if (stmt != null && stmt.beginToken != node.beginToken) {
      Token? c = stmt.beginToken.precedingComments;
      while (c != null) {
        final lex = c.lexeme;
        if (lex.contains('l10n:ignore')) ignore = true;
        final keyMatch = RegExp(r'l10n:key=([A-Za-z_][A-Za-z0-9_]*)')
            .firstMatch(lex);
        if (keyMatch != null) keyOverride ??= keyMatch.group(1);
        c = c.next;
      }
    }
    return _Directives(ignore: ignore, keyOverride: keyOverride);
  }

  AstNode? _enclosingStatement(AstNode node) {
    AstNode? cur = node.parent;
    while (cur != null) {
      if (cur is Statement) return cur;
      cur = cur.parent;
    }
    return null;
  }
}

class _Directives {
  _Directives({required this.ignore, required this.keyOverride});
  final bool ignore;
  final String? keyOverride;
}

extension on NamedType {
  String get qualifiedName {
    final args = typeArguments;
    return args == null ? name2.lexeme : '${name2.lexeme}${args.toSource()}';
  }
}
