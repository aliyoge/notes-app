import 'dart:io';

import 'dart:async';
import 'package:notes_app/db_helper/local_db_helper.dart';
import 'package:notes_app/utils/keys.dart';
import 'package:notes_app/modal_class/notes.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static DatabaseHelper _databaseHelper; // Singleton DatabaseHelper
  static PostgreSQLConnection _database; // Singleton PostgreSQLConnection

  bool _local;

  String noteTable = 'note_table';
  String colId = 'id';
  String colTitle = 'title';
  String colDescription = 'description';
  String colPriority = 'priority';
  String colColor = 'color';
  String colDate = 'date';

  DatabaseHelper._createInstance(); // Named constructor to create instance of DatabaseHelper

  factory DatabaseHelper() {
    if (_databaseHelper == null) {
      _databaseHelper = DatabaseHelper
          ._createInstance(); // This is executed only once, singleton object
    }
    return _databaseHelper;
  }

  clear() {
    _local = null;
    _database = null;
  }

  Future<PostgreSQLConnection> get database async {
    if (_local != null && _local) return null;
    if (_database != null) return _database;
    _database = await initializeDatabase();
    return _database;
  }

  Future<PostgreSQLConnection> initializeDatabase() async {
    _local = true;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    var dbAddr = prefs.getString(Keys.dbAddr);
    String dbIp, dbName, dbAccount, dbPasswd;
    int dbPort;
    if (dbAddr != null && dbAddr != '') {
      var a = dbAddr.split(':');
      if (a == null || a.length < 2) {
        return null;
      }
      dbIp = a[0];
      dbPort = int.parse(a[1]);
      dbName = prefs.getString(Keys.dbName);
      dbAccount = prefs.getString(Keys.dbAccount);
      dbPasswd = prefs.getString(Keys.dbPasswd);
      _local = false;
    }

    if (_local) {
      return null;
    }

    var connection = PostgreSQLConnection(dbIp, dbPort, dbName,
        username: dbAccount, password: dbPasswd);
    await connection.open();

    try {
      await connection.execute("""
        CREATE TABLE $noteTable (
                  $colId SERIAL PRIMARY KEY,
                  $colTitle TEXT,
                  $colDescription TEXT,
                  $colPriority INTEGER,
                  $colColor INTEGER,
                  $colDate TEXT);
        """);
    } catch (e) {
      print(e);
    }

    return connection;
  }

  // Fetch Operation: Get all note objects from database
  Future<List<Map<String, dynamic>>> getNoteMapList() async {
    PostgreSQLConnection db = await this.database;
    if (db == null) return LocalDbHelper().getNoteMapList();

    var list = await db.mappedResultsQuery(
        'SELECT * FROM $noteTable order by $colPriority ASC');
    var mapList = list.map((e) => e[noteTable]).toList();
    return mapList;
  }

  // Insert Operation: Insert a Note object to database
  Future<int> insertNote(Note note) async {
    PostgreSQLConnection db = await this.database;
    if (db == null) return LocalDbHelper().insertNote(note);

    var sql = getInsertSql(noteTable, note.toMap());
    var res = await db.execute(sql, substitutionValues: note.toMap());
    return res;
  }

  // Update Operation: Update a Note object and save it to database
  Future<int> updateNote(Note note) async {
    if (note == null) return null;
    var db = await this.database;
    if (db == null) return await LocalDbHelper().updateNote(note);

    var sql = getUpdateSql(
        noteTable,
        note.toMap(),
        'WHERE $colId = '
        '${note.id}');
    var res = await db.execute(sql, substitutionValues: note.toMap());
    return res;
  }

  // Delete Operation: Delete a Note object from database
  Future<int> deleteNote(int id) async {
    var db = await this.database;
    if (db == null) return await LocalDbHelper().deleteNote(id);

    int result = await db.execute('DELETE FROM $noteTable WHERE $colId = $id');
    return result;
  }

  // Get number of Note objects in database
  Future<int> getCount() async {
    PostgreSQLConnection db = await this.database;
    if (db == null) return LocalDbHelper().getCount();

    var res = await db.execute('SELECT COUNT (*) from $noteTable');
    return res;
  }

  // Get the 'Map List' [ List<Map> ] and convert it to 'Note List' [ List<Note> ]
  Future<List<Note>> getNoteList() async {
    var noteMapList = await getNoteMapList(); // Get 'Map List' from database
    int count =
        noteMapList.length; // Count the number of map entries in db table

    List<Note> noteList = [];
    // For loop to create a 'Note List' from a 'Map List'
    for (int i = 0; i < count; i++) {
      noteList.add(Note.fromMapObject(noteMapList[i]));
    }

    return noteList;
  }

  String getUpdateSql(
      String table, Map<String, dynamic> values, String whereStr) {
    final update = StringBuffer();
    update.write('UPDATE ');
    update.write(_escapeName(table));
    update.write(' SET ');

    final size = (values != null) ? values.length : 0;

    if (size > 0) {
      var i = 0;
      values.forEach((String colName, dynamic value) {
        if (i++ > 0) {
          update.write(', ');
        }

        /// This should be just a column name
        update
            .write('${_escapeName(colName)} = ${PostgreSQLFormat.id(colName)}');
      });
    }
    update.write(' ${whereStr}');

    var sql = update.toString();
    return sql;
  }

  String getInsertSql(String table, Map<String, dynamic> values) {
    final insert = StringBuffer();
    insert.write('INSERT');
    insert.write(' INTO ');
    insert.write(_escapeName(table));
    insert.write(' (');

    final size = (values != null) ? values.length : 0;

    if (size > 0) {
      final sbValues = StringBuffer(') VALUES (');

      var i = 0;
      values.forEach((String colName, dynamic value) {
        if (i++ > 0) {
          insert.write(', ');
          sbValues.write(', ');
        }

        /// This should be just a column name
        insert.write(_escapeName(colName));
        sbValues.write(PostgreSQLFormat.id(colName));
      });
      insert.write(sbValues);
    }
    insert.write(')');

    var sql = insert.toString();
    return sql;
  }

  String _escapeName(String name) {
    if (name == null) {
      return name;
    }
    if (escapeNames.contains(name.toLowerCase())) {
      return _doEscape(name);
    }
    return name;
  }

  String _doEscape(String name) => '"$name"';

  final Set<String> escapeNames = <String>{
    'add',
    'all',
    'alter',
    'and',
    'as',
    'autoincrement',
    'between',
    'case',
    'check',
    'collate',
    'commit',
    'constraint',
    'create',
    'default',
    'deferrable',
    'delete',
    'distinct',
    'drop',
    'else',
    'escape',
    'except',
    'exists',
    'foreign',
    'from',
    'group',
    'having',
    'if',
    'in',
    'index',
    'insert',
    'intersect',
    'into',
    'is',
    'isnull',
    'join',
    'limit',
    'not',
    'notnull',
    'null',
    'on',
    'or',
    'order',
    'primary',
    'references',
    'select',
    'set',
    'table',
    'then',
    'to',
    'transaction',
    'union',
    'unique',
    'update',
    'using',
    'values',
    'when',
    'where'
  };
}
