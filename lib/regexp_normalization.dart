import './regexp_recipes.dart';
import './regexp_builder_base.dart';


RegExpRecipe normalize(RegExpRecipe recipe) {
  return switch (recipe) {
    JoinedRegExpRecipe(tag: RegExpTag.either)         => _normalizeEither(recipe),
    AugmentedRegExpRecipe(tag: RegExpTag.behindIsNot) => _normalizeBehindIsNot(recipe),
    AugmentedRegExpRecipe(tag: RegExpTag.behindIs)    => _normalizeBehindIs(recipe),
    AugmentedRegExpRecipe(tag: RegExpTag.aheadIsNot)  => _normalizeAheadIsNot(recipe),
    AugmentedRegExpRecipe(tag: RegExpTag.aheadIs)     => _normalizeAheadIs(recipe),
    _ => recipe,
  };
}


final class InternalError extends Error {
  final Error error;

  InternalError(this.error);

  @override
  String toString() {
    return "Internal error (something went wrong, and it's not your fault): $error";
  }
}


typedef TransformFn = RegExpRecipe? Function(RegExpRecipe);
typedef TransformBinder = TransformFn Function(RegExpRecipe);
extension _RecipeTraversal on RegExpRecipe {
  RegExpRecipe traverseTransform(TransformBinder binder) {
    var transform = binder(this);

    RegExpRecipe? prevRecipe = null;
    RegExpRecipe newRecipe = this;
    while (newRecipe != prevRecipe) {
      var result = transform(newRecipe);
      if (result == null) return newRecipe;
      prevRecipe = newRecipe;
      newRecipe = result;
    }
    
    switch (newRecipe) {
      case AugmentedRegExpRecipe(:var source): {
        var newSource = source.traverseTransform((_) => transform);
        newRecipe = newRecipe.copy(source: newSource);
      }

      case JoinedRegExpRecipe(:var sources): {
        var newSources = [
          for (var source in sources)
            source.traverseTransform((_) => transform)
        ];
        newRecipe = newRecipe.copy(sources: newSources);
      }

      default: break;
    }
    
    return newRecipe;
  }

  RegExpRecipe traverseTransformAll(Iterable<TransformBinder> transforms) {
    var newRecipe = this;
    for (var transform in transforms) {
      newRecipe = newRecipe.traverseTransform(transform);
    }
    return newRecipe;
  }
}

// transform helper functions

TransformBinder _pureTransform(TransformFn transform) => (_) => transform;

/// (Not intended as a [TransformBinder] function in the regular sense, even though its signature matches.)
TransformFn _transformToFixed(RegExpRecipe normalizedRecipe) {
  return (recipe) {
    if (recipe == normalizedRecipe) {
      return null; // shouldn't keep going because the subtree is already normalized
    } else {
      return normalizedRecipe;
    }
  };
}

// actual transformation functions

TransformFn _transform_spliceOutCapture(RegExpRecipe rootRecipe) {
  var capturesToSplice = <AugmentedRegExpRecipe?>{
    for (var source in rootRecipe.sources)
      if (source case AugmentedRegExpRecipe(tag: RegExpTag.capture)) source
  };
  return (RegExpRecipe recipe) {
    var captureSource = capturesToSplice.firstWhere(
      (capture) => capture == recipe,
      orElse: () => null,
    )?.source;
    return captureSource ?? recipe;
  };
}

TransformFn _transform_hoistUpEither(RegExpRecipe rootRecipe) {
  var lastVisitedRecipe = null as RegExpRecipe?;
  var parentRecipe = null as RegExpRecipe?;
  // TODO: make a specialized searching function to avoid needing a
  //  smart cast hack below
  rootRecipe.traverseTransform(_pureTransform((recipe) {
    if (parentRecipe != null) return null;
    switch (recipe) {
      case JoinedRegExpRecipe(tag: RegExpTag.either): {
        parentRecipe = lastVisitedRecipe;
        return null;
      }

      default: {
        lastVisitedRecipe = recipe;
        return recipe;
      }
    }
  }));

  var parentOfEither = parentRecipe; // necessary to allow for smart cast
  if (parentOfEither == null) return _transformToFixed(rootRecipe);
  
  // permutations must be calculated in case it's a `concat()` with multiple `either()` sources
  List<Map<RegExpRecipe, RegExpRecipe>> permutateEitherReplacements() {
    var permutations = <Map<RegExpRecipe, RegExpRecipe>>[{}];
    for (var source in parentOfEither.sources) {
      if (source.tag == RegExpTag.either) {
        permutations = [
          for (var permutation in permutations)
            for (var replacement in source.sources)
            {
              ...permutation,
              source: replacement,
            }
        ];
      }
    }
    return permutations;
  }
  var replacementMaps = permutateEitherReplacements();
  var normalizedSources = <RegExpRecipe>[];
  for (var replacementMap in replacementMaps) {
      var normalizedSource = rootRecipe.traverseTransformAll([
        _pureTransform((recipe) {
          var replacement = replacementMap[recipe];
          if (replacement != null) {
            return replacement;
          } else if (replacementMap.values.contains(recipe)) {
            return null; // no need to keep going
          } else {
            return recipe;
          }
        }),
        // must be done recursively in case more source `either()`s are nested deeper
        // inside the one that was found
        _transform_hoistUpEither,
      ]);
      // TODO: maybe use the search function (when it's implemented) to find the `either()` recipe
      //  so it's less brittle and would still work if the implementation changed
      if (normalizedSource.tag == RegExpTag.capture && normalizedSource.sources.first.tag == RegExpTag.either) {
        // collapse all branches to avoid nested `either()`s
        normalizedSources.addAll(normalizedSource.sources.first.sources);
      } else {
        normalizedSources.add(normalizedSource);
      }
  }
  var normalizedRecipe = regExpBuilder.either(normalizedSources);
  return _transformToFixed(normalizedRecipe);
}

