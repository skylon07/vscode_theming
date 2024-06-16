import 'package:test/test.dart';

import '../lib/vscode_theming.dart';


void main() {
  group("creating definition items", () {
    late TestDefinition definition;

    setUp(() {
      definition = TestDefinition();
    });

    void expectItem_groupPattern(DefinitionItem item) {
      expect(item.identifier, equals("newItem"));
      expect(item.baseSyntax, same(definition));
      expect(item.innerItems, [definition.basicMatch]);

      var repositoryItem = item.asRepositoryItem();
      expect(repositoryItem.identifier, equals("newItem"));
      expect(repositoryItem.body, isA<GroupingPattern>());
      expect(repositoryItem.body.debugName, equals("TESTLANG.newItem"));
      expect(repositoryItem.body.styleName, equals(null));
    }
    
    
    group("directly, like", () {
      test("for GroupingPatterns", () {
        var item = definition.createItemDirect(
          "newItem",
          createBody: (debugName, innerPatterns) {
            return GroupingPattern(
              debugName: debugName,
              innerPatterns: innerPatterns
            );
          },
          innerItems: () => [
            definition.basicMatch
          ]
        );
        expectItem_groupPattern(item);
      });

      // TODO: tests for other Patterns
    });


    group("intelligently, like", () {
      test("for GroupingPatterns", () {
        var item = definition.createItem(
          "newItem",
          innerItems: () => [
            definition.basicMatch,
          ],
        );
        expectItem_groupPattern(item);
      });

      // TODO: tests for other Patterns
      // TODO: error tests for invalid combinations
    });
  });

  // TODO: test main body creation and warnings
}


final class TestDefinition extends SyntaxDefinition<TestBuilder, TestCollection> {
  TestDefinition() : super(
    langName: "TESTLANG",
    isTextSyntax: false,
    fileTypes: ["completely_fake_filetype"],
    builder: TestBuilder(),
  );

  @override
  List<DefinitionItem> get rootItems => throw UnimplementedError();

  late final basicMatch = createItemDirect(
    "basicCapture",
    createBody: (debugName, innerPatterns) => 
      MatchPattern(debugName: debugName, match: "matchPattern"),
  );
}

final class TestBuilder extends RegExpBuilder<TestCollection> {
  @override
  TestCollection createCollection() {
    var basicMatch = exactly("matchPattern").compile();
    return (basicMatch: basicMatch);
  }
}

typedef TestCollection = ({String basicMatch});
