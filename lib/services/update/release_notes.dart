import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/router/page_utils.dart';

class ReleaseNotes extends StatelessWidget {
  ReleaseNotes(String markdown, {super.key})
    : _document = markdown.trim().isEmpty ? null : _parse(markdown);

  final dom.Element? _document;

  static dom.Element _parse(String markdown) {
    final nodes = md.Document(
      encodeHtml: false,
      inlineSyntaxes: [md.AutolinkExtensionSyntax(), md.StrikethroughSyntax()],
    ).parse(markdown);
    return dom.Element.tag('html')..append(
      dom.Element.tag('body')..nodes.addAll(nodes.map(_toDom)),
    );
  }

  static dom.Node _toDom(md.Node node) {
    if (node is! md.Element) return dom.Text(node.textContent);
    if (node.tag == 'img') return dom.Text(node.attributes['alt'] ?? '');

    final href = node.attributes['href'];
    final uri = href == null ? null : Uri.tryParse(href);
    final safeLink =
        uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
    final element = dom.Element.tag(
      node.tag == 'a' && !safeLink ? 'span' : node.tag,
    );
    if (node.tag == 'a' && safeLink) {
      element.attributes['href'] = uri.toString();
    }
    if (node.attributes['start'] case final start? when node.tag == 'ol') {
      element.attributes['start'] = start;
    }
    element.nodes.addAll(node.children?.map(_toDom) ?? const []);
    return element;
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document == null) return const Text('本次发布未提供更新说明。');
    final colors = Theme.of(context).colorScheme;
    return Html.fromElement(
      documentElement: document,
      onLinkTap: (url, _, _) {
        if (url != null) PageUtils.launchURL(url);
      },
      style: {
        'body': Style(margin: Margins.zero),
        'p': Style(margin: Margins.only(bottom: 8)),
        'h1': Style(fontSize: FontSize.larger, margin: Margins.only(bottom: 8)),
        'h2, h3': Style(
          fontSize: FontSize.larger,
          margin: Margins.only(top: 8, bottom: 4),
        ),
        'a': Style(color: colors.primary),
      },
    );
  }
}
