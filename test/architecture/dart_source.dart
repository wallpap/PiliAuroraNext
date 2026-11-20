import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

final _dependenciesByPath = <String, List<String>>{};

Iterable<File> dartFiles(String root) sync* {
  for (final entry in Directory(root).listSync(followLinks: false)) {
    if (entry is Directory) {
      final relative = path.relative(entry.path).replaceAll('\\', '/');
      if (relative == 'lib/generated/bilibili') continue;
      yield* dartFiles(entry.path);
    } else if (entry is File &&
        entry.path.endsWith('.dart') &&
        !entry.path.endsWith('.g.dart')) {
      yield entry;
    }
  }
}

String libPath(File file) =>
    path.relative(file.path, from: 'lib').replaceAll('\\', '/');

bool featureLayer(String source, String layer) {
  final segments = source.split('/');
  return segments.length >= 4 &&
      segments.first == 'features' &&
      segments[2] == layer;
}

bool isPresentation(String source) =>
    source.startsWith('pages/') ||
    source.startsWith('common/widgets/') ||
    source.startsWith('plugin/pl_player/view/') ||
    featureLayer(source, 'presentation');

CompilationUnit parseSource(String source) =>
    parseString(content: source, throwIfDiagnostics: false).unit;

Iterable<String> sourceDependencies(String source) =>
    unitDependencies(parseSource(source));

Iterable<String> unitDependencies(CompilationUnit unit) sync* {
  for (final directive in unit.directives) {
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

Iterable<({String name, String base})> typeInheritance(
  CompilationUnit unit,
) sync* {
  for (final declaration in unit.declarations) {
    final (name, bases) = switch (declaration) {
      ClassDeclaration node => (
        node.namePart.typeName.lexeme,
        [
          ?node.extendsClause?.superclass,
          ...?node.withClause?.mixinTypes,
          ...?node.implementsClause?.interfaces,
        ],
      ),
      ClassTypeAlias node => (
        node.name.lexeme,
        [
          node.superclass,
          ...node.withClause.mixinTypes,
          ...?node.implementsClause?.interfaces,
        ],
      ),
      MixinDeclaration node => (
        node.name.lexeme,
        [
          ...?node.onClause?.superclassConstraints,
          ...?node.implementsClause?.interfaces,
        ],
      ),
      GenericTypeAlias(name: final name, type: NamedType type) => (
        name.lexeme,
        [type],
      ),
      _ => ('', const <NamedType>[]),
    };
    for (final base in bases) {
      yield (name: name, base: base.name.lexeme);
    }
  }
}

Iterable<String> dependencies(File file) => _dependenciesByPath.putIfAbsent(
  file.path,
  () => sourceDependencies(file.readAsStringSync()).toList(),
);

String? localDependency(File file, String uri) {
  const prefix = 'package:pili_aurora_next/';
  final parsed = Uri.parse(uri);
  final location = parsed.pathSegments.join('/');
  if (uri.startsWith(prefix)) {
    return path.posix.normalize(location.substring('pili_aurora_next/'.length));
  }
  if (parsed.hasScheme || parsed.hasAuthority) return null;
  return libPath(File(path.join(file.parent.path, location)));
}

Set<String> matchingStaticCalls(String source, Set<String> candidates) =>
    matchingUnitStaticCalls(parseSource(source), candidates);

Set<String> matchingUnitStaticCalls(
  CompilationUnit unit,
  Set<String> candidates,
) {
  final visitor = _StaticCallVisitor(candidates);
  unit.accept(visitor);
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
      MethodInvocation(target: null, :final methodName) => methodName.name,
      InstanceCreationExpression(:final constructorName) =>
        constructorName.type.name.lexeme,
      _ => null,
    };
    if (type != null) {
      final call = '$type.${node.methodName.name}';
      if (candidates.contains(call)) calls.add(call);
    }
    super.visitMethodInvocation(node);
  }
}
