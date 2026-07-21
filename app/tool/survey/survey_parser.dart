import 'dart:math' as math;

/// Parser for the `.survey` field format (see surveys/SJT.survey and
/// docs/16-mapping-guide.md).
///
/// Why a bespoke line format rather than YAML/JSON: this file is typed up
/// from paper notes taken while walking a building, often on a laptop in a
/// corridor. Every character of syntax is friction, and a mis-indented YAML
/// block is a far worse failure than a malformed line we can point at with a
/// line number. The parser therefore reports errors as
/// "line 42: <what was wrong>" and keeps going, so one bad line does not
/// hide the other nineteen.
final class SurveyParseException implements Exception {
  SurveyParseException(this.errors);
  final List<String> errors;

  @override
  String toString() => 'Survey has ${errors.length} error(s):\n'
      '${errors.map((e) => '  $e').join('\n')}';
}

final class Survey {
  Survey({
    required this.buildingId,
    required this.buildingName,
    required this.aliases,
    required this.floors,
  });

  final String buildingId;
  final String buildingName;
  final List<String> aliases;
  final List<SurveyFloor> floors;
}

final class SurveyFloor {
  SurveyFloor({
    required this.id,
    required this.level,
    required this.name,
    required this.corridors,
    required this.links,
  });

  final String id;
  final int level;
  final String name;
  final List<SurveyCorridor> corridors;
  final List<SurveyLink> links;
}

final class SurveyCorridor {
  SurveyCorridor({
    required this.id,
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  });

  final String id;
  final double fromX, fromY, toX, toY;

  double get lengthM =>
      math.sqrt(math.pow(toX - fromX, 2) + math.pow(toY - fromY, 2));

  /// Unit vector along the corridor.
  (double, double) get direction {
    final len = lengthM;
    if (len == 0) return (1, 0);
    return ((toX - fromX) / len, (toY - fromY) / len);
  }

  /// Point at [distance] metres along the corridor.
  (double, double) pointAt(double distance) {
    final (dx, dy) = direction;
    return (fromX + dx * distance, fromY + dy * distance);
  }

  /// Point offset perpendicular from the corridor. [side] is 'L' or 'R',
  /// interpreted while walking from `from` towards `to` in a y-down frame:
  /// left is the -90 degree rotation of the direction vector.
  (double, double) offsetPoint(double distance, String side, double offsetM) {
    final (px, py) = pointAt(distance);
    final (dx, dy) = direction;
    // y-down frame: rotating (dx,dy) by -90 deg gives (dy,-dx) = left side.
    final sign = side == 'L' ? 1.0 : -1.0;
    return (px + dy * offsetM * sign, py - dx * offsetM * sign);
  }

  final attachments = <SurveyAttachment>[];
}

/// Anything hanging off a corridor at a measured distance.
final class SurveyAttachment {
  SurveyAttachment({
    required this.kind,
    required this.distance,
    required this.side,
    required this.id,
    this.name,
    this.type,
    this.aliases = const [],
    this.tags = const {},
    this.line = 0,
  });

  final AttachmentKind kind;
  final double distance;
  final String side;
  final String id;
  final String? name;

  /// Room type or POI type, as written in the survey.
  final String? type;
  final List<String> aliases;
  final Map<String, String> tags;
  final int line;
}

enum AttachmentKind { room, poi, stair, lift, entrance }

/// Joins two corridors on the same floor at given distances along each.
final class SurveyLink {
  SurveyLink(this.corridorA, this.distanceA, this.corridorB, this.distanceB);
  final String corridorA;
  final double distanceA;
  final String corridorB;
  final double distanceB;
}

