// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_database.dart';

// ignore_for_file: type=lint
class $LocalMealsTable extends LocalMeals
    with TableInfo<$LocalMealsTable, LocalMeal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMealsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealTypeMeta = const VerificationMeta(
    'mealType',
  );
  @override
  late final GeneratedColumn<String> mealType = GeneratedColumn<String>(
    'meal_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foodsMeta = const VerificationMeta('foods');
  @override
  late final GeneratedColumn<String> foods = GeneratedColumn<String>(
    'foods',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loggedAtMeta = const VerificationMeta(
    'loggedAt',
  );
  @override
  late final GeneratedColumn<int> loggedAt = GeneratedColumn<int>(
    'logged_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _claudeNoteMeta = const VerificationMeta(
    'claudeNote',
  );
  @override
  late final GeneratedColumn<String> claudeNote = GeneratedColumn<String>(
    'claude_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    description,
    mealType,
    foods,
    loggedAt,
    claudeNote,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_meals';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMeal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('meal_type')) {
      context.handle(
        _mealTypeMeta,
        mealType.isAcceptableOrUnknown(data['meal_type']!, _mealTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mealTypeMeta);
    }
    if (data.containsKey('foods')) {
      context.handle(
        _foodsMeta,
        foods.isAcceptableOrUnknown(data['foods']!, _foodsMeta),
      );
    } else if (isInserting) {
      context.missing(_foodsMeta);
    }
    if (data.containsKey('logged_at')) {
      context.handle(
        _loggedAtMeta,
        loggedAt.isAcceptableOrUnknown(data['logged_at']!, _loggedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_loggedAtMeta);
    }
    if (data.containsKey('claude_note')) {
      context.handle(
        _claudeNoteMeta,
        claudeNote.isAcceptableOrUnknown(data['claude_note']!, _claudeNoteMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalMeal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMeal(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      mealType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_type'],
      )!,
      foods: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}foods'],
      )!,
      loggedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logged_at'],
      )!,
      claudeNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}claude_note'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalMealsTable createAlias(String alias) {
    return $LocalMealsTable(attachedDatabase, alias);
  }
}

class LocalMeal extends DataClass implements Insertable<LocalMeal> {
  final String id;
  final String? serverId;
  final String description;
  final String mealType;
  final String foods;
  final int loggedAt;
  final String? claudeNote;
  final String syncStatus;
  const LocalMeal({
    required this.id,
    this.serverId,
    required this.description,
    required this.mealType,
    required this.foods,
    required this.loggedAt,
    this.claudeNote,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['description'] = Variable<String>(description);
    map['meal_type'] = Variable<String>(mealType);
    map['foods'] = Variable<String>(foods);
    map['logged_at'] = Variable<int>(loggedAt);
    if (!nullToAbsent || claudeNote != null) {
      map['claude_note'] = Variable<String>(claudeNote);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalMealsCompanion toCompanion(bool nullToAbsent) {
    return LocalMealsCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      description: Value(description),
      mealType: Value(mealType),
      foods: Value(foods),
      loggedAt: Value(loggedAt),
      claudeNote: claudeNote == null && nullToAbsent
          ? const Value.absent()
          : Value(claudeNote),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalMeal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMeal(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      description: serializer.fromJson<String>(json['description']),
      mealType: serializer.fromJson<String>(json['mealType']),
      foods: serializer.fromJson<String>(json['foods']),
      loggedAt: serializer.fromJson<int>(json['loggedAt']),
      claudeNote: serializer.fromJson<String?>(json['claudeNote']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'description': serializer.toJson<String>(description),
      'mealType': serializer.toJson<String>(mealType),
      'foods': serializer.toJson<String>(foods),
      'loggedAt': serializer.toJson<int>(loggedAt),
      'claudeNote': serializer.toJson<String?>(claudeNote),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalMeal copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    String? description,
    String? mealType,
    String? foods,
    int? loggedAt,
    Value<String?> claudeNote = const Value.absent(),
    String? syncStatus,
  }) => LocalMeal(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    description: description ?? this.description,
    mealType: mealType ?? this.mealType,
    foods: foods ?? this.foods,
    loggedAt: loggedAt ?? this.loggedAt,
    claudeNote: claudeNote.present ? claudeNote.value : this.claudeNote,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  LocalMeal copyWithCompanion(LocalMealsCompanion data) {
    return LocalMeal(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      description: data.description.present
          ? data.description.value
          : this.description,
      mealType: data.mealType.present ? data.mealType.value : this.mealType,
      foods: data.foods.present ? data.foods.value : this.foods,
      loggedAt: data.loggedAt.present ? data.loggedAt.value : this.loggedAt,
      claudeNote: data.claudeNote.present
          ? data.claudeNote.value
          : this.claudeNote,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMeal(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('description: $description, ')
          ..write('mealType: $mealType, ')
          ..write('foods: $foods, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('claudeNote: $claudeNote, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    description,
    mealType,
    foods,
    loggedAt,
    claudeNote,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMeal &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.description == this.description &&
          other.mealType == this.mealType &&
          other.foods == this.foods &&
          other.loggedAt == this.loggedAt &&
          other.claudeNote == this.claudeNote &&
          other.syncStatus == this.syncStatus);
}

class LocalMealsCompanion extends UpdateCompanion<LocalMeal> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String> description;
  final Value<String> mealType;
  final Value<String> foods;
  final Value<int> loggedAt;
  final Value<String?> claudeNote;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalMealsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.description = const Value.absent(),
    this.mealType = const Value.absent(),
    this.foods = const Value.absent(),
    this.loggedAt = const Value.absent(),
    this.claudeNote = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMealsCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    required String description,
    required String mealType,
    required String foods,
    required int loggedAt,
    this.claudeNote = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       description = Value(description),
       mealType = Value(mealType),
       foods = Value(foods),
       loggedAt = Value(loggedAt);
  static Insertable<LocalMeal> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? description,
    Expression<String>? mealType,
    Expression<String>? foods,
    Expression<int>? loggedAt,
    Expression<String>? claudeNote,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (description != null) 'description': description,
      if (mealType != null) 'meal_type': mealType,
      if (foods != null) 'foods': foods,
      if (loggedAt != null) 'logged_at': loggedAt,
      if (claudeNote != null) 'claude_note': claudeNote,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMealsCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String>? description,
    Value<String>? mealType,
    Value<String>? foods,
    Value<int>? loggedAt,
    Value<String?>? claudeNote,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return LocalMealsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      description: description ?? this.description,
      mealType: mealType ?? this.mealType,
      foods: foods ?? this.foods,
      loggedAt: loggedAt ?? this.loggedAt,
      claudeNote: claudeNote ?? this.claudeNote,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (mealType.present) {
      map['meal_type'] = Variable<String>(mealType.value);
    }
    if (foods.present) {
      map['foods'] = Variable<String>(foods.value);
    }
    if (loggedAt.present) {
      map['logged_at'] = Variable<int>(loggedAt.value);
    }
    if (claudeNote.present) {
      map['claude_note'] = Variable<String>(claudeNote.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMealsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('description: $description, ')
          ..write('mealType: $mealType, ')
          ..write('foods: $foods, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('claudeNote: $claudeNote, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSymptomsTable extends LocalSymptoms
    with TableInfo<$LocalSymptomsTable, LocalSymptom> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSymptomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<int> severity = GeneratedColumn<int>(
    'severity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _linkedMealIdMeta = const VerificationMeta(
    'linkedMealId',
  );
  @override
  late final GeneratedColumn<String> linkedMealId = GeneratedColumn<String>(
    'linked_meal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _loggedAtMeta = const VerificationMeta(
    'loggedAt',
  );
  @override
  late final GeneratedColumn<int> loggedAt = GeneratedColumn<int>(
    'logged_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    description,
    severity,
    linkedMealId,
    loggedAt,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_symptoms';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSymptom> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    }
    if (data.containsKey('linked_meal_id')) {
      context.handle(
        _linkedMealIdMeta,
        linkedMealId.isAcceptableOrUnknown(
          data['linked_meal_id']!,
          _linkedMealIdMeta,
        ),
      );
    }
    if (data.containsKey('logged_at')) {
      context.handle(
        _loggedAtMeta,
        loggedAt.isAcceptableOrUnknown(data['logged_at']!, _loggedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_loggedAtMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSymptom map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSymptom(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}severity'],
      )!,
      linkedMealId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_meal_id'],
      ),
      loggedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logged_at'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalSymptomsTable createAlias(String alias) {
    return $LocalSymptomsTable(attachedDatabase, alias);
  }
}

class LocalSymptom extends DataClass implements Insertable<LocalSymptom> {
  final String id;
  final String? serverId;
  final String description;
  final int severity;
  final String? linkedMealId;
  final int loggedAt;
  final String syncStatus;
  const LocalSymptom({
    required this.id,
    this.serverId,
    required this.description,
    required this.severity,
    this.linkedMealId,
    required this.loggedAt,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['description'] = Variable<String>(description);
    map['severity'] = Variable<int>(severity);
    if (!nullToAbsent || linkedMealId != null) {
      map['linked_meal_id'] = Variable<String>(linkedMealId);
    }
    map['logged_at'] = Variable<int>(loggedAt);
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalSymptomsCompanion toCompanion(bool nullToAbsent) {
    return LocalSymptomsCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      description: Value(description),
      severity: Value(severity),
      linkedMealId: linkedMealId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedMealId),
      loggedAt: Value(loggedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalSymptom.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSymptom(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      description: serializer.fromJson<String>(json['description']),
      severity: serializer.fromJson<int>(json['severity']),
      linkedMealId: serializer.fromJson<String?>(json['linkedMealId']),
      loggedAt: serializer.fromJson<int>(json['loggedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'description': serializer.toJson<String>(description),
      'severity': serializer.toJson<int>(severity),
      'linkedMealId': serializer.toJson<String?>(linkedMealId),
      'loggedAt': serializer.toJson<int>(loggedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalSymptom copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    String? description,
    int? severity,
    Value<String?> linkedMealId = const Value.absent(),
    int? loggedAt,
    String? syncStatus,
  }) => LocalSymptom(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    description: description ?? this.description,
    severity: severity ?? this.severity,
    linkedMealId: linkedMealId.present ? linkedMealId.value : this.linkedMealId,
    loggedAt: loggedAt ?? this.loggedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  LocalSymptom copyWithCompanion(LocalSymptomsCompanion data) {
    return LocalSymptom(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      description: data.description.present
          ? data.description.value
          : this.description,
      severity: data.severity.present ? data.severity.value : this.severity,
      linkedMealId: data.linkedMealId.present
          ? data.linkedMealId.value
          : this.linkedMealId,
      loggedAt: data.loggedAt.present ? data.loggedAt.value : this.loggedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSymptom(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('description: $description, ')
          ..write('severity: $severity, ')
          ..write('linkedMealId: $linkedMealId, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    description,
    severity,
    linkedMealId,
    loggedAt,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSymptom &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.description == this.description &&
          other.severity == this.severity &&
          other.linkedMealId == this.linkedMealId &&
          other.loggedAt == this.loggedAt &&
          other.syncStatus == this.syncStatus);
}

class LocalSymptomsCompanion extends UpdateCompanion<LocalSymptom> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<String> description;
  final Value<int> severity;
  final Value<String?> linkedMealId;
  final Value<int> loggedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalSymptomsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.description = const Value.absent(),
    this.severity = const Value.absent(),
    this.linkedMealId = const Value.absent(),
    this.loggedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSymptomsCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    required String description,
    this.severity = const Value.absent(),
    this.linkedMealId = const Value.absent(),
    required int loggedAt,
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       description = Value(description),
       loggedAt = Value(loggedAt);
  static Insertable<LocalSymptom> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? description,
    Expression<int>? severity,
    Expression<String>? linkedMealId,
    Expression<int>? loggedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (description != null) 'description': description,
      if (severity != null) 'severity': severity,
      if (linkedMealId != null) 'linked_meal_id': linkedMealId,
      if (loggedAt != null) 'logged_at': loggedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSymptomsCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<String>? description,
    Value<int>? severity,
    Value<String?>? linkedMealId,
    Value<int>? loggedAt,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return LocalSymptomsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      linkedMealId: linkedMealId ?? this.linkedMealId,
      loggedAt: loggedAt ?? this.loggedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (severity.present) {
      map['severity'] = Variable<int>(severity.value);
    }
    if (linkedMealId.present) {
      map['linked_meal_id'] = Variable<String>(linkedMealId.value);
    }
    if (loggedAt.present) {
      map['logged_at'] = Variable<int>(loggedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSymptomsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('description: $description, ')
          ..write('severity: $severity, ')
          ..write('linkedMealId: $linkedMealId, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalWellbeingTable extends LocalWellbeing
    with TableInfo<$LocalWellbeingTable, LocalWellbeingData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalWellbeingTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _energyMeta = const VerificationMeta('energy');
  @override
  late final GeneratedColumn<int> energy = GeneratedColumn<int>(
    'energy',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(3),
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<int> mood = GeneratedColumn<int>(
    'mood',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(3),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
    'period',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _loggedAtMeta = const VerificationMeta(
    'loggedAt',
  );
  @override
  late final GeneratedColumn<int> loggedAt = GeneratedColumn<int>(
    'logged_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    energy,
    mood,
    notes,
    period,
    loggedAt,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_wellbeing';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalWellbeingData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('energy')) {
      context.handle(
        _energyMeta,
        energy.isAcceptableOrUnknown(data['energy']!, _energyMeta),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('period')) {
      context.handle(
        _periodMeta,
        period.isAcceptableOrUnknown(data['period']!, _periodMeta),
      );
    }
    if (data.containsKey('logged_at')) {
      context.handle(
        _loggedAtMeta,
        loggedAt.isAcceptableOrUnknown(data['logged_at']!, _loggedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_loggedAtMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalWellbeingData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalWellbeingData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      energy: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}energy'],
      )!,
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mood'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      period: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period'],
      ),
      loggedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logged_at'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalWellbeingTable createAlias(String alias) {
    return $LocalWellbeingTable(attachedDatabase, alias);
  }
}

class LocalWellbeingData extends DataClass
    implements Insertable<LocalWellbeingData> {
  final String id;
  final String? serverId;
  final int energy;
  final int mood;
  final String? notes;
  final String? period;
  final int loggedAt;
  final String syncStatus;
  const LocalWellbeingData({
    required this.id,
    this.serverId,
    required this.energy,
    required this.mood,
    this.notes,
    this.period,
    required this.loggedAt,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['energy'] = Variable<int>(energy);
    map['mood'] = Variable<int>(mood);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || period != null) {
      map['period'] = Variable<String>(period);
    }
    map['logged_at'] = Variable<int>(loggedAt);
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalWellbeingCompanion toCompanion(bool nullToAbsent) {
    return LocalWellbeingCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      energy: Value(energy),
      mood: Value(mood),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      period: period == null && nullToAbsent
          ? const Value.absent()
          : Value(period),
      loggedAt: Value(loggedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalWellbeingData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalWellbeingData(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      energy: serializer.fromJson<int>(json['energy']),
      mood: serializer.fromJson<int>(json['mood']),
      notes: serializer.fromJson<String?>(json['notes']),
      period: serializer.fromJson<String?>(json['period']),
      loggedAt: serializer.fromJson<int>(json['loggedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String?>(serverId),
      'energy': serializer.toJson<int>(energy),
      'mood': serializer.toJson<int>(mood),
      'notes': serializer.toJson<String?>(notes),
      'period': serializer.toJson<String?>(period),
      'loggedAt': serializer.toJson<int>(loggedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalWellbeingData copyWith({
    String? id,
    Value<String?> serverId = const Value.absent(),
    int? energy,
    int? mood,
    Value<String?> notes = const Value.absent(),
    Value<String?> period = const Value.absent(),
    int? loggedAt,
    String? syncStatus,
  }) => LocalWellbeingData(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    energy: energy ?? this.energy,
    mood: mood ?? this.mood,
    notes: notes.present ? notes.value : this.notes,
    period: period.present ? period.value : this.period,
    loggedAt: loggedAt ?? this.loggedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  LocalWellbeingData copyWithCompanion(LocalWellbeingCompanion data) {
    return LocalWellbeingData(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      energy: data.energy.present ? data.energy.value : this.energy,
      mood: data.mood.present ? data.mood.value : this.mood,
      notes: data.notes.present ? data.notes.value : this.notes,
      period: data.period.present ? data.period.value : this.period,
      loggedAt: data.loggedAt.present ? data.loggedAt.value : this.loggedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalWellbeingData(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('energy: $energy, ')
          ..write('mood: $mood, ')
          ..write('notes: $notes, ')
          ..write('period: $period, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    energy,
    mood,
    notes,
    period,
    loggedAt,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalWellbeingData &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.energy == this.energy &&
          other.mood == this.mood &&
          other.notes == this.notes &&
          other.period == this.period &&
          other.loggedAt == this.loggedAt &&
          other.syncStatus == this.syncStatus);
}

class LocalWellbeingCompanion extends UpdateCompanion<LocalWellbeingData> {
  final Value<String> id;
  final Value<String?> serverId;
  final Value<int> energy;
  final Value<int> mood;
  final Value<String?> notes;
  final Value<String?> period;
  final Value<int> loggedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalWellbeingCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.energy = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.period = const Value.absent(),
    this.loggedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalWellbeingCompanion.insert({
    required String id,
    this.serverId = const Value.absent(),
    this.energy = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.period = const Value.absent(),
    required int loggedAt,
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       loggedAt = Value(loggedAt);
  static Insertable<LocalWellbeingData> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<int>? energy,
    Expression<int>? mood,
    Expression<String>? notes,
    Expression<String>? period,
    Expression<int>? loggedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (energy != null) 'energy': energy,
      if (mood != null) 'mood': mood,
      if (notes != null) 'notes': notes,
      if (period != null) 'period': period,
      if (loggedAt != null) 'logged_at': loggedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalWellbeingCompanion copyWith({
    Value<String>? id,
    Value<String?>? serverId,
    Value<int>? energy,
    Value<int>? mood,
    Value<String?>? notes,
    Value<String?>? period,
    Value<int>? loggedAt,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return LocalWellbeingCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      energy: energy ?? this.energy,
      mood: mood ?? this.mood,
      notes: notes ?? this.notes,
      period: period ?? this.period,
      loggedAt: loggedAt ?? this.loggedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (energy.present) {
      map['energy'] = Variable<int>(energy.value);
    }
    if (mood.present) {
      map['mood'] = Variable<int>(mood.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (loggedAt.present) {
      map['logged_at'] = Variable<int>(loggedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalWellbeingCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('energy: $energy, ')
          ..write('mood: $mood, ')
          ..write('notes: $notes, ')
          ..write('period: $period, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPreferencesTable extends LocalPreferences
    with TableInfo<$LocalPreferencesTable, LocalPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, data, syncStatus];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPreference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPreference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalPreferencesTable createAlias(String alias) {
    return $LocalPreferencesTable(attachedDatabase, alias);
  }
}

class LocalPreference extends DataClass implements Insertable<LocalPreference> {
  final int id;
  final String data;
  final String syncStatus;
  const LocalPreference({
    required this.id,
    required this.data,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['data'] = Variable<String>(data);
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalPreferencesCompanion toCompanion(bool nullToAbsent) {
    return LocalPreferencesCompanion(
      id: Value(id),
      data: Value(data),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalPreference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPreference(
      id: serializer.fromJson<int>(json['id']),
      data: serializer.fromJson<String>(json['data']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'data': serializer.toJson<String>(data),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalPreference copyWith({int? id, String? data, String? syncStatus}) =>
      LocalPreference(
        id: id ?? this.id,
        data: data ?? this.data,
        syncStatus: syncStatus ?? this.syncStatus,
      );
  LocalPreference copyWithCompanion(LocalPreferencesCompanion data) {
    return LocalPreference(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreference(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data, syncStatus);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPreference &&
          other.id == this.id &&
          other.data == this.data &&
          other.syncStatus == this.syncStatus);
}

class LocalPreferencesCompanion extends UpdateCompanion<LocalPreference> {
  final Value<int> id;
  final Value<String> data;
  final Value<String> syncStatus;
  const LocalPreferencesCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.syncStatus = const Value.absent(),
  });
  LocalPreferencesCompanion.insert({
    this.id = const Value.absent(),
    required String data,
    this.syncStatus = const Value.absent(),
  }) : data = Value(data);
  static Insertable<LocalPreference> custom({
    Expression<int>? id,
    Expression<String>? data,
    Expression<String>? syncStatus,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (syncStatus != null) 'sync_status': syncStatus,
    });
  }

  LocalPreferencesCompanion copyWith({
    Value<int>? id,
    Value<String>? data,
    Value<String>? syncStatus,
  }) {
    return LocalPreferencesCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreferencesCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }
}

class $LocalTrendsCacheTable extends LocalTrendsCache
    with TableInfo<$LocalTrendsCacheTable, LocalTrendsCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTrendsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, data, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_trends_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTrendsCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTrendsCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTrendsCacheData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $LocalTrendsCacheTable createAlias(String alias) {
    return $LocalTrendsCacheTable(attachedDatabase, alias);
  }
}

class LocalTrendsCacheData extends DataClass
    implements Insertable<LocalTrendsCacheData> {
  final int id;
  final String data;
  final int cachedAt;
  const LocalTrendsCacheData({
    required this.id,
    required this.data,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['data'] = Variable<String>(data);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  LocalTrendsCacheCompanion toCompanion(bool nullToAbsent) {
    return LocalTrendsCacheCompanion(
      id: Value(id),
      data: Value(data),
      cachedAt: Value(cachedAt),
    );
  }

  factory LocalTrendsCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTrendsCacheData(
      id: serializer.fromJson<int>(json['id']),
      data: serializer.fromJson<String>(json['data']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'data': serializer.toJson<String>(data),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  LocalTrendsCacheData copyWith({int? id, String? data, int? cachedAt}) =>
      LocalTrendsCacheData(
        id: id ?? this.id,
        data: data ?? this.data,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  LocalTrendsCacheData copyWithCompanion(LocalTrendsCacheCompanion data) {
    return LocalTrendsCacheData(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTrendsCacheData(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTrendsCacheData &&
          other.id == this.id &&
          other.data == this.data &&
          other.cachedAt == this.cachedAt);
}

class LocalTrendsCacheCompanion extends UpdateCompanion<LocalTrendsCacheData> {
  final Value<int> id;
  final Value<String> data;
  final Value<int> cachedAt;
  const LocalTrendsCacheCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.cachedAt = const Value.absent(),
  });
  LocalTrendsCacheCompanion.insert({
    this.id = const Value.absent(),
    required String data,
    required int cachedAt,
  }) : data = Value(data),
       cachedAt = Value(cachedAt);
  static Insertable<LocalTrendsCacheData> custom({
    Expression<int>? id,
    Expression<String>? data,
    Expression<int>? cachedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (cachedAt != null) 'cached_at': cachedAt,
    });
  }

  LocalTrendsCacheCompanion copyWith({
    Value<int>? id,
    Value<String>? data,
    Value<int>? cachedAt,
  }) {
    return LocalTrendsCacheCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTrendsCacheCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }
}

class $LocalVoiceQueueTable extends LocalVoiceQueue
    with TableInfo<$LocalVoiceQueueTable, LocalVoiceQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalVoiceQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transcriptMeta = const VerificationMeta(
    'transcript',
  );
  @override
  late final GeneratedColumn<String> transcript = GeneratedColumn<String>(
    'transcript',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loggedAtMeta = const VerificationMeta(
    'loggedAt',
  );
  @override
  late final GeneratedColumn<int> loggedAt = GeneratedColumn<int>(
    'logged_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, transcript, loggedAt, syncStatus];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_voice_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalVoiceQueueData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('transcript')) {
      context.handle(
        _transcriptMeta,
        transcript.isAcceptableOrUnknown(data['transcript']!, _transcriptMeta),
      );
    } else if (isInserting) {
      context.missing(_transcriptMeta);
    }
    if (data.containsKey('logged_at')) {
      context.handle(
        _loggedAtMeta,
        loggedAt.isAcceptableOrUnknown(data['logged_at']!, _loggedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_loggedAtMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalVoiceQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalVoiceQueueData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      transcript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transcript'],
      )!,
      loggedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logged_at'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalVoiceQueueTable createAlias(String alias) {
    return $LocalVoiceQueueTable(attachedDatabase, alias);
  }
}

class LocalVoiceQueueData extends DataClass
    implements Insertable<LocalVoiceQueueData> {
  final String id;
  final String transcript;
  final int loggedAt;
  final String syncStatus;
  const LocalVoiceQueueData({
    required this.id,
    required this.transcript,
    required this.loggedAt,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['transcript'] = Variable<String>(transcript);
    map['logged_at'] = Variable<int>(loggedAt);
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalVoiceQueueCompanion toCompanion(bool nullToAbsent) {
    return LocalVoiceQueueCompanion(
      id: Value(id),
      transcript: Value(transcript),
      loggedAt: Value(loggedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalVoiceQueueData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalVoiceQueueData(
      id: serializer.fromJson<String>(json['id']),
      transcript: serializer.fromJson<String>(json['transcript']),
      loggedAt: serializer.fromJson<int>(json['loggedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'transcript': serializer.toJson<String>(transcript),
      'loggedAt': serializer.toJson<int>(loggedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalVoiceQueueData copyWith({
    String? id,
    String? transcript,
    int? loggedAt,
    String? syncStatus,
  }) => LocalVoiceQueueData(
    id: id ?? this.id,
    transcript: transcript ?? this.transcript,
    loggedAt: loggedAt ?? this.loggedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  LocalVoiceQueueData copyWithCompanion(LocalVoiceQueueCompanion data) {
    return LocalVoiceQueueData(
      id: data.id.present ? data.id.value : this.id,
      transcript: data.transcript.present
          ? data.transcript.value
          : this.transcript,
      loggedAt: data.loggedAt.present ? data.loggedAt.value : this.loggedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalVoiceQueueData(')
          ..write('id: $id, ')
          ..write('transcript: $transcript, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, transcript, loggedAt, syncStatus);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalVoiceQueueData &&
          other.id == this.id &&
          other.transcript == this.transcript &&
          other.loggedAt == this.loggedAt &&
          other.syncStatus == this.syncStatus);
}

class LocalVoiceQueueCompanion extends UpdateCompanion<LocalVoiceQueueData> {
  final Value<String> id;
  final Value<String> transcript;
  final Value<int> loggedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalVoiceQueueCompanion({
    this.id = const Value.absent(),
    this.transcript = const Value.absent(),
    this.loggedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalVoiceQueueCompanion.insert({
    required String id,
    required String transcript,
    required int loggedAt,
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       transcript = Value(transcript),
       loggedAt = Value(loggedAt);
  static Insertable<LocalVoiceQueueData> custom({
    Expression<String>? id,
    Expression<String>? transcript,
    Expression<int>? loggedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transcript != null) 'transcript': transcript,
      if (loggedAt != null) 'logged_at': loggedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalVoiceQueueCompanion copyWith({
    Value<String>? id,
    Value<String>? transcript,
    Value<int>? loggedAt,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return LocalVoiceQueueCompanion(
      id: id ?? this.id,
      transcript: transcript ?? this.transcript,
      loggedAt: loggedAt ?? this.loggedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (transcript.present) {
      map['transcript'] = Variable<String>(transcript.value);
    }
    if (loggedAt.present) {
      map['logged_at'] = Variable<int>(loggedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalVoiceQueueCompanion(')
          ..write('id: $id, ')
          ..write('transcript: $transcript, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$OfflineDatabase extends GeneratedDatabase {
  _$OfflineDatabase(QueryExecutor e) : super(e);
  $OfflineDatabaseManager get managers => $OfflineDatabaseManager(this);
  late final $LocalMealsTable localMeals = $LocalMealsTable(this);
  late final $LocalSymptomsTable localSymptoms = $LocalSymptomsTable(this);
  late final $LocalWellbeingTable localWellbeing = $LocalWellbeingTable(this);
  late final $LocalPreferencesTable localPreferences = $LocalPreferencesTable(
    this,
  );
  late final $LocalTrendsCacheTable localTrendsCache = $LocalTrendsCacheTable(
    this,
  );
  late final $LocalVoiceQueueTable localVoiceQueue = $LocalVoiceQueueTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localMeals,
    localSymptoms,
    localWellbeing,
    localPreferences,
    localTrendsCache,
    localVoiceQueue,
  ];
}

typedef $$LocalMealsTableCreateCompanionBuilder =
    LocalMealsCompanion Function({
      required String id,
      Value<String?> serverId,
      required String description,
      required String mealType,
      required String foods,
      required int loggedAt,
      Value<String?> claudeNote,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$LocalMealsTableUpdateCompanionBuilder =
    LocalMealsCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String> description,
      Value<String> mealType,
      Value<String> foods,
      Value<int> loggedAt,
      Value<String?> claudeNote,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$LocalMealsTableFilterComposer
    extends Composer<_$OfflineDatabase, $LocalMealsTable> {
  $$LocalMealsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get foods => $composableBuilder(
    column: $table.foods,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get claudeNote => $composableBuilder(
    column: $table.claudeNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMealsTableOrderingComposer
    extends Composer<_$OfflineDatabase, $LocalMealsTable> {
  $$LocalMealsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foods => $composableBuilder(
    column: $table.foods,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get claudeNote => $composableBuilder(
    column: $table.claudeNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMealsTableAnnotationComposer
    extends Composer<_$OfflineDatabase, $LocalMealsTable> {
  $$LocalMealsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mealType =>
      $composableBuilder(column: $table.mealType, builder: (column) => column);

  GeneratedColumn<String> get foods =>
      $composableBuilder(column: $table.foods, builder: (column) => column);

  GeneratedColumn<int> get loggedAt =>
      $composableBuilder(column: $table.loggedAt, builder: (column) => column);

  GeneratedColumn<String> get claudeNote => $composableBuilder(
    column: $table.claudeNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalMealsTableTableManager
    extends
        RootTableManager<
          _$OfflineDatabase,
          $LocalMealsTable,
          LocalMeal,
          $$LocalMealsTableFilterComposer,
          $$LocalMealsTableOrderingComposer,
          $$LocalMealsTableAnnotationComposer,
          $$LocalMealsTableCreateCompanionBuilder,
          $$LocalMealsTableUpdateCompanionBuilder,
          (
            LocalMeal,
            BaseReferences<_$OfflineDatabase, $LocalMealsTable, LocalMeal>,
          ),
          LocalMeal,
          PrefetchHooks Function()
        > {
  $$LocalMealsTableTableManager(_$OfflineDatabase db, $LocalMealsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMealsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMealsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMealsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> mealType = const Value.absent(),
                Value<String> foods = const Value.absent(),
                Value<int> loggedAt = const Value.absent(),
                Value<String?> claudeNote = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMealsCompanion(
                id: id,
                serverId: serverId,
                description: description,
                mealType: mealType,
                foods: foods,
                loggedAt: loggedAt,
                claudeNote: claudeNote,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                required String description,
                required String mealType,
                required String foods,
                required int loggedAt,
                Value<String?> claudeNote = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMealsCompanion.insert(
                id: id,
                serverId: serverId,
                description: description,
                mealType: mealType,
                foods: foods,
                loggedAt: loggedAt,
                claudeNote: claudeNote,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMealsTableProcessedTableManager =
    ProcessedTableManager<
      _$OfflineDatabase,
      $LocalMealsTable,
      LocalMeal,
      $$LocalMealsTableFilterComposer,
      $$LocalMealsTableOrderingComposer,
      $$LocalMealsTableAnnotationComposer,
      $$LocalMealsTableCreateCompanionBuilder,
      $$LocalMealsTableUpdateCompanionBuilder,
      (
        LocalMeal,
        BaseReferences<_$OfflineDatabase, $LocalMealsTable, LocalMeal>,
      ),
      LocalMeal,
      PrefetchHooks Function()
    >;
typedef $$LocalSymptomsTableCreateCompanionBuilder =
    LocalSymptomsCompanion Function({
      required String id,
      Value<String?> serverId,
      required String description,
      Value<int> severity,
      Value<String?> linkedMealId,
      required int loggedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$LocalSymptomsTableUpdateCompanionBuilder =
    LocalSymptomsCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<String> description,
      Value<int> severity,
      Value<String?> linkedMealId,
      Value<int> loggedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$LocalSymptomsTableFilterComposer
    extends Composer<_$OfflineDatabase, $LocalSymptomsTable> {
  $$LocalSymptomsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkedMealId => $composableBuilder(
    column: $table.linkedMealId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSymptomsTableOrderingComposer
    extends Composer<_$OfflineDatabase, $LocalSymptomsTable> {
  $$LocalSymptomsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkedMealId => $composableBuilder(
    column: $table.linkedMealId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSymptomsTableAnnotationComposer
    extends Composer<_$OfflineDatabase, $LocalSymptomsTable> {
  $$LocalSymptomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<String> get linkedMealId => $composableBuilder(
    column: $table.linkedMealId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get loggedAt =>
      $composableBuilder(column: $table.loggedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalSymptomsTableTableManager
    extends
        RootTableManager<
          _$OfflineDatabase,
          $LocalSymptomsTable,
          LocalSymptom,
          $$LocalSymptomsTableFilterComposer,
          $$LocalSymptomsTableOrderingComposer,
          $$LocalSymptomsTableAnnotationComposer,
          $$LocalSymptomsTableCreateCompanionBuilder,
          $$LocalSymptomsTableUpdateCompanionBuilder,
          (
            LocalSymptom,
            BaseReferences<
              _$OfflineDatabase,
              $LocalSymptomsTable,
              LocalSymptom
            >,
          ),
          LocalSymptom,
          PrefetchHooks Function()
        > {
  $$LocalSymptomsTableTableManager(
    _$OfflineDatabase db,
    $LocalSymptomsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSymptomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSymptomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSymptomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> severity = const Value.absent(),
                Value<String?> linkedMealId = const Value.absent(),
                Value<int> loggedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSymptomsCompanion(
                id: id,
                serverId: serverId,
                description: description,
                severity: severity,
                linkedMealId: linkedMealId,
                loggedAt: loggedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                required String description,
                Value<int> severity = const Value.absent(),
                Value<String?> linkedMealId = const Value.absent(),
                required int loggedAt,
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSymptomsCompanion.insert(
                id: id,
                serverId: serverId,
                description: description,
                severity: severity,
                linkedMealId: linkedMealId,
                loggedAt: loggedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSymptomsTableProcessedTableManager =
    ProcessedTableManager<
      _$OfflineDatabase,
      $LocalSymptomsTable,
      LocalSymptom,
      $$LocalSymptomsTableFilterComposer,
      $$LocalSymptomsTableOrderingComposer,
      $$LocalSymptomsTableAnnotationComposer,
      $$LocalSymptomsTableCreateCompanionBuilder,
      $$LocalSymptomsTableUpdateCompanionBuilder,
      (
        LocalSymptom,
        BaseReferences<_$OfflineDatabase, $LocalSymptomsTable, LocalSymptom>,
      ),
      LocalSymptom,
      PrefetchHooks Function()
    >;
typedef $$LocalWellbeingTableCreateCompanionBuilder =
    LocalWellbeingCompanion Function({
      required String id,
      Value<String?> serverId,
      Value<int> energy,
      Value<int> mood,
      Value<String?> notes,
      Value<String?> period,
      required int loggedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$LocalWellbeingTableUpdateCompanionBuilder =
    LocalWellbeingCompanion Function({
      Value<String> id,
      Value<String?> serverId,
      Value<int> energy,
      Value<int> mood,
      Value<String?> notes,
      Value<String?> period,
      Value<int> loggedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$LocalWellbeingTableFilterComposer
    extends Composer<_$OfflineDatabase, $LocalWellbeingTable> {
  $$LocalWellbeingTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get energy => $composableBuilder(
    column: $table.energy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalWellbeingTableOrderingComposer
    extends Composer<_$OfflineDatabase, $LocalWellbeingTable> {
  $$LocalWellbeingTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get energy => $composableBuilder(
    column: $table.energy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalWellbeingTableAnnotationComposer
    extends Composer<_$OfflineDatabase, $LocalWellbeingTable> {
  $$LocalWellbeingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get energy =>
      $composableBuilder(column: $table.energy, builder: (column) => column);

  GeneratedColumn<int> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<int> get loggedAt =>
      $composableBuilder(column: $table.loggedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalWellbeingTableTableManager
    extends
        RootTableManager<
          _$OfflineDatabase,
          $LocalWellbeingTable,
          LocalWellbeingData,
          $$LocalWellbeingTableFilterComposer,
          $$LocalWellbeingTableOrderingComposer,
          $$LocalWellbeingTableAnnotationComposer,
          $$LocalWellbeingTableCreateCompanionBuilder,
          $$LocalWellbeingTableUpdateCompanionBuilder,
          (
            LocalWellbeingData,
            BaseReferences<
              _$OfflineDatabase,
              $LocalWellbeingTable,
              LocalWellbeingData
            >,
          ),
          LocalWellbeingData,
          PrefetchHooks Function()
        > {
  $$LocalWellbeingTableTableManager(
    _$OfflineDatabase db,
    $LocalWellbeingTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalWellbeingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalWellbeingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalWellbeingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<int> energy = const Value.absent(),
                Value<int> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> period = const Value.absent(),
                Value<int> loggedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalWellbeingCompanion(
                id: id,
                serverId: serverId,
                energy: energy,
                mood: mood,
                notes: notes,
                period: period,
                loggedAt: loggedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> serverId = const Value.absent(),
                Value<int> energy = const Value.absent(),
                Value<int> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> period = const Value.absent(),
                required int loggedAt,
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalWellbeingCompanion.insert(
                id: id,
                serverId: serverId,
                energy: energy,
                mood: mood,
                notes: notes,
                period: period,
                loggedAt: loggedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalWellbeingTableProcessedTableManager =
    ProcessedTableManager<
      _$OfflineDatabase,
      $LocalWellbeingTable,
      LocalWellbeingData,
      $$LocalWellbeingTableFilterComposer,
      $$LocalWellbeingTableOrderingComposer,
      $$LocalWellbeingTableAnnotationComposer,
      $$LocalWellbeingTableCreateCompanionBuilder,
      $$LocalWellbeingTableUpdateCompanionBuilder,
      (
        LocalWellbeingData,
        BaseReferences<
          _$OfflineDatabase,
          $LocalWellbeingTable,
          LocalWellbeingData
        >,
      ),
      LocalWellbeingData,
      PrefetchHooks Function()
    >;
typedef $$LocalPreferencesTableCreateCompanionBuilder =
    LocalPreferencesCompanion Function({
      Value<int> id,
      required String data,
      Value<String> syncStatus,
    });
typedef $$LocalPreferencesTableUpdateCompanionBuilder =
    LocalPreferencesCompanion Function({
      Value<int> id,
      Value<String> data,
      Value<String> syncStatus,
    });

class $$LocalPreferencesTableFilterComposer
    extends Composer<_$OfflineDatabase, $LocalPreferencesTable> {
  $$LocalPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPreferencesTableOrderingComposer
    extends Composer<_$OfflineDatabase, $LocalPreferencesTable> {
  $$LocalPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPreferencesTableAnnotationComposer
    extends Composer<_$OfflineDatabase, $LocalPreferencesTable> {
  $$LocalPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalPreferencesTableTableManager
    extends
        RootTableManager<
          _$OfflineDatabase,
          $LocalPreferencesTable,
          LocalPreference,
          $$LocalPreferencesTableFilterComposer,
          $$LocalPreferencesTableOrderingComposer,
          $$LocalPreferencesTableAnnotationComposer,
          $$LocalPreferencesTableCreateCompanionBuilder,
          $$LocalPreferencesTableUpdateCompanionBuilder,
          (
            LocalPreference,
            BaseReferences<
              _$OfflineDatabase,
              $LocalPreferencesTable,
              LocalPreference
            >,
          ),
          LocalPreference,
          PrefetchHooks Function()
        > {
  $$LocalPreferencesTableTableManager(
    _$OfflineDatabase db,
    $LocalPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
              }) => LocalPreferencesCompanion(
                id: id,
                data: data,
                syncStatus: syncStatus,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String data,
                Value<String> syncStatus = const Value.absent(),
              }) => LocalPreferencesCompanion.insert(
                id: id,
                data: data,
                syncStatus: syncStatus,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$OfflineDatabase,
      $LocalPreferencesTable,
      LocalPreference,
      $$LocalPreferencesTableFilterComposer,
      $$LocalPreferencesTableOrderingComposer,
      $$LocalPreferencesTableAnnotationComposer,
      $$LocalPreferencesTableCreateCompanionBuilder,
      $$LocalPreferencesTableUpdateCompanionBuilder,
      (
        LocalPreference,
        BaseReferences<
          _$OfflineDatabase,
          $LocalPreferencesTable,
          LocalPreference
        >,
      ),
      LocalPreference,
      PrefetchHooks Function()
    >;
typedef $$LocalTrendsCacheTableCreateCompanionBuilder =
    LocalTrendsCacheCompanion Function({
      Value<int> id,
      required String data,
      required int cachedAt,
    });
typedef $$LocalTrendsCacheTableUpdateCompanionBuilder =
    LocalTrendsCacheCompanion Function({
      Value<int> id,
      Value<String> data,
      Value<int> cachedAt,
    });

class $$LocalTrendsCacheTableFilterComposer
    extends Composer<_$OfflineDatabase, $LocalTrendsCacheTable> {
  $$LocalTrendsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTrendsCacheTableOrderingComposer
    extends Composer<_$OfflineDatabase, $LocalTrendsCacheTable> {
  $$LocalTrendsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTrendsCacheTableAnnotationComposer
    extends Composer<_$OfflineDatabase, $LocalTrendsCacheTable> {
  $$LocalTrendsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$LocalTrendsCacheTableTableManager
    extends
        RootTableManager<
          _$OfflineDatabase,
          $LocalTrendsCacheTable,
          LocalTrendsCacheData,
          $$LocalTrendsCacheTableFilterComposer,
          $$LocalTrendsCacheTableOrderingComposer,
          $$LocalTrendsCacheTableAnnotationComposer,
          $$LocalTrendsCacheTableCreateCompanionBuilder,
          $$LocalTrendsCacheTableUpdateCompanionBuilder,
          (
            LocalTrendsCacheData,
            BaseReferences<
              _$OfflineDatabase,
              $LocalTrendsCacheTable,
              LocalTrendsCacheData
            >,
          ),
          LocalTrendsCacheData,
          PrefetchHooks Function()
        > {
  $$LocalTrendsCacheTableTableManager(
    _$OfflineDatabase db,
    $LocalTrendsCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTrendsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTrendsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTrendsCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<int> cachedAt = const Value.absent(),
              }) => LocalTrendsCacheCompanion(
                id: id,
                data: data,
                cachedAt: cachedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String data,
                required int cachedAt,
              }) => LocalTrendsCacheCompanion.insert(
                id: id,
                data: data,
                cachedAt: cachedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTrendsCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$OfflineDatabase,
      $LocalTrendsCacheTable,
      LocalTrendsCacheData,
      $$LocalTrendsCacheTableFilterComposer,
      $$LocalTrendsCacheTableOrderingComposer,
      $$LocalTrendsCacheTableAnnotationComposer,
      $$LocalTrendsCacheTableCreateCompanionBuilder,
      $$LocalTrendsCacheTableUpdateCompanionBuilder,
      (
        LocalTrendsCacheData,
        BaseReferences<
          _$OfflineDatabase,
          $LocalTrendsCacheTable,
          LocalTrendsCacheData
        >,
      ),
      LocalTrendsCacheData,
      PrefetchHooks Function()
    >;
typedef $$LocalVoiceQueueTableCreateCompanionBuilder =
    LocalVoiceQueueCompanion Function({
      required String id,
      required String transcript,
      required int loggedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$LocalVoiceQueueTableUpdateCompanionBuilder =
    LocalVoiceQueueCompanion Function({
      Value<String> id,
      Value<String> transcript,
      Value<int> loggedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$LocalVoiceQueueTableFilterComposer
    extends Composer<_$OfflineDatabase, $LocalVoiceQueueTable> {
  $$LocalVoiceQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalVoiceQueueTableOrderingComposer
    extends Composer<_$OfflineDatabase, $LocalVoiceQueueTable> {
  $$LocalVoiceQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalVoiceQueueTableAnnotationComposer
    extends Composer<_$OfflineDatabase, $LocalVoiceQueueTable> {
  $$LocalVoiceQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => column,
  );

  GeneratedColumn<int> get loggedAt =>
      $composableBuilder(column: $table.loggedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalVoiceQueueTableTableManager
    extends
        RootTableManager<
          _$OfflineDatabase,
          $LocalVoiceQueueTable,
          LocalVoiceQueueData,
          $$LocalVoiceQueueTableFilterComposer,
          $$LocalVoiceQueueTableOrderingComposer,
          $$LocalVoiceQueueTableAnnotationComposer,
          $$LocalVoiceQueueTableCreateCompanionBuilder,
          $$LocalVoiceQueueTableUpdateCompanionBuilder,
          (
            LocalVoiceQueueData,
            BaseReferences<
              _$OfflineDatabase,
              $LocalVoiceQueueTable,
              LocalVoiceQueueData
            >,
          ),
          LocalVoiceQueueData,
          PrefetchHooks Function()
        > {
  $$LocalVoiceQueueTableTableManager(
    _$OfflineDatabase db,
    $LocalVoiceQueueTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalVoiceQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalVoiceQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalVoiceQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> transcript = const Value.absent(),
                Value<int> loggedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalVoiceQueueCompanion(
                id: id,
                transcript: transcript,
                loggedAt: loggedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String transcript,
                required int loggedAt,
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalVoiceQueueCompanion.insert(
                id: id,
                transcript: transcript,
                loggedAt: loggedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalVoiceQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$OfflineDatabase,
      $LocalVoiceQueueTable,
      LocalVoiceQueueData,
      $$LocalVoiceQueueTableFilterComposer,
      $$LocalVoiceQueueTableOrderingComposer,
      $$LocalVoiceQueueTableAnnotationComposer,
      $$LocalVoiceQueueTableCreateCompanionBuilder,
      $$LocalVoiceQueueTableUpdateCompanionBuilder,
      (
        LocalVoiceQueueData,
        BaseReferences<
          _$OfflineDatabase,
          $LocalVoiceQueueTable,
          LocalVoiceQueueData
        >,
      ),
      LocalVoiceQueueData,
      PrefetchHooks Function()
    >;

class $OfflineDatabaseManager {
  final _$OfflineDatabase _db;
  $OfflineDatabaseManager(this._db);
  $$LocalMealsTableTableManager get localMeals =>
      $$LocalMealsTableTableManager(_db, _db.localMeals);
  $$LocalSymptomsTableTableManager get localSymptoms =>
      $$LocalSymptomsTableTableManager(_db, _db.localSymptoms);
  $$LocalWellbeingTableTableManager get localWellbeing =>
      $$LocalWellbeingTableTableManager(_db, _db.localWellbeing);
  $$LocalPreferencesTableTableManager get localPreferences =>
      $$LocalPreferencesTableTableManager(_db, _db.localPreferences);
  $$LocalTrendsCacheTableTableManager get localTrendsCache =>
      $$LocalTrendsCacheTableTableManager(_db, _db.localTrendsCache);
  $$LocalVoiceQueueTableTableManager get localVoiceQueue =>
      $$LocalVoiceQueueTableTableManager(_db, _db.localVoiceQueue);
}
