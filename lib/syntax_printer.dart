import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import './syntax_definition.dart';


/// Converts a [SyntaxElement] into its JSON string representation.
/// 
/// Each [SyntaxElement] represents a particular kind of TextMate JSON object.
/// This class simply provides methods for converting these objects into strings.
/// [print] is primarily responsible for this conversion, and [printToFile] can be
/// used to easily write the results to a file.
/// 
/// This class follows the singleton pattern, and the methods described above can
/// be accessed via [instance]. This instance requires no additional setup and
/// completely encapsulates the responsibilities of its encoder.
class SyntaxPrinter {
  /// The indentation used for each "scope" in the resulting JSON.
  static const INDENT = "    ";
  /// The singleton instance to use to access all printing methods.
  static final instance = SyntaxPrinter._create();

  /// The JSON encoder used to pretty-print a [SyntaxElement] into its JSON form.
  late final JsonEncoder _encoder = 
    JsonEncoder.withIndent(INDENT, (item) => item.toJson());

  /// A private constructor that creates an instance of this class.
  /// Instances should not be created and instead the singleton [instance] should
  /// be used.
  SyntaxPrinter._create();

  /// "Prints" a given [element] by converting it to a string containing its
  /// JSON representation. Each [SyntaxElement] represents a kind of JSON object,
  /// so passing any type of element is acceptable.
  String print(SyntaxElement element) {
    return _encoder.convert(element) + "\n";
  }

  /// "Prints" a given [element] to a given file [path]. Like [print], this function
  /// can convert any [SyntaxElement] into its JSON string representation. However,
  /// instead of returning the string, this function will write the resulting JSON
  /// into a file, returning a [Future] that can be used to `await` the completion
  /// of the operation.
  Future<void> printToFile(SyntaxElement element, String path) {
    var file = File(path);
    var contents = print(element);
    return file.writeAsString(contents);
  }
}

/// Guarantees that an implementor can work properly with the JSON encoding process.
abstract interface class JsonEncodable {
  /// Converts `this` and returns a [Map] representing a JSON object.
  /// This allows for easy integration with dart's [JsonEncoder] class.
  Map toJson();
}


/// The base class for various kinds of TextMate JSON elements. 
/// 
/// Each subtype of this is intended to be a data class/map for a separate kind
/// of TextMate element. (See each class' docstring for an example of what it represents.)
/// It is the responsibility of these subtypes to implement [toJson] and define
/// all properties needed to create the corresponding JSON representaton.
/// Some classes may also define conversion methods to other element types.
/// 
/// Subclasses of this *must* have [toJson] implemented, as guaranteed by the
/// [JsonEncodable] interface. This method is responsible for returning the actual
/// JSON representation of `this` element.
sealed class SyntaxElement implements JsonEncodable {
  const SyntaxElement();
}


// TODO: finish documenting from here on (does MainBody also need any additional info?)
/// Represents an entire TextMate object contained in a language file.
/// This includes the supported file types, the language scope name, root
/// patterns, and the named repository patterns.
/// 
/// ```
/// {
///     "fileTypes": [
///         "txt",
///         "dart",
///         // etc
///     ],
///     "scopeName": "language.scope.name",
///     "patterns": [
///         // <Pattern>,
///         // ...
///     ],
///     "repository": {
///       // <RepositoryItem>,
///       // ...
///     }
/// }
/// ```
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
  final bool _shouldTreatAsReference;

  const IncludePattern({required this.identifier, super.debugName = "", bool isRepoItemRef = true}) :
    _shouldTreatAsReference = isRepoItemRef;

  @override
  Map toJson() {
    return {
      ...super.toJson(),
      'include': _shouldTreatAsReference ? "#$identifier" : identifier,
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