Survey parseSurvey(String source) {
  final errors = <String>[];
  String? buildingId;
  String? buildingName;
  var aliases = <String>[];
  final floors = <SurveyFloor>[];
  SurveyFloor? floor;
  SurveyCorridor? corridor;

  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final lineNo = i + 1;
    final raw = lines[i];
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;

    final tokens = _tokenize(line);
    if (tokens.isEmpty) continue;
    final command = tokens.first;
    final args = tokens.skip(1).toList();

    void err(String message) => errors.add('line $lineNo: $message');

    switch (command) {
      case 'building':
        if (args.length < 2) {
          err('building needs <ID> "<Name>"');
          continue;
        }
        buildingId = args[0];
        buildingName = args[1];
        aliases = _namedList(args, 'alias');

      case 'floor':
        if (args.length < 3) {
          err('floor needs <id> level=<int> "<Name>"');
          continue;
        }
        final level = int.tryParse(_named(args, 'level') ?? '');
        if (level == null) {
          err('floor is missing a valid level=<int>');
          continue;
        }
        floor = SurveyFloor(
          id: args[0],
          level: level,
          name: args.last,
          corridors: [],
          links: [],
        );
        floors.add(floor);
        corridor = null;

      case 'corridor':
        if (floor == null) {
          err('corridor before any floor');
          continue;
        }
        if (args.isEmpty) {
          err('corridor needs an id');
          continue;
        }
        // Two ways to declare a corridor. Explicit endpoints:
        //   corridor c_main from=0,20 to=60,20
        // or — far easier to write from field notes, where you know the
        // length you paced and roughly which way you walked:
        //   corridor c_main length=60 heading=E [start=0,20]
        final from = _coord(_named(args, 'from'));
        final to = _coord(_named(args, 'to'));
        final length = double.tryParse(_named(args, 'length') ?? '');
        if (from != null && to != null) {
          corridor = SurveyCorridor(
            id: args[0],
            fromX: from.$1,
            fromY: from.$2,
            toX: to.$1,
            toY: to.$2,
          );
        } else if (length != null) {
          final heading = (_named(args, 'heading') ?? 'E').toUpperCase();
          final start = _coord(_named(args, 'start')) ??
              // Sensible default origins so a single-corridor floor needs no
              // coordinates at all: run east from the left edge, or south
              // from the top edge.
              (heading == 'N' || heading == 'S' ? (20.0, 0.0) : (0.0, 20.0));
          final (dx, dy) = switch (heading) {
            'E' => (1.0, 0.0),
            'W' => (-1.0, 0.0),
            'S' => (0.0, 1.0),
            'N' => (0.0, -1.0),
            _ => (1.0, 0.0),
          };
          if (!const {'E', 'W', 'N', 'S'}.contains(heading)) {
            err('heading must be E, W, N or S (got "$heading"); assuming E');
          }
          corridor = SurveyCorridor(
            id: args[0],
            fromX: start.$1,
            fromY: start.$2,
            toX: start.$1 + dx * length,
            toY: start.$2 + dy * length,
          );
        } else {
          err('corridor needs either from=<x>,<y> to=<x>,<y> '
              'or length=<metres> [heading=E|W|N|S]');
          continue;
        }
        floor.corridors.add(corridor);

      case 'room':
      case 'poi':
      case 'stair':
      case 'lift':
      case 'entrance':
        if (corridor == null) {
          err('$command before any corridor');
          continue;
        }
        final attachment = _parseAttachment(command, args, lineNo, err);
        if (attachment != null) corridor.attachments.add(attachment);

      case 'link':
        if (floor == null) {
          err('link before any floor');
          continue;
        }
        if (args.length < 4) {
          err('link needs <corridorA> <distA> <corridorB> <distB>');
          continue;
        }
        final da = double.tryParse(args[1]);
        final db = double.tryParse(args[3]);
        if (da == null || db == null) {
          err('link distances must be numbers');
          continue;
        }
        floor.links.add(SurveyLink(args[0], da, args[2], db));

      default:
        err('unknown command "$command"');
    }
  }

  if (buildingId == null || buildingName == null) {
    errors.add('missing: building <ID> "<Name>"');
  }
  if (floors.isEmpty) errors.add('survey declares no floors');
  if (errors.isNotEmpty) throw SurveyParseException(errors);

  return Survey(
    buildingId: buildingId!,
    buildingName: buildingName!,
    aliases: aliases,
    floors: floors,
  );
}

SurveyAttachment? _parseAttachment(
  String command,
  List<String> args,
  int lineNo,
  void Function(String) err,
) {
  if (args.length < 2) {
    err('$command needs at least <distance> <L|R>');
    return null;
  }
  final distance = double.tryParse(args[0]);
  if (distance == null) {
    err('$command distance "${args[0]}" is not a number');
    return null;
  }
  final side = args[1].toUpperCase();
  if (side != 'L' && side != 'R') {
    err('$command side must be L or R, got "${args[1]}"');
    return null;
  }
  final rest = args.skip(2).where((a) => !a.contains('=')).toList();

  switch (command) {
    case 'room':
      if (rest.length < 3) {
        err('room needs <id> "<Name>" <type>');
        return null;
      }
      return SurveyAttachment(
        kind: AttachmentKind.room,
        distance: distance,
        side: side,
        id: rest[0],
        name: rest[1],
        type: rest[2],
        aliases: _namedList(args, 'alias'),
        tags: _tags(args),
        line: lineNo,
      );
    case 'poi':
      if (rest.isEmpty) {
        err('poi needs a <type>');
        return null;
      }
      return SurveyAttachment(
        kind: AttachmentKind.poi,
        distance: distance,
        side: side,
        id: _named(args, 'id') ?? 'poi_${command}_$lineNo',
        name: rest.length > 1 ? rest[1] : null,
        type: rest[0],
        line: lineNo,
      );
    default:
      if (rest.isEmpty) {
        err('$command needs a shared id');
        return null;
      }
      return SurveyAttachment(
        kind: switch (command) {
          'stair' => AttachmentKind.stair,
          'lift' => AttachmentKind.lift,
          _ => AttachmentKind.entrance,
        },
        distance: distance,
        side: side,
        id: rest[0],
        line: lineNo,
      );
  }
}

/// Splits on whitespace but keeps "quoted strings" together (quotes removed).
List<String> _tokenize(String line) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (final rune in line.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (char == ' ' && !inQuotes) {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) tokens.add(buffer.toString());
  return tokens;
}

String? _named(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  return null;
}

List<String> _namedList(List<String> args, String key) {
  final value = _named(args, key);
  if (value == null) return const [];
  return value
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

Map<String, String> _tags(List<String> args) {
  final tags = <String, String>{};
  for (final a in args) {
    if (!a.startsWith('tag:')) continue;
    final body = a.substring(4);
    final eq = body.indexOf('=');
    if (eq > 0) tags[body.substring(0, eq)] = body.substring(eq + 1);
  }
  return tags;
}

(double, double)? _coord(String? value) {
  if (value == null) return null;
  final parts = value.split(',');
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0]);
  final y = double.tryParse(parts[1]);
  if (x == null || y == null) return null;
  return (x, y);
}
