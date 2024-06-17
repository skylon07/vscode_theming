import 'dart:mirrors';

import './syntax_printer.dart';
import './regexp_builder_base.dart';
import './regexp_recipes.dart';


abstract base class SyntaxDefinition<BuilderT extends RegExpBuilder<CollectionT>, CollectionT> {
  final String? scopePrefix;
  final bool isTextSyntax;
  final String langName;
  final List<String> fileTypes;

  final List<DefinitionItem> _repoItems = [];
  bool _isComputingInnerItems = false;
  StyleName? _parentStyleCache = null;
  String _parentIdentifierCache = "";
  int _currInnerItemsCreated = 0;

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
      repository: [for (var item in _repoItems) item.asRepositoryItem()],
    );
    _warnBadCollectionDeclarations();
    return body;
  }

  DefinitionItem createItem(
    String identifier,
    {
      StyleName? styleName,
      RegExpRecipe? match,
      RegExpPair? matchPair,
      Map<GroupRef, StyleName>? captures,
      Map<GroupRef, StyleName>? beginCaptures,
      Map<GroupRef, StyleName>? endCaptures,
      List<DefinitionItem>? Function()? innerItems,
    }
  ) {
    if (_isComputingInnerItems) throw StateError("`createItem()` must be called outside any inner-items lists.");
    var item = DefinitionItem._(
      identifier,
      isInline: false,
      baseSyntax: this,
      createBody: (debugName, innerPatterns) => 
        _smartCreateBody(
          styleName: styleName,
          match: match,
          matchPair: matchPair,
          captures: captures,
          beginCaptures: beginCaptures,
          endCaptures: endCaptures,
          
          debugName: debugName,
          innerPatterns: innerPatterns,
        ),
      createInnerItems: () => _smartCreateInnerItems(identifier, styleName, innerItems),
    );
    _repoItems.add(item);
    return item;
  }

  DefinitionItem createItemInline(
    {
      RegExpRecipe? match,
      RegExpPair? matchPair,
      Map<GroupRef, StyleName>? captures,
      Map<GroupRef, StyleName>? beginCaptures,
      Map<GroupRef, StyleName>? endCaptures,
      List<DefinitionItem>? Function()? innerItems,
    }
  ) {
    if (!_isComputingInnerItems) throw StateError("`createItemInline()` can only be called inside an inner items list.");
    var parentStyleName = _parentStyleCache;
    var parentIdentifier = _parentIdentifierCache;
    ++_currInnerItemsCreated;
    
    var identifier = "$parentIdentifier.pattern$_currInnerItemsCreated";
    return DefinitionItem._(
      "$parentIdentifier.pattern$_currInnerItemsCreated",
      isInline: true,
      baseSyntax: this,
      createBody: (debugName, innerPatterns) => 
        _smartCreateBody(
          match: match,
          matchPair: matchPair,
          captures: captures,
          beginCaptures: beginCaptures,
          endCaptures: endCaptures,

          styleName: parentStyleName,

          debugName: debugName,
          innerPatterns: innerPatterns,
        ),
      createInnerItems: () => _smartCreateInnerItems(identifier, parentStyleName, innerItems),
    );
  }

  Pattern _smartCreateBody({
    required String debugName,
    required StyleName? styleName,
    required RegExpRecipe? match,
    required RegExpPair? matchPair,
    required Map<GroupRef, StyleName>? captures,
    required Map<GroupRef, StyleName>? beginCaptures,
    required Map<GroupRef, StyleName>? endCaptures,
    required List<Pattern>? innerPatterns,
  }) {
    var args = (
      debugName: debugName,
      styleName: styleName,
      match: match,
      matchPair: matchPair,
      captures: captures,
      beginCaptures: beginCaptures,
      endCaptures: endCaptures,
      innerPatterns: innerPatterns,
    );
    return switch (args) {
      (
        debugName: String debugName,
        match: RegExpRecipe match,

        styleName: StyleName? styleName,
        captures: Map<GroupRef, StyleName>? captures,
        
        matchPair: null,
        beginCaptures: null,
        endCaptures: null,
        innerPatterns: null || [],
       ) => 
        MatchPattern(
          debugName: debugName,
          styleName: styleName,
          match: match.compile(),
          captures: 
            (captures != null)? 
              _capturesAsPattern(captures, match, debugName, "captures")
            : const {},
        ),

      (
        debugName: String debugName,
        matchPair: RegExpPair matchPair,

        styleName: StyleName? styleName,
        beginCaptures: Map<GroupRef, StyleName>? beginCaptures,
        endCaptures: Map<GroupRef, StyleName>? endCaptures,
        innerPatterns: List<Pattern>? innerPatterns,

        match: null,
        captures: null,
      ) =>
        EnclosurePattern(
          debugName: debugName,
          styleName: styleName,
          innerPatterns: innerPatterns ?? [],
          begin: matchPair.begin.compile(),
          end: matchPair.end.compile(),
          beginCaptures:
            (beginCaptures != null)? 
              _capturesAsPattern(beginCaptures, matchPair.begin, debugName, "beginCaptures")
            : const {},
          endCaptures:
            (endCaptures != null)? 
              _capturesAsPattern(endCaptures, matchPair.end, debugName, "endCaptures")
            : const {},
        ),

      (
        debugName: String debugName,
        innerPatterns: List<Pattern> innerPatterns,

        styleName: StyleName? styleName,

        match: null,
        matchPair: null,
        captures: null,
        beginCaptures: null,
        endCaptures: null,
       ) when innerPatterns.isNotEmpty =>
        GroupingPattern(
          debugName: debugName,
          styleName: styleName,
          innerPatterns: innerPatterns
        ),
      
      _ => throw ArgumentError("Invalid argument pattern."),
    };
  }

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

  List<DefinitionItem>? _smartCreateInnerItems(String identifier, StyleName? styleName, List<DefinitionItem>? Function()? innerItems) {
    // using a style cache (and not a stack) assumes `createItem()`
    // cannot be called in the inner items
    _parentStyleCache = styleName;
    _parentIdentifierCache = identifier;
    _currInnerItemsCreated = 0;
    _isComputingInnerItems = true;

    var items = innerItems?.call();
    
    _isComputingInnerItems = false;
    _parentStyleCache = null;
    _parentIdentifierCache = "";
    _currInnerItemsCreated = 0;
    return items;
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
  final String identifier;
  final bool isInline;
  final Pattern Function(String debugName, List<Pattern> innerPatterns) createBody;
  final List<DefinitionItem>? Function()? createInnerItems;

  DefinitionItem._(
    this.identifier,
    {
      required this.baseSyntax,
      required this.createBody,
      required this.isInline,
      this.createInnerItems,
    }
  );

  late final innerItems = createInnerItems?.call() ?? [];

  RepositoryItem asRepositoryItem() => _repositoryItem;
  late final _repositoryItem = _whenInline(
    () => throw ArgumentError.notNull("identifier"),
    () => RepositoryItem(
      identifier: identifier,
      body: _body
    ),
  );
  
  Pattern asInnerItem() => _innerItemPattern;
  late final _innerItemPattern = _whenInline(
    () => _body,
    () => IncludePattern(identifier: identifier),
  );

  late final _body = createBody(
    "${baseSyntax.langName}.$identifier",
    [
      for (var item in innerItems)
        item.asInnerItem()
    ],
  );

  ResultT _whenInline<ResultT>(ResultT Function() isInline, ResultT Function() isNotInline) {
    return this.isInline ? isInline() : isNotInline();
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
