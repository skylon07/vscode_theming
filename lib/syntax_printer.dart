import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import './syntax_definition.dart';


// TODO: document all classes here; include a code block showing a "template"
//  that illustrates the kind of pattern the class is emulating

class SyntaxPrinter {
  static const INDENT = "    ";
  static final instance = SyntaxPrinter._create();

  late final JsonEncoder _encoder = 
    JsonEncoder.withIndent(INDENT, (item) => item.toJson());

  SyntaxPrinter._create();

  String print(SyntaxElement syntax) {
    return _encoder.convert(syntax) + "\n";
  }

  Future<void> printToFile(SyntaxElement syntax, String path) {
    var file = File(path);
    var contents = print(syntax);
    return file.writeAsString(contents);
  }
}

abstract interface class JsonEncodable {
  Map toJson();
}


sealed class SyntaxElement implements JsonEncodable {
  const SyntaxElement();
}


final class MainBody extends SyntaxElement {
  final String? scopePrefix;
  final bool isTextSyntax;
  final String langName;
  final List<String> fileTypes;
  final List<Pattern> topLevelPatterns;
  final List<RepositoryItem> repository;

  const MainBody({
    this.scopePrefix,
    required this.isTextSyntax,
    required this.langName,
    required this.fileTypes,
    required this.topLevelPatterns,
    required this.repository,
  });

  @override
  Map toJson() {
    var prefix = (scopePrefix != null)? "$scopePrefix." : "";
    var scopeType = isTextSyntax ? "text" : "source";
    return {
      "fileTypes": fileTypes,
      "scopeName": "$prefix$scopeType.$langName",
      "patterns": topLevelPatterns,
      "repository": {
        for (var item in repository)
          item.identifier: item,
      },
    };
  }
}

final class RepositoryItem extends SyntaxElement {
  final String identifier;
  final Pattern body;

  const RepositoryItem({
    required this.identifier,
    required this.body,
  });

  @override
  Map toJson() {
    // it is the containing object's resposibility to
    // assign the correct identifier
    return body.toJson();
  }

  IncludePattern asInclude() => IncludePattern(identifier: identifier);
}

sealed class Pattern extends SyntaxElement {
  final String debugName;
  final StyleName? styleName;

  const Pattern({
    required this.debugName,
    this.styleName,
  });

  @override
  @mustBeOverridden
  @mustCallSuper
  Map toJson() {
    final styleName = this.styleName;
    var name =
      "${styleName != null ? "${styleName.scope} " : ""}"
      "${debugName.isNotEmpty ? "debugName.$debugName" : ""}";
    return {
      if (name.isNotEmpty)
        'name': name,
    };
  }
}

final class MatchPattern extends Pattern {
  final String match;
  final Map<int, CapturePattern> captures;

  const MatchPattern({
    required super.debugName,
    super.styleName,
    required this.match,
    this.captures = const {},
  });

  @override
  Map toJson() {
    return {
      ...super.toJson(),
      'match': match,
      if (captures.isNotEmpty)
        'captures': captures.stringifyKeys(),
    };
  }
}

final class CapturePattern extends Pattern {
  CapturePattern({
    required super.debugName,
    super.styleName,
  });

  @override
  Map toJson() {
    return super.toJson();
  }
}

final class GroupingPattern extends Pattern {
  final List<Pattern> innerPatterns;

  const GroupingPattern({
    required super.debugName,
    super.styleName,
    required this.innerPatterns,
  });

  @override
  Map toJson() {
    return {  
      ...super.toJson(),
      if (innerPatterns.isNotEmpty)
        'patterns': innerPatterns,
    };
  }
}

final class EnclosurePattern extends GroupingPattern {
  final String begin;
  final String end;
  final Map<int, CapturePattern> beginCaptures;
  final Map<int, CapturePattern> endCaptures;

  const EnclosurePattern({
    required super.debugName,
    super.styleName,
    super.innerPatterns = const [],
    required this.begin,
    required this.end,
    this.beginCaptures = const {},
    this.endCaptures = const {},
  });

  @override
  Map toJson() {
    return {
      ...super.toJson(),
      'begin': begin,
      'end': end,
      if (beginCaptures.isNotEmpty)
        'beginCaptures': beginCaptures.stringifyKeys(),
      if (endCaptures.isNotEmpty)
        'endCaptures': endCaptures.stringifyKeys(),
    };
  }
}

final class IncludePattern extends Pattern {
  final String identifier;

  const IncludePattern({required this.identifier, super.debugName = ""});

  @override
  Map toJson() {
    var shouldTreatAsReference = identifier.isNotEmpty && identifier[0] != "%";
    return {
      ...super.toJson(),
      'include': shouldTreatAsReference ? "#$identifier" : identifier.substring(1),
    };
  }
}


extension _IndexMapping<ItemT> on List<ItemT> {
  Map<String, ItemT> toIndexedMap() =>
    {
      for (var idx = 0; idx < length; ++idx)
        '${idx + 1}': this[idx]
    };
}

extension _IndexStringification<ItemT> on Map<dynamic, ItemT>{ 
  Map<String, ItemT> stringifyKeys() => 
    {
      for (var MapEntry(:key, :value) in entries)
        "$key": value
    };
}
