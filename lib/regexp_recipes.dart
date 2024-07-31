import 'package:meta/meta.dart';


sealed class RegExpRecipe {
  final List<RegExpRecipe> sources;
  final GroupTracker _tracker;
  final RegExpTag tag;
  var _hasCompiled = false;

  RegExpRecipe(this.sources, this._tracker, {this.tag = RegExpTag.none});

  String compile() {
    _hasCompiled = true;
    return _expr;
  }
  late final _expr = _createExpr();
  bool get hasCompiled => _hasCompiled;

  int positionOf(GroupRef ref) => _tracker.getPosition(ref);

  @mustBeOverridden
  RegExpRecipe copy({RegExpTag? tag});
  String _createExpr();
}

enum RegExpTag {
  none,
  capture, either, chars,
  concat,
  aheadIs, aheadIsNot,
  behindIs, behindIsNot,
}


final class BaseRegExpRecipe extends RegExpRecipe {
  final String expr;

  BaseRegExpRecipe(this.expr, {super.tag}) : super(const [], GroupTracker());

  @override
  BaseRegExpRecipe copy({
    String? expr,
    RegExpTag? tag,
  }) => BaseRegExpRecipe(
    expr ?? this.expr,
    tag: tag ?? this.tag,
  );
  
  @override
  String _createExpr() => expr;
}

final class AugmentedRegExpRecipe extends RegExpRecipe {
  final RegExpRecipe source;
  final Augmenter augment;

  AugmentedRegExpRecipe(this.source, this.augment, {super.tag}) : super([source], source._tracker);

  @override
  AugmentedRegExpRecipe copy({
    RegExpRecipe? source,
    Augmenter? augment,
    RegExpTag? tag,
  }) => AugmentedRegExpRecipe(
    source ?? this.source,
    augment ?? this.augment,
    tag: tag ?? this.tag,
  );

  @override
  String _createExpr() => augment(source.compile());
}
typedef Augmenter = String Function(String expr);

final class JoinedRegExpRecipe extends RegExpRecipe {
  final String joinBy;
  final bool allowDuplicateRefs;

  JoinedRegExpRecipe(List<RegExpRecipe> sources, this.joinBy, {super.tag, required this.allowDuplicateRefs}) : 
    super(
      sources,
      GroupTracker.combine(
        sources.map((source) => source._tracker),
        allowDuplicateRefs: allowDuplicateRefs,
      ),
    );

  @override
  JoinedRegExpRecipe copy({
    List<RegExpRecipe>? sources,
    String? joinBy,
    RegExpTag? tag,
    bool? allowDuplicateRefs,
  }) => JoinedRegExpRecipe(
    sources ?? this.sources,
    joinBy ?? this.joinBy,
    tag: tag ?? this.tag,
    allowDuplicateRefs: allowDuplicateRefs ?? this.allowDuplicateRefs,
  );

  @override
  String _createExpr() {
    return sources
      .map((source) => source.compile())
      .join(joinBy);
  }
}


final class InvertibleRegExpRecipe extends AugmentedRegExpRecipe {
  final bool inverted;

  InvertibleRegExpRecipe(super.source, super.augment, {required this.inverted, super.tag});

  @override
  InvertibleRegExpRecipe copy({
    RegExpRecipe? source,
    Augmenter? augment,
    bool? inverted,
    RegExpTag? tag,
  }) => InvertibleRegExpRecipe(
    source ?? this.source,
    augment ?? this.augment,
    inverted: inverted ?? this.inverted,
    tag: tag ?? this.tag,
  );
}

final class TrackedRegExpRecipe extends AugmentedRegExpRecipe {
  @override
  late final GroupTracker _tracker;

  TrackedRegExpRecipe(
    super.source,
    super.augment,
    {
      GroupRef? ref,
      GroupTracker? tracker,
      super.tag,
    }
  ) {
    var newTracker = tracker ?? source._tracker.increment();
    if (ref != null) {
      newTracker = newTracker.startTracking(ref);
    }
    _tracker = newTracker;
  }

  @override
  TrackedRegExpRecipe copy({
    RegExpRecipe? source,
    Augmenter? augment,
    GroupTracker? tracker,
    RegExpTag? tag,
  }) => TrackedRegExpRecipe(
    source ?? this.source,
    augment ?? this.augment,
    tracker: tracker ?? this._tracker,
    tag: tag ?? this.tag,
  );
}


class GroupRef {
  var _positionUsed = false;
  bool get positionUsed => _positionUsed;
}

// TODO: document operation meanings
final class GroupTracker {
  final Map<GroupRef, int> _positions;
  final int _groupCount;
  final Set<GroupRef> _invalidRefs;

  const GroupTracker._create(this._positions, this._groupCount, this._invalidRefs);
  const GroupTracker(): this._create(const {}, 0, const {});

  GroupTracker startTracking(GroupRef newRef, [int position = 1]) {
    _throwIfInvalid(newRef);
    assert (!_positions.containsKey(newRef));
    return GroupTracker._create(
      {
        ..._positions,
        newRef: position,
      },
      _groupCount,
      _invalidRefs,
    );
  }

  int getPosition(GroupRef ref) {
    _throwIfInvalid(ref);
    if (!_positions.containsKey(ref)) throw ArgumentError("Position not tracked for ref!", "ref");
    ref._positionUsed = true;
    return _positions[ref]!;
  }

  int get groupCount => _groupCount;

  GroupTracker increment([int by = 1]) => GroupTracker._create(
    {
      for (var MapEntry(key: groupRef, value: position) in _positions.entries)
        groupRef: position + by,
    },
    _groupCount + by,
    _invalidRefs,
  );

  void _throwIfInvalid(GroupRef ref) {
    var isInvalid = _invalidRefs.contains(ref);
    if (isInvalid) throw ArgumentError("Ref is invalid because it was used multiple times!", "ref");
  }

  static GroupTracker combine(Iterable<GroupTracker> trackers, {bool allowDuplicateRefs = false}) {
    var combinedPositions = <GroupRef, int>{};
    var combinedInvalidRefs = <GroupRef>{};
    var totalGroupCount = 0;

    for (var tracker in trackers) {
      combinedInvalidRefs.addAll(tracker._invalidRefs);
      for (var MapEntry(key: groupRef, value: position) in tracker._positions.entries) {
        if (combinedInvalidRefs.contains(groupRef)) continue;

        if (!combinedPositions.containsKey(groupRef)) {
          combinedPositions[groupRef] = position + totalGroupCount;
        } else if (allowDuplicateRefs) {
          combinedPositions.remove(groupRef);
          combinedInvalidRefs.add(groupRef);
        } else {
          throw ArgumentError("""
A GroupRef was reused in multiple places.
By default, this is not allowed since the GroupRef is no longer a reliable reference.
Pass `allowDuplicateRefs: true` to bypass this error if you understand ."""
          );
        }
      }
      totalGroupCount += tracker._groupCount;
    }

    return GroupTracker._create(combinedPositions, totalGroupCount, combinedInvalidRefs);
  }
}
