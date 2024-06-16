import 'dart:mirrors';

import './syntax_printer.dart';
import './regexp_builder_base.dart';
import './regexp_recipes.dart';


abstract base class SyntaxDefinition<BuilderT extends RegExpBuilder<CollectionT>, CollectionT> {
  final String? scopePrefix;
  final bool isTextSyntax;
  final String langName;
  final List<String> fileTypes;
  final List<DefinitionItem> _items = [];
  late final CollectionT collection;
  
  SyntaxDefinition({
    this.scopePrefix,
    required this.isTextSyntax,
    required this.langName,
    required this.fileTypes,
    required BuilderT builder,
  }) {
    collection = builder.createCollection();
  }

  List<DefinitionItem> get rootItems;

  late final mainBody = _createMainBody();
  MainBody _createMainBody() {
    var body = MainBody(
      scopePrefix: scopePrefix,
      isTextSyntax: isTextSyntax,
      langName: langName,
      fileTypes: fileTypes,
      topLevelPatterns: [for (var item in rootItems) item.asInnerItem()],
      repository: [
        for (var itemIdx = 0; itemIdx < _items.length; ++itemIdx) 
          _items[itemIdx].asRepositoryItem()
      ],
    );
    _warnBadCollectionDeclarations();
    return body;
  }

  DefinitionItem createItemDirect(
    String identifier,
    {
      required Pattern Function(String debugName, List<Pattern> innerPatterns) createBody,
      List<DefinitionItem>? Function()? innerItems,
    }
  ) {
    var item = DefinitionItem._(
      identifier,
      baseSyntax: this,
      createBody: createBody,
      calcInnerItems: innerItems,
    );
    _items.add(item);
    return item;
  }

  DefinitionItem createItem(
    String identifier,
    {
      StyleName? styleName,
      RegExpRecipe? match,
      RegExpPair? matchPair,
      RegExpRecipe? begin,
      RegExpRecipe? end,
      Map<GroupRef, StyleName>? captures,
      Map<GroupRef, StyleName>? beginCaptures,
      Map<GroupRef, StyleName>? endCaptures,
      List<DefinitionItem>? Function()? innerItems,
    }
  ) {
    var argMap = {
      'debugName': null, // set later
      'styleName': styleName,
      'match': match,
      'begin': begin ?? matchPair?.begin,
      'end': end ?? matchPair?.end,
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
      innerItems: innerItems,
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
        String? offendingReason = null;
        try {
          var collectionValue = collectionInstance.delegate(Invocation.getter(collectionDeclaration.simpleName));
          offendingReason = switch (collectionValue) {
            RegExpRecipe(hasCompiled: false) => "unused recipe",
            GroupRef(positionUsed: false) => "unused ref",
            RegExpPair(
              begin: RegExpRecipe(hasCompiled: var beginHasCompiled), 
              end: RegExpRecipe(hasCompiled: var endHasCompiled),
            ) => {
              (false, false): "unused (begin/end) recipe",
              (false, true): "unused (begin) recipe",
              (true, false): "unused (end) recipe",
              (true, true): null,
            }[(beginHasCompiled, endHasCompiled)],
            _ => null,
          };
        } catch (error) {
          offendingReason = "access error";
        }
        if (offendingReason != null) {
          offendingCollectionDeclarations.add((collectionDeclaration, offendingReason));
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
  final SyntaxDefinition baseSyntax;
  final String? identifier;
  final Pattern Function(String debugName, List<Pattern> innerPatterns) createBody;
  final List<DefinitionItem>? Function()? calcInnerItems;

  DefinitionItem._(
    this.identifier,
    {
      required this.baseSyntax,
      required this.createBody,
      this.calcInnerItems,
    }
  );

  late final innerItems = calcInnerItems?.call() ?? [];

  RepositoryItem asRepositoryItem() => _repositoryItem;
  late final _repositoryItem = _whenInline(
    () => throw ArgumentError.notNull("identifier"),
    (identifier) => RepositoryItem(
      identifier: identifier,
      body: _body
    ),
  );
  
  Pattern asInnerItem() => _innerItemPattern;
  late final _innerItemPattern = _whenInline(
    () => _body,
    (identifier) => IncludePattern(identifier: identifier),
  );

  late final _body = createBody(
    "${baseSyntax.langName}.$identifier",
    [
      for (var item in innerItems)
        item.asInnerItem()
    ],
  );

  ResultT _whenInline<ResultT>(ResultT Function() isInline, ResultT Function(String) isNotInline) {
    final identifier = this.identifier;
    var inline = identifier == null;
    return inline ? isInline() : isNotInline(identifier);
  }
}


abstract interface class StyleName {
  String get scope;
}


final class RegExpPair {
  final RegExpRecipe begin;
  final RegExpRecipe end;

  RegExpPair(this.begin, this.end);
}


extension _SymbolPrettyStrings on Symbol {
  String toPrettyString() {
    var str = toString();
    return str.substring("Symbol(\"".length, str.length - "\")".length);
  }
}
