// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmark_record.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetBookmarkRecordCollection on Isar {
  IsarCollection<BookmarkRecord> get bookmarkRecords => this.collection();
}

const BookmarkRecordSchema = CollectionSchema(
  name: r'BookmarkRecord',
  id: -3175551374250870718,
  properties: {
    r'customName': PropertySchema(
      id: 0,
      name: r'customName',
      type: IsarType.string,
    ),
    r'lastUsedAt': PropertySchema(
      id: 1,
      name: r'lastUsedAt',
      type: IsarType.dateTime,
    ),
    r'payload': PropertySchema(
      id: 2,
      name: r'payload',
      type: IsarType.object,

      target: r'RoomInvitePayloadRecord',
    ),
    r'pinned': PropertySchema(id: 3, name: r'pinned', type: IsarType.bool),
    r'savedAt': PropertySchema(
      id: 4,
      name: r'savedAt',
      type: IsarType.dateTime,
    ),
  },

  estimateSize: _bookmarkRecordEstimateSize,
  serialize: _bookmarkRecordSerialize,
  deserialize: _bookmarkRecordDeserialize,
  deserializeProp: _bookmarkRecordDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {
    r'RoomInvitePayloadRecord': RoomInvitePayloadRecordSchema,
    r'PeerEndpointRecord': PeerEndpointRecordSchema,
  },

  getId: _bookmarkRecordGetId,
  getLinks: _bookmarkRecordGetLinks,
  attach: _bookmarkRecordAttach,
  version: '3.3.2',
);

int _bookmarkRecordEstimateSize(
  BookmarkRecord object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.customName.length * 3;
  bytesCount +=
      3 +
      RoomInvitePayloadRecordSchema.estimateSize(
        object.payload,
        allOffsets[RoomInvitePayloadRecord]!,
        allOffsets,
      );
  return bytesCount;
}

void _bookmarkRecordSerialize(
  BookmarkRecord object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.customName);
  writer.writeDateTime(offsets[1], object.lastUsedAt);
  writer.writeObject<RoomInvitePayloadRecord>(
    offsets[2],
    allOffsets,
    RoomInvitePayloadRecordSchema.serialize,
    object.payload,
  );
  writer.writeBool(offsets[3], object.pinned);
  writer.writeDateTime(offsets[4], object.savedAt);
}

BookmarkRecord _bookmarkRecordDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = BookmarkRecord();
  object.customName = reader.readString(offsets[0]);
  object.id = id;
  object.lastUsedAt = reader.readDateTimeOrNull(offsets[1]);
  object.payload =
      reader.readObjectOrNull<RoomInvitePayloadRecord>(
        offsets[2],
        RoomInvitePayloadRecordSchema.deserialize,
        allOffsets,
      ) ??
      RoomInvitePayloadRecord();
  object.pinned = reader.readBool(offsets[3]);
  object.savedAt = reader.readDateTime(offsets[4]);
  return object;
}

P _bookmarkRecordDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 2:
      return (reader.readObjectOrNull<RoomInvitePayloadRecord>(
                offset,
                RoomInvitePayloadRecordSchema.deserialize,
                allOffsets,
              ) ??
              RoomInvitePayloadRecord())
          as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _bookmarkRecordGetId(BookmarkRecord object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _bookmarkRecordGetLinks(BookmarkRecord object) {
  return [];
}

void _bookmarkRecordAttach(
  IsarCollection<dynamic> col,
  Id id,
  BookmarkRecord object,
) {
  object.id = id;
}

extension BookmarkRecordQueryWhereSort
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QWhere> {
  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension BookmarkRecordQueryWhere
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QWhereClause> {
  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension BookmarkRecordQueryFilter
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QFilterCondition> {
  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'customName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'customName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'customName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'customName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'customName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'customName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'customName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'customName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'customName', value: ''),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  customNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'customName', value: ''),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  lastUsedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastUsedAt'),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  lastUsedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastUsedAt'),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  lastUsedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastUsedAt', value: value),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  lastUsedAtGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastUsedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  lastUsedAtLessThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastUsedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  lastUsedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastUsedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  pinnedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'pinned', value: value),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  savedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'savedAt', value: value),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  savedAtGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'savedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  savedAtLessThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'savedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition>
  savedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'savedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension BookmarkRecordQueryObject
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QFilterCondition> {
  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterFilterCondition> payload(
    FilterQuery<RoomInvitePayloadRecord> q,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'payload');
    });
  }
}