/// (This transform function should *only* be used when it is guaranteed
/// no sources will be `either()` nodes.)
TransformFn _transform_extractTrailingAheadIs(RegExpRecipe rootRecipe) {
  var trailingRecipes = <RegExpRecipe>{rootRecipe};
  var recipeToExtract = null as RegExpRecipe?;
  // TODO: make a specialized searching function to avoid needing a
  //  smart cast hack below
  var rootRecipeAfterExtract = rootRecipe.traverseTransform(_pureTransform(
    (recipe) {
      if (recipe case JoinedRegExpRecipe(tag: RegExpTag.either)) {
        throw InternalError(ArgumentError("'either' recipes must not be present when extracting 'aheadIs' recipes."));
      }

      if (trailingRecipes.contains(recipe)) {
        if (recipe case AugmentedRegExpRecipe(tag: RegExpTag.aheadIs)) {
          recipeToExtract = recipe;
          return regExpBuilder.nothing;
        } else if (recipe case AugmentedRegExpRecipe(:var source)) {
          trailingRecipes.add(source);
        } else if (recipe case JoinedRegExpRecipe(tag: RegExpTag.concat, :var sources)) {
          trailingRecipes.add(sources.last);
        }
      } else if (recipe case AugmentedRegExpRecipe(tag: RegExpTag.aheadIs)) {
        return regExpBuilder.nothing;
      }
      return recipe;
    }
  ));
  
  var trailingRecipe = recipeToExtract; // necessary to avoid compilation error
  var normalizedRecipe = regExpBuilder.concat([
    rootRecipeAfterExtract,
    if (trailingRecipe != null) trailingRecipe,
  ]);
  return _transformToFixed(normalizedRecipe);
}


final class RecipeConfigurationError extends Error {
  final RegExpRecipe topRecipe;
  final RegExpRecipe containedRecipe;
  final String? details;

  RecipeConfigurationError(this.topRecipe, this.containedRecipe, [this.details]);

  @override
  String toString() {
    var topRecipeRep = _prettyRepOf(topRecipe, "...");
    var containedRecipeRep = _prettyRepOf(containedRecipe, "...");
    var fullRep = _prettyRepOf(topRecipe, "...$containedRecipeRep...");
    var detailsStr = (details != null)? " ($details)" : "";
    return "Invalid regex configuration `$fullRep`: `$topRecipeRep` cannot contain `$containedRecipeRep$detailsStr";
  }

  static String _prettyRepOf(RegExpRecipe recipe, String innerRep) {
    return switch(recipe) {
      BaseRegExpRecipe(:var expr) => 
        expr,
      AugmentedRegExpRecipe(:var augment) => 
        augment(innerRep),
      JoinedRegExpRecipe(:var joinBy) => 
        "$innerRep$joinBy...",
    };
  }
}


RegExpRecipe _normalizeEither(JoinedRegExpRecipe recipe) {
  var (chars, notChars, rest) = _flattenEither(recipe);
  var charClass = _combineCharClasses(chars);
  var notCharClass = _combineCharClasses(notChars);
  // TODO: this thinks capture(either(chars(...))) is a "rest"; it should instead combine all of them
  //  (add a test for it too)
  return recipe.copy(
    sources: [
      if (charClass != null) charClass,
      if (notCharClass != null) notCharClass,
      ...rest,
    ],
  );
}

