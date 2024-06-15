import 'dart:mirrors';

import './syntax_printer.dart';
import './regexp_builder_base.dart';
import './regexp_recipes.dart';


abstract base class SyntaxDefinition<BuilderT extends RegExpBuilder<CollectionT>, CollectionT> {
  final String langName;
  final bool isTextSyntax;
  final List<String> fileTypes;
  final List<DefinitionItem> _items = [];
  late final CollectionT collection;
  
  SyntaxDefinition({
    required this.langName,
    required this.isTextSyntax,
    required this.fileTypes,
    required BuilderT builder,
  }) {
    collection = builder.createCollection();
  }

  List<DefinitionItem> get rootItems;

  late final mainBody = _createMainBody();
  // TODO: is there a way to add tests for this?
  MainBody _createMainBody() {
    var body = MainBody(
      fileTypes: fileTypes,
      langName: langName,
      topLevelPatterns: [for (var item in rootItems) item.asIncludePattern()],
      repository: [for (var item in _items) item.asRepositoryItem()],
    );
    _warnBadCollectionDeclarations();
    return body;
  }

  DefinitionItem createItemDirect(
    String identifier,
    {
      required Pattern Function(String debugName, List<Pattern> innerPatterns) createBody,
      List<DefinitionItem>? Function()? createInnerItems,
    }
  ) {
    var item = DefinitionItem._(
      identifier,
      parent: this,
      createBody: createBody,
      createInnerItems: createInnerItems,
    );
    _items.add(item);
    return item;
  }

  DefinitionItem createItem(
    String identifier,
    {
      StyleName? styleName,
      RegExpRecipe? match,
      RegExpRecipe? begin,
      RegExpRecipe? end,
      Map<GroupRef, StyleName>? captures,
      Map<GroupRef, StyleName>? beginCaptures,
      Map<GroupRef, StyleName>? endCaptures,
      List<DefinitionItem>? Function()? createInnerItems,
    }
  ) {
    var argMap = {
      'debugName': null, // set later
      'styleName': styleName,
      'match': match,
      'begin': begin,
      'end': end,
      'captures': captures,
      'beginCaptures': beginCaptures,
      'endCaptures': endCaptures,
      'innerPatterns': null, // set later
    };
    return createItemDirect(
      identifier,
      createBody: (debugName, innerPatterns) {
        argMap['debugName'] = debugName;
        argMap['innerPatterns'] = innerPatterns;
        return _createItem_smartBody(argMap);
      },
      createInnerItems: createInnerItems,
    );
  }

  Pattern _createItem_smartBody(Map<String, dynamic> argMap) =>
    switch (argMap) {
      {
        'debugName': String debugName,
        'match': RegExpRecipe match,

        'styleName': StyleName? styleName,
        'captures': Map<GroupRef, StyleName>? captures,
        
        'begin': null,
        'end': null,
        'beginCaptures': null,
        'endCaptures': null,
        'innerPatterns': null || [],
      } => 
        MatchPattern(
          debugName: debugName,
          styleName: styleName,
          match: match.compile(),
          captures: 
            (captures != null)? 
              _capturesAsPattern(captures, match, debugName, "captures")
            : const {},
        ),

      {
        'debugName': String debugName,
        'begin': RegExpRecipe begin,
        'end': RegExpRecipe end,

        'styleName': StyleName? styleName,
        'beginCaptures': Map<GroupRef, StyleName>? beginCaptures,
        'endCaptures': Map<GroupRef, StyleName>? endCaptures,
        'innerPatterns': List<Pattern>? innerPatterns,

        'match': null,
        'captures': null,
      } =>
        EnclosurePattern(
          debugName: debugName,
          styleName: styleName,
          innerPatterns: innerPatterns ?? [],
          begin: begin.compile(),
          end: end.compile(),
          beginCaptures:
            (beginCaptures != null)? 
              _capturesAsPattern(beginCaptures, begin, debugName, "beginCaptures")
            : const {},
          endCaptures:
            (endCaptures != null)? 
              _capturesAsPattern(endCaptures, end, debugName, "endCaptures")
            : const {},
        ),

      {
        'debugName': String debugName,
        'innerPatterns': List<Pattern> innerPatterns,

        'styleName': StyleName? styleName,

        'match': null,
        'begin': null,
        'end': null,
        'captures': null,
        'beginCaptures': null,
        'endCaptures': null,
      } when innerPatterns.isNotEmpty =>
        GroupingPattern(
          debugName: debugName,
          styleName: styleName,
          innerPatterns: innerPatterns
        ),
      
      _ => throw ArgumentError("Invalid argument pattern."),
    };

  Map<int, CapturePattern> _capturesAsPattern(Map<GroupRef, StyleName> captures, RegExpRecipe recipe, String itemDebugName, String captureKeyName) {
    var patterns = <int, CapturePattern>{};
    for (var MapEntry(key: ref, value: styleName) in captures.entries) {
      var capturePosition = recipe.positionOf(ref);
      patterns[capturePosition] = 
        CapturePattern(
          debugName: "$itemDebugName.$captureKeyName[$capturePosition]",
          styleName: styleName,
        );
    }
    return patterns;
  }

  void _warnBadCollectionDeclarations() {
    var collectionInstance = reflect(collection);
    var offendingCollectionDeclarations = <(VariableMirror, String)>[];
    for (var collectionDeclaration in collectionInstance.type.declarations.values) {
      // check it isn't a constructor, method, etc.
      if (collectionDeclaration is VariableMirror) {
        try {
          var collectionValue = collectionInstance.delegate(Invocation.getter(collectionDeclaration.simpleName));
          var offendingReason = switch (collectionValue) {
            RegExpRecipe(hasCompiled: false) => "unused recipe",
            GroupRef(positionUsed: false) => "unused ref",
            _ => null,
          };
          if (offendingReason != null) {
            offendingCollectionDeclarations.add((collectionDeclaration, offendingReason));
          }
        } catch (error) {
          offendingCollectionDeclarations.add((collectionDeclaration, "access error"));
        }
      }
    }
    if (offendingCollectionDeclarations.isNotEmpty) {
      print("Warning: Bad declarations found in collection '${collectionInstance.type.simpleName.toPrettyString()}':");
      for (var (offendingDeclaration, reason) in offendingCollectionDeclarations) {
        print("  - '${offendingDeclaration.simpleName.toPrettyString()}': $reason");
      }
    }
  }
}

final class DefinitionItem {
  final SyntaxDefinition parent;
  final String identifier;
  final Pattern Function(String debugName, List<Pattern> innerPatterns) createBody;
  final List<DefinitionItem>? Function()? createInnerItems;

  DefinitionItem._(
    this.identifier,
    {
      required this.parent,
      required this.createBody,
      this.createInnerItems,
    }
  );

  late final innerItems = createInnerItems?.call() ?? [];

  RepositoryItem asRepositoryItem() => _repositoryItem;
  late final _repositoryItem = RepositoryItem(
    identifier: identifier,
    body: createBody(
      "${parent.langName}.$identifier",
      innerItems
        .map((item) => item.asIncludePattern())
        .toList(),
    )
  );

  IncludePattern asIncludePattern() => _includePattern;
  late final _includePattern = IncludePattern(identifier: identifier);
}


abstract interface class StyleName {
  String get scope;
}


extension _SymbolPrettyStrings on Symbol {
  String toPrettyString() {
    var str = toString();
    return str.substring("Symbol(\"".length, str.length - "\")".length);
  }
}
