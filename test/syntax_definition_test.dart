import 'package:test/test.dart';

import '../lib/better_textmate/better_textmate.dart';


void main() {
  group("capture index tracking, like", () {
    test("a single capture group", () {
      var ref = GroupRef();
      var recipe = TestBuilder().singleCaptureTest1(ref);
      expect(recipe.compile(), equals("(asdf)"));
      expect(recipe.positionOf(ref), equals(1));
    });

    test("nested capture groups", () {
      var ref1 = GroupRef();
      var ref2 = GroupRef();
      var ref3 = GroupRef();
      var recipe = TestBuilder().multiCaptureTest1(ref1, ref2, ref3);
      expect(recipe.compile(), equals("(((bfksn)))"));
      expect(recipe.positionOf(ref1), equals(1));
      expect(recipe.positionOf(ref2), equals(2));
      expect(recipe.positionOf(ref3), equals(3));
    });

    test("nested and concatenated capture groups", () {
      var ref1 = GroupRef();
      var ref2 = GroupRef();
      var ref3 = GroupRef();
      var ref4 = GroupRef();
      var recipe = TestBuilder().multiCaptureTest2(ref1, ref2, ref3, ref4);
      // TODO: change to this when capture simplification is implemented
      // expect(recipe.compile(), equals("(abc1)abc2(((abc3))abc4)"));
      // expect(recipe.positionOf(ref1), equals(1));
      // expect(recipe.positionOf(ref2), equals(2));
      // expect(recipe.positionOf(ref3), equals(3));
      // expect(recipe.positionOf(ref4), equals(4));
      expect(recipe.compile(), equals("((abc1)abc2((((abc3))abc4)))"));
      expect(recipe.positionOf(ref1), equals(2));
      expect(recipe.positionOf(ref2), equals(3));
      expect(recipe.positionOf(ref3), equals(5));
      expect(recipe.positionOf(ref4), equals(6));
    });
  });


  group("creating definition items", () {
    late TestDefinition definition;

    setUp(() {
      definition = TestDefinition();
    });

    void expectItem_groupPattern(DefinitionItem item) {
      expect(item.identifier, equals("newItem"));
      expect(item.parent, same(definition));
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
          createInnerItems: () => [
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
          createInnerItems: () => [
            definition.basicMatch,
          ],
        );
        expectItem_groupPattern(item);
      });

      // TODO: tests for other Patterns
      // TODO: error tests for invalid combinations
    });
  });


  group("regular expression generation using", () {
    late TestBuilder builder;

    setUp(() {
      builder = TestBuilder();
    });


    group("'exactly' patterns, like", () {
      test("ones with escaped characters", () {
        var result = builder
          .exactly(r"Use .* and .+, also (), [], or {}... right? (Many $ from ^s)")
          .compile();
        expect(result, equals(r"Use \.\* and \.\+, also \(\), \[\], or \{\}\.\.\. right\? \(Many \$ from \^s\)"));
      });
    });


    group("`chars` patterns, like", () {
      test("ones with ranges characters", () {
        var result = builder
          .chars("a-z")
          .compile();
        expect(result, equals(r"[a-z]"));
      });

      test("ones with escaped characters", () {
        var result = builder
          .chars("a-z/[^-^]")
          .compile();
        expect(result, equals(r"[a-z\/\[\^-\^\]]"));
      });

      test("ones that are inverted escaped characters", () {
        var result = builder
          .notChars("nope")
          .compile();
        expect(result, equals(r"[^nope]"));
      });
    });


    group("`concat` patterns, like", () {
      test("ones combining basic patterns", () {
        var result = builder
          .concat([
            builder.exactly("abc"),
            builder.exactly("def"),
            builder.exactly("ghi"),
          ])
          .compile();
        expect(result, equals("(abcdefghi)"));
      });
    });


    group("`either` patterns, like", () {
      test("ones with multiple patterns", () {
        var result = builder
          .either([
            builder.exactly("asdf"),
            builder.chars("asdf"),
          ])
          .compile();
        expect(result, equals("([asdf]|asdf)"));
      });

      test("those with only character classes", () {
        var result = builder
          .either([
            builder.chars("123"),
            builder.chars("a-c"),
          ])
          .compile();
        expect(result, equals("([123a-c])"));
      });

      test("those with only inverted character classes", () {
        var result = builder
          .either([
            builder.notChars("123"),
            builder.notChars("a-c"),
          ])
          .compile();
        expect(result, equals("([^123a-c])"));
      });

      test("those with a mixture of normal/inverted character classes", () {
        var result = builder
          .either([
            builder.notChars("123"),
            builder.chars("a-c"),
            builder.notChars("456"),
            builder.chars("d-g"),
          ])
          .compile();
        expect(result, equals("([a-cd-g]|[^123456])"));
      });
    });

    // TODO: add tests for
    //  - behindIs/Not(aheadIsNot) throws errors
    //  - behindIs(behindIsNot) throws errors
    //  - behindIsNot(behindIs) does NOT throw errors
    //  - behindIs/Not(concat(..., aheadIs)) prunes aheadIs nodes
    //  - behindIs/Not(concat(aheadIs, ...)) throws errors
    //  - behindIsNot transforms correctly to aheadIsNot(behindIs)


    group("`behindIsNot` patterns, like", () {
      test("those with `either` clauses inside them", () {
        var result = builder
          .behindIsNot(
            builder.either([
              builder.exactly("abc"),
              builder.exactly("def"),
            ])
          )
          .compile();
        expect(result, equals("(?!(?<=abc|def))"));
      });
      test("those with `concat` clauses inside them", () {
        var result = builder
          .behindIsNot(
            builder.concat([
              builder.exactly("abc"),
              builder.exactly("def"),
            ])
          )
          .compile();
        expect(result, equals("(?<!abcdef)"));
      });
    });
  });
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

  RegExpRecipe singleCaptureTest1(GroupRef ref) {
    return capture(exactly("asdf"), ref);
  }

  RegExpRecipe multiCaptureTest1(GroupRef ref1, GroupRef ref2, GroupRef ref3) {
    return capture(capture(capture(exactly("bfksn"), ref3), ref2), ref1);
  }

  RegExpRecipe multiCaptureTest2(GroupRef ref1, GroupRef ref2, GroupRef ref3, GroupRef ref4) {
    return concat([
      capture(exactly("abc1"), ref1),
      exactly("abc2"),
      capture(concat([
        capture(capture(exactly("abc3"), ref4), ref3),
        exactly("abc4")
      ]), ref2)
    ]);
  }
}

typedef TestCollection = ({String basicMatch});