extension BookmarkRecordQueryLinks
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QFilterCondition> {}

extension BookmarkRecordQuerySortBy
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QSortBy> {
  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  sortByCustomName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customName', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  sortByCustomNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customName', Sort.desc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  sortByLastUsedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUsedAt', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  sortByLastUsedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUsedAt', Sort.desc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy> sortByPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pinned', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  sortByPinnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pinned', Sort.desc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy> sortBySavedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'savedAt', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  sortBySavedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'savedAt', Sort.desc);
    });
  }
}

extension BookmarkRecordQuerySortThenBy
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QSortThenBy> {
  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  thenByCustomName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customName', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  thenByCustomNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customName', Sort.desc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  thenByLastUsedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUsedAt', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  thenByLastUsedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUsedAt', Sort.desc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy> thenByPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pinned', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  thenByPinnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pinned', Sort.desc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy> thenBySavedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'savedAt', Sort.asc);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QAfterSortBy>
  thenBySavedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'savedAt', Sort.desc);
    });
  }
}

extension BookmarkRecordQueryWhereDistinct
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QDistinct> {
  QueryBuilder<BookmarkRecord, BookmarkRecord, QDistinct> distinctByCustomName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'customName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QDistinct>
  distinctByLastUsedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastUsedAt');
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QDistinct> distinctByPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pinned');
    });
  }

  QueryBuilder<BookmarkRecord, BookmarkRecord, QDistinct> distinctBySavedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'savedAt');
    });
  }
}

extension BookmarkRecordQueryProperty
    on QueryBuilder<BookmarkRecord, BookmarkRecord, QQueryProperty> {
  QueryBuilder<BookmarkRecord, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<BookmarkRecord, String, QQueryOperations> customNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'customName');
    });
  }

  QueryBuilder<BookmarkRecord, DateTime?, QQueryOperations>
  lastUsedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastUsedAt');
    });
  }

  QueryBuilder<BookmarkRecord, RoomInvitePayloadRecord, QQueryOperations>
  payloadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payload');
    });
  }

  QueryBuilder<BookmarkRecord, bool, QQueryOperations> pinnedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pinned');
    });
  }

  QueryBuilder<BookmarkRecord, DateTime, QQueryOperations> savedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'savedAt');
    });
  }
}

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const RoomInvitePayloadRecordSchema = Schema(
  name: r'RoomInvitePayloadRecord',
  id: -1057582922154870854,
  properties: {
    r'displayName': PropertySchema(
      id: 0,
      name: r'displayName',
      type: IsarType.string,
    ),
    r'gameId': PropertySchema(id: 1, name: r'gameId', type: IsarType.string),
    r'gameName': PropertySchema(
      id: 2,
      name: r'gameName',
      type: IsarType.string,
    ),
    r'networkName': PropertySchema(
      id: 3,
      name: r'networkName',
      type: IsarType.string,
    ),
    r'networkSecret': PropertySchema(
      id: 4,
      name: r'networkSecret',
      type: IsarType.string,
    ),
    r'peers': PropertySchema(
      id: 5,
      name: r'peers',
      type: IsarType.objectList,

      target: r'PeerEndpointRecord',
    ),
    r'v': PropertySchema(id: 6, name: r'v', type: IsarType.long),
  },

  estimateSize: _roomInvitePayloadRecordEstimateSize,
  serialize: _roomInvitePayloadRecordSerialize,
  deserialize: _roomInvitePayloadRecordDeserialize,
  deserializeProp: _roomInvitePayloadRecordDeserializeProp,
);

int _roomInvitePayloadRecordEstimateSize(
  RoomInvitePayloadRecord object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.displayName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.gameId.length * 3;
  bytesCount += 3 + object.gameName.length * 3;
  bytesCount += 3 + object.networkName.length * 3;
  bytesCount += 3 + object.networkSecret.length * 3;
  bytesCount += 3 + object.peers.length * 3;
  {
    final offsets = allOffsets[PeerEndpointRecord]!;
    for (var i = 0; i < object.peers.length; i++) {
      final value = object.peers[i];
      bytesCount += PeerEndpointRecordSchema.estimateSize(
        value,
        offsets,
        allOffsets,
      );
    }
  }
  return bytesCount;
}