typedef EitherFlatClasses = (
  List<InvertibleRegExpRecipe> charsList,
  List<InvertibleRegExpRecipe> notCharsList,
  List<RegExpRecipe>          restList,
);
EitherFlatClasses _flattenEither(JoinedRegExpRecipe recipe) {
  var charsList = <InvertibleRegExpRecipe>[];
  var notCharsList = <InvertibleRegExpRecipe>[];
  var restList = <RegExpRecipe>[];

  recipe.traverseTransform(_pureTransform((source) {
    switch (source) {
      case InvertibleRegExpRecipe(tag: RegExpTag.chars, inverted: false): {
        charsList.add(source);
        return null;
      }

      case InvertibleRegExpRecipe(tag: RegExpTag.chars, inverted: true): {
        notCharsList.add(source);
        return null;
      }

      case RegExpRecipe(:var tag): {
        if (tag == RegExpTag.either) return source;

        restList.add(source);
        return null;
      }
    }
  }));
  return (charsList, notCharsList, restList);
}

InvertibleRegExpRecipe? _combineCharClasses(List<InvertibleRegExpRecipe> recipes) {
  if (recipes.isEmpty) return null;

  var (combinedClasses, inverted) = recipes
    .map((recipe) => (recipe.source.compile(), recipe.inverted))
    .reduce((last, next) {
      var (lastSource, lastInverted) = last;
      var (nextSource, nextInverted) = next;
      assert (lastInverted == nextInverted);
      return (lastSource + nextSource, nextInverted);
    });
  return InvertibleRegExpRecipe(
    BaseRegExpRecipe(combinedClasses),
    recipes.first.augment,
    inverted: inverted,
  );
}


RegExpRecipe _normalizeBehindIsNot(AugmentedRegExpRecipe recipe) {
  var useAlternateRecipe = false;
  var useAheadIsTransform = false;
  var normalizedRecipe = recipe.traverseTransformAll([
    _transform_spliceOutCapture,
    _pureTransform((source) {
      switch (source.tag) {
        case RegExpTag.capture:
        case RegExpTag.either: {
          useAlternateRecipe = true;
          return null;
        }

        case RegExpTag.aheadIs: {
          useAheadIsTransform = true;
          return null;
        }

        case RegExpTag.aheadIsNot: {
          throw RecipeConfigurationError(recipe, source);
        }

        default: return source;
      }
    }),
  ]);

  if (useAlternateRecipe) {
    return normalize(
      regExpBuilder.aheadIsNot(
        regExpBuilder.behindIs(
          recipe.source,
        ),
      )
    );
  } else if (useAheadIsTransform) {
    return normalizedRecipe.traverseTransform(
      // okay to use; `either()` recipes can't be present because they cause the
      // "alternate recipe" branch above to return instead
      _transform_extractTrailingAheadIs,
    );
  } else {
    return normalizedRecipe;
  }
}


RegExpRecipe _normalizeBehindIs(AugmentedRegExpRecipe recipe) {
  var useAheadIsTransform = false;
  var containsEitherRecipes = false;
  var normalizedRecipe = recipe.traverseTransformAll([
    _transform_spliceOutCapture,
    _pureTransform((source) {
      switch (source.tag) {
        case RegExpTag.either: {
          containsEitherRecipes = true;
          return source;
        }

        case RegExpTag.aheadIs: {
          useAheadIsTransform = true;
          return null;
        }

        case RegExpTag.aheadIsNot:
        case RegExpTag.behindIsNot: {
          throw RecipeConfigurationError(recipe, source);
        }

        default: return source;
      }
    }),
  ]);

  if (useAheadIsTransform) {
    RegExpRecipe transformBehindIs(RegExpRecipe behindIsRecipe) {
      return behindIsRecipe.traverseTransform(
        _transform_extractTrailingAheadIs,
      );
    }
    
    if (containsEitherRecipes) {
      // this operation is blocked by a check first since hoisting `either()`s seems kind of expensive...
      var eitherHasBeenNormalized = false;
      return normalizedRecipe.traverseTransformAll([
        _transform_hoistUpEither,
        _pureTransform((source) {
          if (eitherHasBeenNormalized) {
            return null;
          } else if (source.tag == RegExpTag.either) {
            eitherHasBeenNormalized = true;
            return (source as JoinedRegExpRecipe).copy(
              sources: [
                for (var behindIsSource in source.sources)
                  transformBehindIs(behindIsSource)
              ],
            );
          } else {
            return source;
          }
        }),
      ]);
    } else {
      return transformBehindIs(normalizedRecipe);
    }
  } else {
    return normalizedRecipe;
  }
}


RegExpRecipe _normalizeAheadIsNot(AugmentedRegExpRecipe recipe) {
  return recipe.traverseTransform(_transform_spliceOutCapture);
}


RegExpRecipe _normalizeAheadIs(AugmentedRegExpRecipe recipe) {
  return recipe.traverseTransform(_transform_spliceOutCapture);
}

// TODO: normalize redundant/nested capture()s, checking for reused refs along the way
