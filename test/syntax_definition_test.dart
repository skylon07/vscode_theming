import 'package:test/test.dart';

import '../lib/vscode_theming_tools.dart';


void main() {
  group("creating scope units", () {
    late TestDefinition definition;

    setUp(() {
      definition = TestDefinition();
    });

    // TODO: should organize this better before writing future tests like it...
    void expectItem_groupPattern(ScopeUnit unit) {
      expect(unit.identifier, equals("newItem"));
      expect(unit.baseSyntax, same(definition));
      expect(unit.innerUnits, equals([definition.basicMatch]));

      var repositoryItem = unit.asRepositoryItem();
      expect(repositoryItem.identifier, equals("newItem"));
      expect(repositoryItem.body, isA<GroupingPattern>());
      expect(repositoryItem.body.debugName, equals("TESTLANG.newItem"));
      expect(repositoryItem.body.styleName, equals(null));
    }


    group("intelligently, like", () {
      test("for GroupingPatterns", () {
        var unit = definition.createUnit(
          "newItem",
          innerUnits: () => [
            definition.basicMatch,
          ],
        );
        expectItem_groupPattern(unit);
      });

      // TODO: tests for other Patterns
      // TODO: error tests for invalid combinations
    });


    group("that are nested (through the linker), like", () {
      void expectDebugNames(Pattern parent, String parentIdentifier, List<String?> childIdentifiers) {
        String getDebugName(String? identifier) => 
          identifier != null ? "${definition.langName}.$identifier" : "";

        expect(parent, isA<GroupingPattern>());
        var itemBody = parent as GroupingPattern;
        expect(itemBody.debugName, equals(getDebugName(parentIdentifier)));
        expect(
          itemBody.innerPatterns.map((pattern) => pattern.debugName),
          equals(childIdentifiers.map((identifier) => getDebugName(identifier)))
        );
      }

      void expectStyleNames(Pattern parent, String? parentStyleName, List<String?> childStyleNames) {
        expect(parent, isA<GroupingPattern>());
        var itemBody = parent as GroupingPattern;
        expect(itemBody.styleName?.scope, equals(parentStyleName));
        expect(itemBody.innerPatterns.map((pattern) => pattern.styleName?.scope), equals(childStyleNames));
      }

      String identifierForInline(String parentIdentifier, int inlineCountIdx) => "$parentIdentifier.inline$inlineCountIdx";

      test("a unit with another unit reference", () {
        var parentIdentifier = "unitWithRegularChild";
        var parentStyleName = "parent";
        var unit = definition.createUnit(
          parentIdentifier,
          styleName: TestStyleName(parentStyleName),
          innerUnits: () => [
            definition.createUnit(
              "unitWithRegularChild_child",
              styleName: TestStyleName("child"),
              match: regExpBuilder.nothing,
            ),
          ],
        );
        expectDebugNames(unit.asRepositoryItem().body, parentIdentifier, [null]);
        expectStyleNames(unit.asRepositoryItem().body, parentStyleName, [null]);
      });
      
      test("a unit with an inline unit", () {
        var parentIdentifier = "unitWithInlineChild";
        var parentStyleName = "parent";
        var unit = definition.createUnit(
          parentIdentifier,
          styleName: TestStyleName(parentStyleName),
          innerUnits: () => [
            definition.createUnitInline(match: regExpBuilder.nothing),
          ],
        );
        expectDebugNames(unit.asRepositoryItem().body, parentIdentifier, [identifierForInline(parentIdentifier, 1)]);
        expectStyleNames(unit.asRepositoryItem().body, parentStyleName, [parentStyleName]);
      });

      test("a unit with an inline unit (without a style name)", () {
        var parentIdentifier = "unitWithInlineChild";
        var parentStyleName = null;
        var unit = definition.createUnit(
          parentIdentifier,
          styleName: parentStyleName,
          innerUnits: () => [
            definition.createUnitInline(match: regExpBuilder.nothing),
          ],
        );
        expectDebugNames(unit.asRepositoryItem().body, parentIdentifier, [identifierForInline(parentIdentifier, 1)]);
        expectStyleNames(unit.asRepositoryItem().body, parentStyleName, [parentStyleName]);
      });

      test("a unit with a few inline units", () {
        var parentIdentifier = "unitWithInlineChildren";
        var parentStyleName = "parent";
        var unit = definition.createUnit(
          parentIdentifier,
          styleName: TestStyleName(parentStyleName),
          innerUnits: () => [
            definition.createUnitInline(match: regExpBuilder.nothing),
            definition.createUnitInline(match: regExpBuilder.nothing),
            definition.createUnitInline(match: regExpBuilder.nothing),
          ],
        );
        expectDebugNames(
          unit.asRepositoryItem().body,
          parentIdentifier,
          [
            identifierForInline(parentIdentifier, 1),
            identifierForInline(parentIdentifier, 2),
            identifierForInline(parentIdentifier, 3),
          ]
        );
        expectStyleNames(
          unit.asRepositoryItem().body,
          parentStyleName,
          [
            parentStyleName,
            parentStyleName,
            parentStyleName,
          ]
        );
      });

      test("a unit with a mixture of inner units", () {
        var parentIdentifier = "unitWithMixedChildren";
        var parentStyleName = "parent";
        var unit = definition.createUnit(
          parentIdentifier,
          styleName: TestStyleName(parentStyleName),
          innerUnits: () => [
            definition.createUnitInline(match: regExpBuilder.nothing),
            definition.createUnit(
              "unitWithMixedChildren_child1",
              styleName: TestStyleName("child1"),
              match: regExpBuilder.nothing,
            ),
            definition.createUnitInline(match: regExpBuilder.nothing),
            definition.createUnit(
              "unitWithMixedChildren_child2",
              styleName: TestStyleName("child2"),
              match: regExpBuilder.nothing,
            ),
            definition.createUnitInline(match: regExpBuilder.nothing),
            definition.createUnit(
              "unitWithMixedChildren_child3",
              styleName: TestStyleName("child3"),
              match: regExpBuilder.nothing,
            ),
            definition.createUnitInline(match: regExpBuilder.nothing),
          ],
        );
        expectDebugNames(
          unit.asRepositoryItem().body,
          parentIdentifier,
          [
            identifierForInline(parentIdentifier, 1),
            null,
            identifierForInline(parentIdentifier, 2),
            null,
            identifierForInline(parentIdentifier, 3),
            null,
            identifierForInline(parentIdentifier, 4),
          ]
        );
        expectStyleNames(
          unit.asRepositoryItem().body,
          parentStyleName,
          [
            parentStyleName,
            null,
            parentStyleName,
            null,
            parentStyleName,
            null,
            parentStyleName,
          ]
        );
      });

      test("a unit with nested inline units", () {
        var parentIdentifier = "unitWithNestedInlineChildren";
        var parentStyleName = "parent";
        var specialChildIdentifier = identifierForInline(parentIdentifier, 1);
        var specialChild2Identifier = identifierForInline(specialChildIdentifier, 2);
        late ScopeUnit specialChild;
        late ScopeUnit specialChild2;
        var unit = definition.createUnit(
          parentIdentifier,
          styleName: TestStyleName(parentStyleName),
          innerUnits: () => [
            specialChild = definition.createUnitInline(
              innerUnits: () => [
                definition.createUnitInline(match: regExpBuilder.nothing),
                specialChild2 = definition.createUnitInline(
                  innerUnits: () => [
                    definition.createUnitInline(match: regExpBuilder.nothing),
                    definition.createUnitInline(match: regExpBuilder.nothing),
                    definition.createUnitInline(match: regExpBuilder.nothing),
                  ]
                ),
                definition.createUnitInline(match: regExpBuilder.nothing),
              ],
            ),
            definition.createUnitInline(match: regExpBuilder.nothing),
          ],
        );
        expectDebugNames(
          unit.asRepositoryItem().body,
          parentIdentifier,
          [
            specialChildIdentifier,
            identifierForInline(parentIdentifier, 2),
          ],
        );
        expectStyleNames(
          unit.asRepositoryItem().body,
          parentStyleName,
          [
            parentStyleName,
            parentStyleName,
          ],
        );
        expectDebugNames(
          specialChild.asInnerPattern(),
          specialChildIdentifier,
          [
            identifierForInline(specialChildIdentifier, 1),
            specialChild2Identifier,
            identifierForInline(specialChildIdentifier, 3),
          ],
        );
        expectStyleNames(
          specialChild.asInnerPattern(),
          parentStyleName,
          [
            parentStyleName,
            parentStyleName,
            parentStyleName,
          ],
        );
        expectDebugNames(
          specialChild2.asInnerPattern(),
          specialChild2Identifier,
          [
            identifierForInline(specialChild2Identifier, 1),
            identifierForInline(specialChild2Identifier, 2),
            identifierForInline(specialChild2Identifier, 3),
          ],
        );
        expectStyleNames(
          specialChild2.asInnerPattern(),
          parentStyleName,
          [
            parentStyleName,
            parentStyleName,
            parentStyleName,
          ],
        );
      });

      test("a unit with nested regular and inline units", () {
        var parentIdentifier = "unitWithNestedMixedChildren";
        var parentStyleName = "parent";
        var specialChildIdentifier = "unitWithNestedMixedChildren_child";
        var specialChildStyleName = "child";
        var specialChild2Identifier = "unitWithNestedMixedChildren_child";
        var specialChild2StyleName = "child";
        late ScopeUnit specialChild;
        late ScopeUnit specialChild2;
        var unit = definition.createUnit(
          parentIdentifier,
          styleName: TestStyleName(parentStyleName),
          innerUnits: () => [
            specialChild = definition.createUnit(
              specialChildIdentifier,
              styleName: TestStyleName(specialChildStyleName),
              innerUnits: () => [
                definition.createUnitInline(match: regExpBuilder.nothing),
                specialChild2 = definition.createUnit(
                  specialChild2Identifier,
                  styleName: TestStyleName(specialChild2StyleName),
                  innerUnits: () => [
                    definition.createUnitInline(match: regExpBuilder.nothing),
                    definition.createUnitInline(match: regExpBuilder.nothing),
                    definition.createUnitInline(match: regExpBuilder.nothing),
                  ]
                ),
                definition.createUnitInline(match: regExpBuilder.nothing),
              ],
            ),
            definition.createUnitInline(match: regExpBuilder.nothing),
          ],
        );
        expectDebugNames(
          unit.asRepositoryItem().body,
          parentIdentifier,
          [
            null,
            identifierForInline(parentIdentifier, 1),
          ],
        );
        expectStyleNames(
          unit.asRepositoryItem().body,
          parentStyleName,
          [
            null,
            parentStyleName
          ],
        );
        expectDebugNames(
          specialChild.asRepositoryItem().body,
          specialChildIdentifier,
          [
            identifierForInline(specialChildIdentifier, 1),
            null,
            identifierForInline(specialChildIdentifier, 2),
          ],
        );
        expectStyleNames(
          specialChild.asRepositoryItem().body,
          specialChildStyleName,
          [
            specialChildStyleName,
            null,
            specialChildStyleName,
          ],
        );
        expectDebugNames(
          specialChild2.asRepositoryItem().body,
          specialChild2Identifier,
          [
            identifierForInline(specialChild2Identifier, 1),
            identifierForInline(specialChild2Identifier, 2),
            identifierForInline(specialChild2Identifier, 3),
          ],
        );
        expectStyleNames(
          specialChild2.asRepositoryItem().body,
          specialChild2StyleName,
          [
            specialChild2StyleName,
            specialChild2StyleName,
            specialChild2StyleName,
          ],
        );
      });
    });
  });

  // TODO: test main body creation and warnings (like unused recipes)
}


final class TestDefinition extends SyntaxDefinition<TestBuilder, TestCollection> {
  TestDefinition() : super(
    langName: "TESTLANG",
    isTextSyntax: false,
    fileTypes: ["completely_fake_filetype"],
    builder: TestBuilder(),
  );

  @override
  List<ScopeUnit> get rootUnits => throw UnimplementedError();

  late final basicMatch = createUnit(
    "basicCapture",
    match: collection.basicMatch,
  );
}

final class TestBuilder extends RegExpBuilder<TestCollection> {
  @override
  TestCollection createCollection() {
    var basicMatch = exactly("matchPattern");
    return (basicMatch: basicMatch);
  }
}

typedef TestCollection = ({RegExpRecipe basicMatch});

final class TestStyleName implements StyleName {
  final String scope;

  TestStyleName(this.scope);
}
