import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

final _dependenciesByPath = <String, List<String>>{};

CompilationUnit parseSource(String source) =>
    parseString(content: source, throwIfDiagnostics: false).unit;

Iterable<String> sourceDependencies(String source) sync* {
  for (final directive in parseSource(source).directives) {
    if (directive is UriBasedDirective) {
      if (directive.uri.stringValue case final uri?) yield uri;
    }
    if (directive is NamespaceDirective) {
      for (final configuration in directive.configurations) {
        if (configuration.uri.stringValue case final uri?) yield uri;
      }
    }
  }
}

Iterable<String> dependencies(File file) => _dependenciesByPath.putIfAbsent(
  file.path,
  () => sourceDependencies(file.readAsStringSync()).toList(),
);

String? localDependency(File file, String uri) {
  const prefix = 'package:pili_aurora_next/';
  if (uri.startsWith(prefix)) return uri.substring(prefix.length);
  if (uri.contains(':')) return null;
  return path
      .relative(path.normalize(path.join(file.parent.path, uri)), from: 'lib')
      .replaceAll('\\', '/');
}

Set<String> matchingStaticCalls(String source, Set<String> candidates) {
  final visitor = _StaticCallVisitor(candidates);
  parseSource(source).accept(visitor);
  return visitor.calls;
}

class _StaticCallVisitor extends RecursiveAstVisitor<void> {
  _StaticCallVisitor(this.candidates);

  final Set<String> candidates;
  final calls = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final type = switch (node.target) {
      SimpleIdentifier(:final name) => name,
      PrefixedIdentifier(:final identifier) => identifier.name,
      _ => null,
    };
    if (type != null) {
      final call = '$type.${node.methodName.name}';
      if (candidates.contains(call)) calls.add(call);
    }
    super.visitMethodInvocation(node);
  }
}
