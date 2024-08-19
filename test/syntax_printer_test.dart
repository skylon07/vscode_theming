import 'package:test/test.dart';

import '../lib/vscode_theming_tools.dart';


String syntaxPrint(SyntaxElement syntax) =>
  SyntaxPrinter.instance.print(syntax);

enum TestStyleName implements StyleName {
  name1("scope.name1"), name2("scope.name2"), name3("scope.name3");
  final String scope;

  const TestStyleName(this.scope);
}

void main() {
  group("pattern syntaxes, such as", () {
    group("'capture' patterns, like", () {
      test("those without a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          CapturePattern(debugName: "debugName")
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName"
}
"""
          ),
        );
      });

      test("those with a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          CapturePattern(debugName: "debugName", styleName: TestStyleName.name1)
        );
        expect(
          result,
          equals(
r"""
{
    "name": "scope.name1 debugName.debugName"
}
"""
          ),
        );
      });
    });


    group("'match' patterns, like", () {
      test("those without a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          MatchPattern(debugName: "debugName", match: "abcdef")
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "match": "abcdef"
}
"""
          ),
        );
      });

      test("those with a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          MatchPattern(
            debugName: "debugName",
            styleName: TestStyleName.name1,
            match: "abcdef"
          )
        );
        expect(
          result,
          equals(
r"""
{
    "name": "scope.name1 debugName.debugName",
    "match": "abcdef"
}
"""
          ),
        );
      });

      test("those with captures", () {
        var result = SyntaxPrinter.instance.print(
          MatchPattern(debugName: "debugName", match: "abcdef", captures: {
            1: CapturePattern(debugName: "debugName1"),
            2: CapturePattern(debugName: "debugName2"),
            3: CapturePattern(debugName: "debugName3"),
          })
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "match": "abcdef",
    "captures": {
        "1": {
            "name": "debugName.debugName1"
        },
        "2": {
            "name": "debugName.debugName2"
        },
        "3": {
            "name": "debugName.debugName3"
        }
    }
}
"""
          ),
        );
      });

      test("those with escapes in matches", () {
        var result = SyntaxPrinter.instance.print(
          MatchPattern(debugName: "debugName", match: r"\.*"),
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "match": "\\.*"
}
"""
          )
        );
      });
    });


    group("'group' patterns, like", () {
      test("those without a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          GroupingPattern(debugName: "debugName", innerPatterns: [
            CapturePattern(debugName: "debugName1"),
            CapturePattern(debugName: "debugName2"),
            CapturePattern(debugName: "debugName3"),
          ])
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "patterns": [
        {
            "name": "debugName.debugName1"
        },
        {
            "name": "debugName.debugName2"
        },
        {
            "name": "debugName.debugName3"
        }
    ]
}
"""
          ),
        );
      });

      test("those with a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          GroupingPattern(
            debugName: "debugName",
            styleName: TestStyleName.name1,
            innerPatterns: [
              CapturePattern(debugName: "debugName1"),
              CapturePattern(debugName: "debugName2"),
              CapturePattern(debugName: "debugName3"),
            ]
          )
        );
        expect(
          result,
          equals(
r"""
{
    "name": "scope.name1 debugName.debugName",
    "patterns": [
        {
            "name": "debugName.debugName1"
        },
        {
            "name": "debugName.debugName2"
        },
        {
            "name": "debugName.debugName3"
        }
    ]
}
"""
          ),
        );
      });
    });


    group("'enclosure' patterns, like", () {
      test("those without a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          EnclosurePattern(debugName: "debugName", begin: "abc", end: "def")
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "begin": "abc",
    "end": "def"
}
"""
          ),
        );
      });

      test("those with a (style) name", () {
        var result = SyntaxPrinter.instance.print(
          EnclosurePattern(
            debugName: "debugName",
            styleName: TestStyleName.name1,
            begin: "abc",
            end: "def"
          )
        );
        expect(
          result,
          equals(
r"""
{
    "name": "scope.name1 debugName.debugName",
    "begin": "abc",
    "end": "def"
}
"""
          ),
        );
      });

      test("those with begin-captures", () {
        var result = SyntaxPrinter.instance.print(
          EnclosurePattern(debugName: "debugName", begin: "abc", end: "def", beginCaptures: {
            1: CapturePattern(debugName: "debugName1"),
            2: CapturePattern(debugName: "debugName2"),
            3: CapturePattern(debugName: "debugName3"),
          })
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "begin": "abc",
    "end": "def",
    "beginCaptures": {
        "1": {
            "name": "debugName.debugName1"
        },
        "2": {
            "name": "debugName.debugName2"
        },
        "3": {
            "name": "debugName.debugName3"
        }
    }
}
"""
          ),
        );
      });

      test("those with end-captures", () {
        var result = SyntaxPrinter.instance.print(
          EnclosurePattern(debugName: "debugName", begin: "abc", end: "def", endCaptures: {
            1: CapturePattern(debugName: "debugName1"),
            2: CapturePattern(debugName: "debugName2"),
            3: CapturePattern(debugName: "debugName3"),
          })
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "begin": "abc",
    "end": "def",
    "endCaptures": {
        "1": {
            "name": "debugName.debugName1"
        },
        "2": {
            "name": "debugName.debugName2"
        },
        "3": {
            "name": "debugName.debugName3"
        }
    }
}
"""
          ),
        );
      });

      test("those with inner children patterns", () {
        var result = SyntaxPrinter.instance.print(
          EnclosurePattern(debugName: "debugName", begin: "abc", end: "def", innerPatterns: [
            CapturePattern(debugName: "debugName1"),
            CapturePattern(debugName: "debugName2"),
            CapturePattern(debugName: "debugName3"),
          ])
        );
        expect(
          result,
          equals(
r"""
{
    "name": "debugName.debugName",
    "patterns": [
        {
            "name": "debugName.debugName1"
        },
        {
            "name": "debugName.debugName2"
        },
        {
            "name": "debugName.debugName3"
        }
    ],
    "begin": "abc",
    "end": "def"
}
"""
          ),
        );
      });
    });


    group("'include' patterns, like", () {
      test("those with any (non-escaped) identifier", () {
        var result = SyntaxPrinter.instance.print(
          IncludePattern(identifier: "some-repository-identifier")
        );
        expect(
          result,
          equals(
r"""
{
    "include": "#some-repository-identifier"
}
"""
          ),
        );
      });

      test("those with a non-repository identifier", () {
        var result = SyntaxPrinter.instance.print(
          IncludePattern(identifier: "do-this-exactly", isRepoItemRef: false)
        );
        expect(
          result,
          equals(
r"""
{
    "include": "do-this-exactly"
}
"""
          ),
        );
      });
    });
  });


  group("repository items, like", () {
    test("that they should not include their identifier in their JSON encoding", () {
      var result = SyntaxPrinter.instance.print(
        RepositoryItem(
          identifier: "some-identifier",
          body: IncludePattern(identifier: "some-other-identifier")
        )
      );
      expect(
        result,
        equals(
r"""
{
    "include": "#some-other-identifier"
}
"""
        ),
      );
    });

    test("that their identifiers match their corresponding include pattern", () {
      var includeId = RepositoryItem(
        identifier: "repository-identifier",
        body: MatchPattern(debugName: "whatever", match: "whatever"),
      ).asInclude().identifier;
      expect(includeId, equals("repository-identifier"));
    });
  });


  group("entire syntax bodies/files, like", () {
    test("those with all their attributes defined", () {
      var result = SyntaxPrinter.instance.print(
        MainBody(
          isTextSyntax: false,
          fileTypes: [
            "dart1",
            "dart2"
          ],
          langName: "dart",
          topLevelPatterns: [
            EnclosurePattern(
              debugName: "enclosureDebugName",
              begin: "enclosure-begin",
              end: "enclosure-end",
              innerPatterns: [
                IncludePattern(identifier: "some-repo-thing")
              ]
            )
          ],
          repository: [
            RepositoryItem(
              identifier: "some-repo-thing",
              body: MatchPattern(
                debugName: "matchDebugName",
                match: "match-me"
              ),
            ),
          ],
        )
      );
      expect(
        result,
        equals(
r"""
{
    "fileTypes": [
        "dart1",
        "dart2"
    ],
    "scopeName": "source.dart",
    "patterns": [
        {
            "name": "debugName.enclosureDebugName",
            "patterns": [
                {
                    "include": "#some-repo-thing"
                }
            ],
            "begin": "enclosure-begin",
            "end": "enclosure-end"
        }
    ],
    "repository": {
        "some-repo-thing": {
            "name": "debugName.matchDebugName",
            "match": "match-me"
        }
    }
}
"""
        ),
      );
    });
  });
}