void _roomInvitePayloadRecordSerialize(
  RoomInvitePayloadRecord object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.displayName);
  writer.writeString(offsets[1], object.gameId);
  writer.writeString(offsets[2], object.gameName);
  writer.writeString(offsets[3], object.networkName);
  writer.writeString(offsets[4], object.networkSecret);
  writer.writeObjectList<PeerEndpointRecord>(
    offsets[5],
    allOffsets,
    PeerEndpointRecordSchema.serialize,
    object.peers,
  );
  writer.writeLong(offsets[6], object.v);
}

RoomInvitePayloadRecord _roomInvitePayloadRecordDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = RoomInvitePayloadRecord();
  object.displayName = reader.readStringOrNull(offsets[0]);
  object.gameId = reader.readString(offsets[1]);
  object.gameName = reader.readString(offsets[2]);
  object.networkName = reader.readString(offsets[3]);
  object.networkSecret = reader.readString(offsets[4]);
  object.peers =
      reader.readObjectList<PeerEndpointRecord>(
        offsets[5],
        PeerEndpointRecordSchema.deserialize,
        allOffsets,
        PeerEndpointRecord(),
      ) ??
      [];
  object.v = reader.readLong(offsets[6]);
  return object;
}

P _roomInvitePayloadRecordDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readObjectList<PeerEndpointRecord>(
                offset,
                PeerEndpointRecordSchema.deserialize,
                allOffsets,
                PeerEndpointRecord(),
              ) ??
              [])
          as P;
    case 6:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension RoomInvitePayloadRecordQueryFilter
    on
        QueryBuilder<
          RoomInvitePayloadRecord,
          RoomInvitePayloadRecord,
          QFilterCondition
        > {
  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'displayName'),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'displayName'),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'displayName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'displayName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'displayName', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  displayNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'displayName', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'gameId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'gameId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'gameId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'gameId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'gameId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'gameId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'gameId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'gameId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'gameId', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'gameId', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'gameName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'gameName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'gameName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'gameName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'gameName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'gameName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'gameName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'gameName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'gameName', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  gameNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'gameName', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'networkName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'networkName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'networkName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'networkName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'networkName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'networkName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'networkName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'networkName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'networkName', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'networkName', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'networkSecret',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'networkSecret',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'networkSecret',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'networkSecret',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'networkSecret',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'networkSecret',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'networkSecret',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'networkSecret',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'networkSecret', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  networkSecretIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'networkSecret', value: ''),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  peersLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'peers', length, true, length, true);
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  peersIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'peers', 0, true, 0, true);
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  peersIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'peers', 0, false, 999999, true);
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  peersLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'peers', 0, true, length, include);
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  peersLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'peers', length, include, 999999, true);
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  peersLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'peers',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  vEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'v', value: value),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  vGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'v',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  vLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'v',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  vBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'v',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension RoomInvitePayloadRecordQueryObject
    on
        QueryBuilder<
          RoomInvitePayloadRecord,
          RoomInvitePayloadRecord,
          QFilterCondition
        > {
  QueryBuilder<
    RoomInvitePayloadRecord,
    RoomInvitePayloadRecord,
    QAfterFilterCondition
  >
  peersElement(FilterQuery<PeerEndpointRecord> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'peers');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const PeerEndpointRecordSchema = Schema(
  name: r'PeerEndpointRecord',
  id: 3522805546583797839,
  properties: {
    r'uri': PropertySchema(id: 0, name: r'uri', type: IsarType.string),
  },

  estimateSize: _peerEndpointRecordEstimateSize,
  serialize: _peerEndpointRecordSerialize,
  deserialize: _peerEndpointRecordDeserialize,
  deserializeProp: _peerEndpointRecordDeserializeProp,
);

int _peerEndpointRecordEstimateSize(
  PeerEndpointRecord object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.uri.length * 3;
  return bytesCount;
}

void _peerEndpointRecordSerialize(
  PeerEndpointRecord object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.uri);
}

PeerEndpointRecord _peerEndpointRecordDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PeerEndpointRecord();
  object.uri = reader.readString(offsets[0]);
  return object;
}

P _peerEndpointRecordDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension PeerEndpointRecordQueryFilter
    on QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QFilterCondition> {
  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'uri',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'uri',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriLessThan(String value, {bool include = false, bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'uri',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'uri',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'uri',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'uri',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'uri',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'uri',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'uri', value: ''),
      );
    });
  }

  QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QAfterFilterCondition>
  uriIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'uri', value: ''),
      );
    });
  }
}

extension PeerEndpointRecordQueryObject
    on QueryBuilder<PeerEndpointRecord, PeerEndpointRecord, QFilterCondition> {}
