import 'dart:mirrors';

import 'package:vscode_theming/vscode_theming.dart';

import './syntax_printer.dart';
import './regexp_builder_base.dart';
import './regexp_recipes.dart';


abstract base class SyntaxDefinition<BuilderT extends RegExpBuilder<CollectionT>, CollectionT> {
  final String? scopePrefix;
  final bool isTextSyntax;
  final String langName;
  final List<String> fileTypes;

  final List<ScopeUnit> _repoUnits = [];
  final _linker = _ScopeLinker();

  late final CollectionT collection;
  late final entireRecipe = GroupRef();
  
  SyntaxDefinition({
    this.scopePrefix,
    required this.isTextSyntax,
    required this.langName,
    required this.fileTypes,
    required BuilderT builder,
  }) {
    collection = builder.createCollection();
  }

  List<ScopeUnit> get rootUnits;
  late final self = ScopeUnit._(
    r"$self",
    isStandardRef: false,
    
    baseSyntax: this,
    createBody: (_, __) => throw UnimplementedError(r"$self has no body"),
    isInline: false,
  );

  late final mainBody = _createMainBody();
  MainBody _createMainBody() {
    var body = MainBody(
      scopePrefix: scopePrefix,
      isTextSyntax: isTextSyntax,
      langName: langName,
      fileTypes: fileTypes,
      topLevelPatterns: [for (var unit in rootUnits) unit.asInnerPattern()],
      repository: [
        for (var unitIdx = 0; unitIdx < _repoUnits.length; ++unitIdx) 
          _repoUnits[unitIdx].asRepositoryItem()
      ],
    );
    _warnBadCollectionDeclarations();
    return body;
  }

  ScopeUnit createUnit(
    String identifier,
    {
      StyleName? styleName,
      RegExpRecipe? match,
      RegExpPair? matchPair,
      Map<GroupRef, StyleName>? captures,
      Map<GroupRef, StyleName>? beginCaptures,
      Map<GroupRef, StyleName>? endCaptures,
      List<ScopeUnit>? Function()? innerUnits,
    }
  ) {
    var unit = ScopeUnit._(
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
      createInnerUnits: () => _linker.linkInnerUnits(
        innerUnits: innerUnits,
        parentStyleName: styleName,
        parentIdentifier: identifier,
      ),
    );
    _repoUnits.add(unit);
    return unit;
  }

  ScopeUnit createUnitInline(
    {
      StyleName? styleName,
      RegExpRecipe? match,
      RegExpPair? matchPair,
      Map<GroupRef, StyleName>? captures,
      Map<GroupRef, StyleName>? beginCaptures,
      Map<GroupRef, StyleName>? endCaptures,
      List<ScopeUnit>? Function()? innerUnits,
    }
  ) {
    if (!_linker.isLinkingInnerUnits) throw StateError("`createUnitInline()` units can only be used inside an 'inner units' list. (Did you include one as a root unit?)");
    // linker values have to be read/stored now while in a valid linking state
    var identifier = "${_linker.parentIdentifier}.inline${_linker.countNewInline()}";
    var resolvedStyleName = styleName ?? _linker.parentStyle;
    
    return ScopeUnit._(
      identifier,
      isInline: true,
      baseSyntax: this,
      createBody: (debugName, innerPatterns) => 
        _smartCreateBody(
          match: match,
          matchPair: matchPair,
          captures: captures,
          beginCaptures: beginCaptures,
          endCaptures: endCaptures,

          styleName: resolvedStyleName,

          debugName: debugName,
          innerPatterns: innerPatterns,
        ),
      createInnerUnits: () => _linker.linkInnerUnits(
        innerUnits: innerUnits,
        parentStyleName: resolvedStyleName,
        parentIdentifier: identifier,
      ),
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

  Map<int, CapturePattern> _capturesAsPattern(Map<GroupRef, StyleName> captures, RegExpRecipe recipe, String unitDebugName, String captureKeyName) {
    var patterns = <int, CapturePattern>{};
    for (var MapEntry(key: ref, value: styleName) in captures.entries) {
      var capturePosition = ref == entireRecipe ? 0 : recipe.positionOf(ref);
      patterns[capturePosition] = 
        CapturePattern(
          debugName: "$unitDebugName.$captureKeyName[$capturePosition]",
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

final class ScopeUnit {
  final SyntaxDefinition baseSyntax;
  final String identifier;
  final bool isInline;
  final Pattern Function(String debugName, List<Pattern> innerPatterns) createBody;
  final List<ScopeUnit>? Function()? createInnerUnits;
  final bool _isStandardRef;

  ScopeUnit._(
    this.identifier,
    {
      required this.baseSyntax,
      required this.createBody,
      required this.isInline,
      this.createInnerUnits,
      bool isStandardRef = true,
    }
  ) : _isStandardRef = isStandardRef;

  late final innerUnits = createInnerUnits?.call() ?? [];

  RepositoryItem asRepositoryItem() => _repositoryItem;
  late final _repositoryItem = !this.isInline ?
    RepositoryItem(
      identifier: identifier,
      body: _body
    ) :
    throw StateError("cannot be an inline unit");
  
  Pattern asInnerPattern() => _innerPattern;
  late final _innerPattern = this.isInline ? _body : IncludePattern(identifier: identifier, isRepoItemRef: _isStandardRef);

  late final _body = createBody(
    "${baseSyntax.langName}.$identifier",
    [
      for (var unit in innerUnits)
        unit.asInnerPattern()
    ],
  );
}


abstract interface class StyleName {
  String get scope;
}

final class RegExpPair {
  final RegExpRecipe begin;
  final RegExpRecipe end;

  RegExpPair(this.begin, this.end);

  RegExpRecipe asSingleRecipe([RegExpRecipe? between]) => regExpBuilder.concat([
    begin,
    between ?? regExpBuilder.zeroOrMore(regExpBuilder.anything),
    end,
  ]);
}


extension _SymbolPrettyStrings on Symbol {
  String toPrettyString() {
    var str = toString();
    return str.substring("Symbol(\"".length, str.length - "\")".length);
  }
}


final class _ScopeLinker {
  bool _isLinkingInnerUnits = false;
  StyleName? _parentStyle;
  String? _parentIdentifier;
  int? _parentNumInlines;

  List<ScopeUnit>? linkInnerUnits({
    required List<ScopeUnit>? Function()? innerUnits,
    required StyleName? parentStyleName,
    required String parentIdentifier,
  }) {
    // tracking a stack is not necessary since creating a layer of inner units
    // will happen one at a time and can't happen recursively
    // (because they're lazy factory functions)
    _parentStyle = parentStyleName;
    _parentIdentifier = parentIdentifier;
    _parentNumInlines = 0;
    _isLinkingInnerUnits = true;

    var units = innerUnits?.call();
    
    _isLinkingInnerUnits = false;
    _parentStyle = null;
    _parentIdentifier = null;
    _parentNumInlines = null;
    return units;
  }

  bool get isLinkingInnerUnits => _isLinkingInnerUnits;
  StyleName? get parentStyle {
    _checkIsLinking();
    return _parentStyle;
  }
  String get parentIdentifier {
    _checkIsLinking();
    return _parentIdentifier!;
  }
  
  int countNewInline() {
    _checkIsLinking();
    var newNumInlines = _parentNumInlines! + 1;
    _parentNumInlines = newNumInlines;
    return newNumInlines;
  }

  void _checkIsLinking() {
    if (!isLinkingInnerUnits) {
      throw StateError("Not currently linking units.");
    }
  }
}
