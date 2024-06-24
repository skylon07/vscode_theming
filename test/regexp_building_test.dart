import 'package:test/test.dart';

import '../lib/vscode_theming.dart';


var builder = regExpBuilder;

void main() {
  group("capture index tracking, like", () {
    test("a single capture group", () {
      var ref = GroupRef();
      var recipe = builder.capture(builder.exactly("asdf"), ref);
      expect(recipe.compile(), equals("(asdf)"));
      expect(recipe.positionOf(ref), equals(1));
    });

    test("nested capture groups", () {
      var ref1 = GroupRef();
      var ref2 = GroupRef();
      var ref3 = GroupRef();
      var recipe = builder.capture(
        builder.capture(
          builder.capture(
            builder.exactly("bfksn"),
            ref3
          ), 
          ref2
        ), 
        ref1
      );
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
      var recipe = builder.concat([
        builder.capture(builder.exactly("abc1"), ref1),
        builder.exactly("abc2"),
        builder.capture(
          builder.concat([
            builder.capture(
              builder.capture(
                builder.exactly("abc3"),
                ref4
              ),
              ref3
            ),
            builder.exactly("abc4")
          ]), 
          ref2
        )
      ]);
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

    test("recipes that optimize out capture groups", () {
      var ref1 = GroupRef();
      var ref2 = GroupRef();
      var ref3 = GroupRef();
      var ref4 = GroupRef();
      var ref5 = GroupRef();
      var recipe = builder.concat([
        builder.capture(
          builder.exactly("asdf"),
          ref1
        ),
        builder.behindIsNot(
          builder.capture(
            builder.exactly("NONO"),
            ref2
          )
        ),
        builder.capture(
          builder.exactly("123"),
          ref3,
        ),
        builder.exactly("456"),
        builder.aheadIs(
          builder.capture(
            builder.exactly("YESYES"),
            ref4,
          )
        ),
        builder.capture(
          builder.exactly("the_end"),
          ref5,
        ),
      ]);
      expect(recipe.compile(), equals("((asdf)(?<!NONO)(123)456(?=YESYES)(the_end))"));
      expect(recipe.positionOf(ref1), equals(2));
      expect(() => recipe.positionOf(ref2), throwsArgumentError);
      expect(recipe.positionOf(ref3), equals(3));
      expect(() => recipe.positionOf(ref4), throwsArgumentError);
      expect(recipe.positionOf(ref5), equals(4));
    });
  });


  group("regular expression generation using", () {
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
        // TODO: change to this when capture simplification is implemented
        // expect(result, equals("(?!(?<=abc|def))"));
        expect(result, equals("(?!(?<=(abc|def)))"));
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
        // TODO: change to this when capture simplification is implemented
        // expect(result, equals("(?<!abcdef)"));
        expect(result, equals("(?!(?<=(abcdef)))"));
      });
    });
  });
}
