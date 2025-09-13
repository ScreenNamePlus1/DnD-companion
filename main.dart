// lib/main.dart
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Database Helper
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('dnd_enhanced.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE characters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        strength INTEGER,
        dexterity INTEGER,
        constitution INTEGER,
        intelligence INTEGER,
        wisdom INTEGER,
        charisma INTEGER,
        proficiency_bonus INTEGER,
        skill_proficiencies TEXT,
        max_hp INTEGER,
        current_hp INTEGER,
        temp_hp INTEGER,
        spell_slots TEXT,
        is_active INTEGER DEFAULT 0
      )
    ''');
    
    await db.execute('''
      CREATE TABLE roll_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER,
        roll_type TEXT,
        dice_notation TEXT,
        result INTEGER,
        details TEXT,
        timestamp INTEGER,
        FOREIGN KEY (character_id) REFERENCES characters (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE initiative_tracker (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        initiative_roll INTEGER,
        dex_modifier INTEGER,
        total_initiative INTEGER
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE characters ADD COLUMN max_hp INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE characters ADD COLUMN current_hp INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE characters ADD COLUMN temp_hp INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE characters ADD COLUMN spell_slots TEXT');
      await db.execute('ALTER TABLE characters ADD COLUMN is_active INTEGER DEFAULT 0');
    }
  }

  Future<void> insertOrUpdateCharacter(Map<String, dynamic> character) async {
    final db = await instance.database;
    final id = character['id'];
    if (id != null) {
      await db.update('characters', character, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert('characters', character);
    }
  }

  Future<List<Map<String, dynamic>>> getAllCharacters() async {
    final db = await instance.database;
    return await db.query('characters', orderBy: 'name');
  }

  Future<Map<String, dynamic>?> getActiveCharacter() async {
    final db = await instance.database;
    final result = await db.query('characters', where: 'is_active = 1', limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> setActiveCharacter(int characterId) async {
    final db = await instance.database;
    await db.update('characters', {'is_active': 0});
    await db.update('characters', {'is_active': 1}, where: 'id = ?', whereArgs: [characterId]);
  }

  Future<void> insertRollHistory(Map<String, dynamic> roll) async {
    final db = await instance.database;
    await db.insert('roll_history', roll);
    // Keep only last 50 rolls
    await db.delete('roll_history', where: 'id NOT IN (SELECT id FROM roll_history ORDER BY timestamp DESC LIMIT 50)');
  }

  Future<List<Map<String, dynamic>>> getRollHistory(int limit) async {
    final db = await instance.database;
    return await db.query('roll_history', orderBy: 'timestamp DESC', limit: limit);
  }
}

// Enhanced Character Model
class CharacterModel with ChangeNotifier {
  int? id;
  String name = 'New Character';
  int strength = 10;
  int dexterity = 10;
  int constitution = 10;
  int intelligence = 10;
  int wisdom = 10;
  int charisma = 10;
  int proficiencyBonus = 2;
  int maxHp = 0;
  int currentHp = 0;
  int tempHp = 0;
  
  Map<String, bool> skillProficiencies = {
    'Acrobatics': false,
    'Animal Handling': false,
    'Arcana': false,
    'Athletics': false,
    'Deception': false,
    'History': false,
    'Insight': false,
    'Intimidation': false,
    'Investigation': false,
    'Medicine': false,
    'Nature': false,
    'Perception': false,
    'Performance': false,
    'Persuasion': false,
    'Religion': false,
    'Sleight of Hand': false,
    'Stealth': false,
    'Survival': false,
  };

  Map<int, int> maxSpellSlots = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0, 9: 0};
  Map<int, int> usedSpellSlots = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0, 9: 0};

  static const Map<String, String> skillToAbility = {
    'Acrobatics': 'Dexterity',
    'Animal Handling': 'Wisdom',
    'Arcana': 'Intelligence',
    'Athletics': 'Strength',
    'Deception': 'Charisma',
    'History': 'Intelligence',
    'Insight': 'Wisdom',
    'Intimidation': 'Charisma',
    'Investigation': 'Intelligence',
    'Medicine': 'Wisdom',
    'Nature': 'Intelligence',
    'Perception': 'Wisdom',
    'Performance': 'Charisma',
    'Persuasion': 'Charisma',
    'Religion': 'Intelligence',
    'Sleight of Hand': 'Dexterity',
    'Stealth': 'Dexterity',
    'Survival': 'Wisdom',
  };

  int getModifier(int score) => (score - 10) ~/ 2;

  int getAbilityScore(String ability) {
    switch (ability) {
      case 'Strength': return strength;
      case 'Dexterity': return dexterity;
      case 'Constitution': return constitution;
      case 'Intelligence': return intelligence;
      case 'Wisdom': return wisdom;
      case 'Charisma': return charisma;
      default: return 10;
    }
  }

  int getAbilityModifier(String ability) => getModifier(getAbilityScore(ability));

  int getSkillModifier(String skill) {
    final ability = skillToAbility[skill] ?? 'Strength';
    final abilityMod = getAbilityModifier(ability);
    final profBonus = skillProficiencies[skill] == true ? proficiencyBonus : 0;
    return abilityMod + profBonus;
  }

  void updateFromMap(Map<String, dynamic> data) {
    id = data['id'];
    name = data['name'] ?? name;
    strength = data['strength'] ?? strength;
    dexterity = data['dexterity'] ?? dexterity;
    constitution = data['constitution'] ?? constitution;
    intelligence = data['intelligence'] ?? intelligence;
    wisdom = data['wisdom'] ?? wisdom;
    charisma = data['charisma'] ?? charisma;
    proficiencyBonus = data['proficiency_bonus'] ?? proficiencyBonus;
    maxHp = data['max_hp'] ?? maxHp;
    currentHp = data['current_hp'] ?? currentHp;
    tempHp = data['temp_hp'] ?? tempHp;
    
    if (data['skill_proficiencies'] != null) {
      try {
        final skillData = jsonDecode(data['skill_proficiencies']);
        if (skillData is Map) {
          skillProficiencies.addAll(Map<String, bool>.from(skillData));
        }
      } catch (e) {
        print('Error parsing skill proficiencies: $e');
      }
    }
    
    if (data['spell_slots'] != null) {
      try {
        final spellData = jsonDecode(data['spell_slots']);
        if (spellData is Map && spellData['max'] != null && spellData['used'] != null) {
          maxSpellSlots.addAll(Map<int, int>.from(spellData['max'].map((k, v) => MapEntry(int.parse(k.toString()), v))));
          usedSpellSlots.addAll(Map<int, int>.from(spellData['used'].map((k, v) => MapEntry(int.parse(k.toString()), v))));
        }
      } catch (e) {
        print('Error parsing spell slots: $e');
      }
    }
    
    notifyListeners();
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'strength': strength,
      'dexterity': dexterity,
      'constitution': constitution,
      'intelligence': intelligence,
      'wisdom': wisdom,
      'charisma': charisma,
      'proficiency_bonus': proficiencyBonus,
      'max_hp': maxHp,
      'current_hp': currentHp,
      'temp_hp': tempHp,
      'skill_proficiencies': jsonEncode(skillProficiencies),
      'spell_slots': jsonEncode({'max': maxSpellSlots, 'used': usedSpellSlots}),
      'is_active': 1,
    };
  }

  void updateStat(String stat, int value) {
    switch (stat) {
      case 'strength': strength = value; break;
      case 'dexterity': dexterity = value; break;
      case 'constitution': constitution = value; break;
      case 'intelligence': intelligence = value; break;
      case 'wisdom': wisdom = value; break;
      case 'charisma': charisma = value; break;
      case 'proficiency_bonus': proficiencyBonus = value; break;
      case 'max_hp': maxHp = value; break;
      case 'current_hp': currentHp = value; break;
      case 'temp_hp': tempHp = value; break;
    }
    notifyListeners();
  }

  void toggleProficiency(String skill) {
    skillProficiencies[skill] = !skillProficiencies[skill]!;
    notifyListeners();
  }

  void useSpellSlot(int level) {
    if (usedSpellSlots[level]! < maxSpellSlots[level]!) {
      usedSpellSlots[level] = usedSpellSlots[level]! + 1;
      notifyListeners();
    }
  }

  void restoreSpellSlot(int level) {
    if (usedSpellSlots[level]! > 0) {
      usedSpellSlots[level] = usedSpellSlots[level]! - 1;
      notifyListeners();
    }
  }

  void longRest() {
    currentHp = maxHp;
    tempHp = 0;
    usedSpellSlots.updateAll((key, value) => 0);
    notifyListeners();
  }
}

// Enhanced Dice Roller Model
class DiceRollerModel with ChangeNotifier {
  List<int> _results = [];
  int _total = 0;
  int _numDice = 1;
  int _diceSides = 20;
  bool _isRolling = false;
  String _rollType = 'Ability Check';
  String _ability = 'Strength';
  String _skill = '';
  bool _isProficient = false;
  String _advantage = 'Normal';
  int _extraBonus = 0;
  List<Map<String, dynamic>> _rollHistory = [];

  // Getters
  List<int> get results => _results;
  int get total => _total;
  int get numDice => _numDice;
  int get diceSides => _diceSides;
  bool get isRolling => _isRolling;
  String get rollType => _rollType;
  String get ability => _ability;
  String get skill => _skill;
  bool get isProficient => _isProficient;
  String get advantage => _advantage;
  int get extraBonus => _extraBonus;
  List<Map<String, dynamic>> get rollHistory => _rollHistory;

  // Roll types that don't use ability modifiers
  static const List<String> rollTypesWithoutMods = [
    'Death Saving Throw',
    'Spell Damage',
    'Raw Dice'
  ];

  void setNumDice(int value) {
    _numDice = value;
    notifyListeners();
  }

  void setDiceSides(int value) {
    _diceSides = value;
    notifyListeners();
  }

  void setRollType(String type) {
    _rollType = type;
    if (type == 'Skill Check' && _skill.isEmpty) {
      _skill = 'Athletics';
    }
    notifyListeners();
  }

  void setAbility(String ability) {
    _ability = ability;
    notifyListeners();
  }

  void setSkill(String skill) {
    _skill = skill;
    _ability = CharacterModel.skillToAbility[skill] ?? 'Strength';
    notifyListeners();
  }

  void setProficient(bool value) {
    _isProficient = value;
    notifyListeners();
  }

  void setAdvantage(String value) {
    _advantage = value;
    notifyListeners();
  }

  void setExtraBonus(int value) {
    _extraBonus = value;
    notifyListeners();
  }

  Future<void> rollDice(CharacterModel? character) async {
    _isRolling = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800));

    // Roll the dice
    List<int> allRolls = [];
    int finalResult = 0;
    bool isCritical = false;
    bool isCriticalFailure = false;

    if (_diceSides == 20 && (_advantage != 'Normal')) {
      // Advantage/Disadvantage: roll twice
      int roll1 = Random().nextInt(20) + 1;
      int roll2 = Random().nextInt(20) + 1;
      allRolls = [roll1, roll2];
      
      if (_advantage == 'Advantage') {
        finalResult = max(roll1, roll2);
      } else {
        finalResult = min(roll1, roll2);
      }
    } else {
      // Normal roll or non-d20
      for (int i = 0; i < _numDice; i++) {
        allRolls.add(Random().nextInt(_diceSides) + 1);
      }
      finalResult = allRolls.reduce((a, b) => a + b);
    }

    // Check for natural 20/1 on d20 rolls
    if (_diceSides == 20 && _numDice == 1) {
      isCritical = finalResult == 20;
      isCriticalFailure = finalResult == 1;
    }

    // Apply modifiers based on roll type
    int totalModifiers = 0;
    String modifierBreakdown = '';

    if (!rollTypesWithoutMods.contains(_rollType) && character != null) {
      // Ability modifier
      int abilityMod = 0;
      if (_rollType == 'Skill Check' && _skill.isNotEmpty) {
        abilityMod = character.getSkillModifier(_skill);
        totalModifiers += abilityMod;
        final skillAbility = CharacterModel.skillToAbility[_skill] ?? 'Strength';
        final abilityOnlyMod = character.getAbilityModifier(skillAbility);
        final profBonus = character.skillProficiencies[_skill] == true ? character.proficiencyBonus : 0;
        modifierBreakdown = '$skillAbility ${abilityOnlyMod >= 0 ? '+' : ''}$abilityOnlyMod';
        if (profBonus > 0) {
          modifierBreakdown += ' + Prof +$profBonus';
        }
      } else {
        abilityMod = character.getAbilityModifier(_ability);
        totalModifiers += abilityMod;
        modifierBreakdown = '$_ability ${abilityMod >= 0 ? '+' : ''}$abilityMod';
        
        // Proficiency bonus (if applicable)
        if (_isProficient && _rollType != 'Initiative Roll') {
          totalModifiers += character.proficiencyBonus;
          modifierBreakdown += ' + Prof +${character.proficiencyBonus}';
        }
      }
    }

    // Extra bonus
    if (_extraBonus != 0) {
      totalModifiers += _extraBonus;
      modifierBreakdown += ' + Extra ${_extraBonus >= 0 ? '+' : ''}$_extraBonus';
    }

    _results = allRolls;
    _total = finalResult + totalModifiers;

    // Create roll history entry
    final rollEntry = {
      'type': _rollType,
      'dice': '${_numDice}d$_diceSides',
      'rolls': allRolls,
      'base_total': finalResult,
      'modifiers': totalModifiers,
      'modifier_breakdown': modifierBreakdown,
      'final_total': _total,
      'is_critical': isCritical,
      'is_critical_failure': isCriticalFailure,
      'advantage': _advantage,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _rollHistory.insert(0, rollEntry);
    if (_rollHistory.length > 20) {
      _rollHistory.removeLast();
    }

    // Save to database if character exists
    if (character?.id != null) {
      await DatabaseHelper.instance.insertRollHistory({
        'character_id': character!.id,
        'roll_type': _rollType,
        'dice_notation': '${_numDice}d$_diceSides',
        'result': _total,
        'details': jsonEncode(rollEntry),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    _isRolling = false;
    notifyListeners();
  }

  void clearHistory() {
    _rollHistory.clear();
    notifyListeners();
  }
}

// Initiative Tracker Model
class InitiativeModel with ChangeNotifier {
  List<Map<String, dynamic>> _initiatives = [];
  
  List<Map<String, dynamic>> get initiatives => _initiatives;

  void addInitiative(String name, int dexMod) {
    final roll = Random().nextInt(20) + 1;
    final total = roll + dexMod;
    
    _initiatives.add({
      'name': name,
      'roll': roll,
      'dex_mod': dexMod,
      'total': total,
    });
    
    _sortInitiatives();
    notifyListeners();
  }

  void removeInitiative(int index) {
    if (index >= 0 && index < _initiatives.length) {
      _initiatives.removeAt(index);
      notifyListeners();
    }
  }

  void clearInitiatives() {
    _initiatives.clear();
    notifyListeners();
  }

  void _sortInitiatives() {
    _initiatives.sort((a, b) => b['total'].compareTo(a['total']));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbHelper = DatabaseHelper.instance;
  final characterData = await dbHelper.getActiveCharacter();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final model = CharacterModel();
          if (characterData != null) model.updateFromMap(characterData);
          return model;
        }),
        ChangeNotifierProvider(create: (_) => DiceRollerModel()),
        ChangeNotifierProvider(create: (_) => InitiativeModel()),
      ],
      child: const DnDDiceRollerApp(),
    ),
  );
}

class DnDDiceRollerApp extends StatelessWidget {
  const DnDDiceRollerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enhanced D&D Dice Roller',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    DiceRollerScreen(),
    CharacterSheetScreen(),
    InitiativeScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.casino),
            label: 'Dice Roller',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Character',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Initiative',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class DiceRollerScreen extends StatelessWidget {
  const DiceRollerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final diceModel = Provider.of<DiceRollerModel>(context);
    final characterModel = Provider.of<CharacterModel>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('D&D Dice Roller'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => _showRollHistory(context, diceModel),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Quick Roll Buttons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick Rolls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: () => _quickRoll(diceModel, 'Initiative Roll', characterModel),
                          child: const Text('Initiative'),
                        ),
                        ElevatedButton(
                          onPressed: () => _quickRoll(diceModel, 'Death Saving Throw', characterModel),
                          child: const Text('Death Save'),
                        ),
                        ElevatedButton(
                          onPressed: () => _quickRoll(diceModel, 'Ability Check', characterModel),
                          child: const Text('Perception'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Dice Configuration
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Number of Dice and Sides
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Number of Dice'),
                              DropdownButton<int>(
                                isExpanded: true,
                                value: diceModel.numDice,
                                items: List.generate(10, (index) => index + 1)
                                    .map((value) => DropdownMenuItem(value: value, child: Text(value.toString())))
                                    .toList(),
                                onChanged: (value) => diceModel.setNumDice(value!),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Die Type'),
                              DropdownButton<int>(
                                isExpanded: true,
                                value: diceModel.diceSides,
                                items: [4, 6, 8, 10, 12, 20, 100]
                                    .map((sides) => DropdownMenuItem(value: sides, child: Text('d$sides')))
                                    .toList(),
                                onChanged: (value) => diceModel.setDiceSides(value!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Roll Type
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Roll Type'),
                        DropdownButton<String>(
                          isExpanded: true,
                          value: diceModel.rollType,
                          items: [
                            'Ability Check',
                            'Skill Check',
                            'Saving Throw',
                            'Attack Roll',
                            'Initiative Roll',
                            'Death Saving Throw',
                            'Damage Roll',
                            'Spell Damage',
                            'Raw Dice'
                          ].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                          onChanged: (value) => diceModel.setRollType(value!),
                        ),
                      ],
                    ),
                    
                    // Skill selection for Skill Check
                    if (diceModel.rollType == 'Skill Check') ...[
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Skill'),
                          DropdownButton<String>(
                            isExpanded: true,
                            value: diceModel.skill.isEmpty ? 'Athletics' : diceModel.skill,
                            items: CharacterModel.skillToAbility.keys
                                .map((skill) => DropdownMenuItem(value: skill, child: Text(skill)))
                                .toList(),
                            onChanged: (value) => diceModel.setSkill(value!),
                          ),
                        ],
                      ),
                    ],
                    
                    // Ability (for non-skill checks)
                    if (diceModel.rollType != 'Skill Check' && 
                        diceModel.rollType != 'Death Saving Throw' && 
                        diceModel.rollType != 'Spell Damage' && 
                        diceModel.rollType != 'Raw Dice') ...[
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ability'),
                          DropdownButton<String>(
                            isExpanded: true,
                            value: diceModel.ability,
                            items: ['Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma']
                                .map((ability) => DropdownMenuItem(value: ability, child: Text(ability)))
                                .toList(),
                            onChanged: (value) => diceModel.setAbility(value!),
                          ),
                        ],
                      ),
                    ],
                    
                    // Proficiency (for relevant rolls)
                    if (diceModel.rollType != 'Initiative Roll' && 
                        diceModel.rollType != 'Death Saving Throw' && 
                        diceModel.rollType != 'Skill Check' &&
                        diceModel.rollType != 'Spell Damage' && 
                        diceModel.rollType != 'Raw Dice') ...[
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('Proficient'),
                        value: diceModel.isProficient,
                        onChanged: (value) => diceModel.setProficient(value!),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    ],
                    
                    // Advantage/Disadvantage (d20 only)
                    if (diceModel.diceSides == 20) ...[
                      const SizedBox(height: 16),
                      const Text('Advantage/Disadvantage'),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Normal'),
                              value: 'Normal',
                              groupValue: diceModel.advantage,
                              onChanged: (value) => diceModel.setAdvantage(value!),
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Advantage'),
                              value: 'Advantage',
                              groupValue: diceModel.advantage,
                              onChanged: (value) => diceModel.setAdvantage(value!),
                              dense: true,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Disadvantage'),
                              value: 'Disadvantage',
                              groupValue: diceModel.advantage,
                              onChanged: (value) => diceModel.setAdvantage(value!),
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                    
                    // Extra Bonus
                    const SizedBox(height: 16),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Extra Bonus/Penalty',
                        hintText: 'e.g., +2 or -1',
                      ),
                      onChanged: (value) {
                        final bonus = int.tryParse(value) ?? 0;
                        diceModel.setExtraBonus(bonus);
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Roll Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: diceModel.isRolling ? null : () => diceModel.rollDice(characterModel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  textStyle: const TextStyle(fontSize: 24),
                ),
                child: diceModel.isRolling 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('Roll ${diceModel.numDice}d${diceModel.diceSides}'),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Results Display
            if (diceModel.results.isNotEmpty) _buildResultsCard(diceModel),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard(DiceRollerModel diceModel) {
    final lastRoll = diceModel.rollHistory.isNotEmpty ? diceModel.rollHistory.first : null;
    if (lastRoll == null) return const SizedBox.shrink();

    final isCrit = lastRoll['is_critical'] == true;
    final isCritFail = lastRoll['is_critical_failure'] == true;

    return Card(
      color: isCrit 
          ? Colors.green.withOpacity(0.2) 
          : isCritFail 
              ? Colors.red.withOpacity(0.2) 
              : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isCrit 
                      ? '🎉 NATURAL 20!' 
                      : isCritFail 
                          ? '💀 NATURAL 1!' 
                          : 'Result',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isCrit 
                        ? Colors.green 
                        : isCritFail 
                            ? Colors.red 
                            : null,
                  ),
                ),
                Text(
                  lastRoll['final_total'].toString(),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Rolls: ${lastRoll['rolls'].join(', ')}',
              style: const TextStyle(fontSize: 16),
            ),
            if (lastRoll['modifier_breakdown']?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                'Modifiers: ${lastRoll['modifier_breakdown']}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
            if (lastRoll['advantage'] != 'Normal') ...[
              const SizedBox(height: 4),
              Text(
                lastRoll['advantage'],
                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _quickRoll(DiceRollerModel diceModel, String rollType, CharacterModel characterModel) {
    diceModel.setRollType(rollType);
    diceModel.setNumDice(1);
    diceModel.setDiceSides(20);
    diceModel.setAdvantage('Normal');
    diceModel.setExtraBonus(0);
    
    switch (rollType) {
      case 'Initiative Roll':
        diceModel.setAbility('Dexterity');
        diceModel.setProficient(false);
        break;
      case 'Death Saving Throw':
        // No modifiers
        break;
      case 'Ability Check':
        diceModel.setAbility('Wisdom'); // For perception
        diceModel.setProficient(characterModel.skillProficiencies['Perception'] ?? false);
        break;
    }
    
    diceModel.rollDice(characterModel);
  }

  void _showRollHistory(BuildContext context, DiceRollerModel diceModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Roll History'),
            TextButton(
              onPressed: () {
                diceModel.clearHistory();
                Navigator.of(context).pop();
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: diceModel.rollHistory.length,
            itemBuilder: (context, index) {
              final roll = diceModel.rollHistory[index];
              final time = DateTime.fromMillisecondsSinceEpoch(roll['timestamp']);
              
              return ListTile(
                title: Text('${roll['type']} - ${roll['dice']}'),
                subtitle: Text(
                  '${roll['rolls'].join(', ')} = ${roll['final_total']}\n'
                  '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                ),
                trailing: roll['is_critical'] == true
                    ? const Icon(Icons.star, color: Colors.green)
                    : roll['is_critical_failure'] == true
                        ? const Icon(Icons.warning, color: Colors.red)
                        : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class CharacterSheetScreen extends StatefulWidget {
  const CharacterSheetScreen({super.key});

  @override
  State<CharacterSheetScreen> createState() => _CharacterSheetScreenState();
}

class _CharacterSheetScreenState extends State<CharacterSheetScreen> {
  final _nameController = TextEditingController();
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final stats = ['strength', 'dexterity', 'constitution', 'intelligence', 'wisdom', 'charisma', 
                   'proficiency_bonus', 'max_hp', 'current_hp', 'temp_hp'];
    for (final stat in stats) {
      _controllers[stat] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _controllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CharacterModel>(
      builder: (context, characterModel, child) {
        // Update controllers when character changes
        _nameController.text = characterModel.name;
        _controllers['strength']!.text = characterModel.strength.toString();
        _controllers['dexterity']!.text = characterModel.dexterity.toString();
        _controllers['constitution']!.text = characterModel.constitution.toString();
        _controllers['intelligence']!.text = characterModel.intelligence.toString();
        _controllers['wisdom']!.text = characterModel.wisdom.toString();
        _controllers['charisma']!.text = characterModel.charisma.toString();
        _controllers['proficiency_bonus']!.text = characterModel.proficiencyBonus.toString();
        _controllers['max_hp']!.text = characterModel.maxHp.toString();
        _controllers['current_hp']!.text = characterModel.currentHp.toString();
        _controllers['temp_hp']!.text = characterModel.tempHp.toString();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Character Sheet'),
            actions: [
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: () => _saveCharacter(characterModel),
              ),
              PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'long_rest',
                    child: Text('Long Rest'),
                  ),
                  const PopupMenuItem(
                    value: 'manage_chars',
                    child: Text('Manage Characters'),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'long_rest':
                      characterModel.longRest();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Long rest completed!')),
                      );
                      break;
                    case 'manage_chars':
                      _showCharacterManager(context);
                      break;
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Character Name
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Character Name'),
                  onChanged: (value) => characterModel.name = value,
                ),
                const SizedBox(height: 20),
                
                // Ability Scores
                const Text('Ability Scores', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildAbilityScores(characterModel),
                const SizedBox(height: 20),
                
                // Health and Resources
                const Text('Health & Resources', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildHealthSection(characterModel),
                const SizedBox(height: 20),
                
                // Skills
                const Text('Skill Proficiencies', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildSkillsSection(characterModel),
                const SizedBox(height: 20),
                
                // Spell Slots
                const Text('Spell Slots', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildSpellSlotsSection(characterModel),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAbilityScores(CharacterModel characterModel) {
    final abilities = [
      ('Strength', 'strength', characterModel.strength),
      ('Dexterity', 'dexterity', characterModel.dexterity),
      ('Constitution', 'constitution', characterModel.constitution),
      ('Intelligence', 'intelligence', characterModel.intelligence),
      ('Wisdom', 'wisdom', characterModel.wisdom),
      ('Charisma', 'charisma', characterModel.charisma),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ...abilities.map((ability) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(ability.$1, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controllers[ability.$2],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onChanged: (value) {
                        final score = int.tryParse(value) ?? 10;
                        characterModel.updateStat(ability.$2, score);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 60,
                    child: Text(
                      'Mod: ${characterModel.getModifier(ability.$3) >= 0 ? '+' : ''}${characterModel.getModifier(ability.$3)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            )),
            const Divider(),
            Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text('Proficiency Bonus', style: TextStyle(fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: TextField(
                    controller: _controllers['proficiency_bonus'],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onChanged: (value) {
                      final bonus = int.tryParse(value) ?? 2;
                      characterModel.updateStat('proficiency_bonus', bonus);
                    },
                  ),
                ),
                const SizedBox(width: 76),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthSection(CharacterModel characterModel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers['max_hp'],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max HP'),
                    onChanged: (value) {
                      final hp = int.tryParse(value) ?? 0;
                      characterModel.updateStat('max_hp', hp);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _controllers['current_hp'],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Current HP'),
                    onChanged: (value) {
                      final hp = int.tryParse(value) ?? 0;
                      characterModel.updateStat('current_hp', hp);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controllers['temp_hp'],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Temporary HP'),
              onChanged: (value) {
                final hp = int.tryParse(value) ?? 0;
                characterModel.updateStat('temp_hp', hp);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsSection(CharacterModel characterModel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: CharacterModel.skillToAbility.entries.map((entry) {
            final skill = entry.key;
            final ability = entry.value;
            final modifier = characterModel.getSkillModifier(skill);
            
            return CheckboxListTile(
              title: Text('$skill ($ability)'),
              subtitle: Text('Modifier: ${modifier >= 0 ? '+' : ''}$modifier'),
              value: characterModel.skillProficiencies[skill],
              onChanged: (_) => characterModel.toggleProficiency(skill),
              dense: true,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSpellSlotsSection(CharacterModel characterModel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: List.generate(9, (index) {
            final level = index + 1;
            final maxSlots = characterModel.maxSpellSlots[level] ?? 0;
            final usedSlots = characterModel.usedSpellSlots[level] ?? 0;
            final availableSlots = maxSlots - usedSlots;

            return Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text('Level $level:', style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max',
                      isDense: true,
                    ),
                    controller: TextEditingController(text: maxSlots.toString()),
                    onChanged: (value) {
                      final slots = int.tryParse(value) ?? 0;
                      characterModel.maxSpellSlots[level] = slots;
                      characterModel.notifyListeners();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Text('Used: $usedSlots'),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: usedSlots > 0 ? () => characterModel.restoreSpellSlot(level) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: usedSlots < maxSlots ? () => characterModel.useSpellSlot(level) : null,
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _saveCharacter(CharacterModel characterModel) async {
    try {
      await DatabaseHelper.instance.insertOrUpdateCharacter(characterModel.toMap());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Character saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving character: $e')),
        );
      }
    }
  }

  void _showCharacterManager(BuildContext context) {
    // This would show a dialog to manage multiple characters
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Character Manager'),
        content: Text('Multiple character management coming soon!'),
      ),
    );
  }
}

class InitiativeScreen extends StatelessWidget {
  const InitiativeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InitiativeModel>(
      builder: (context, initiativeModel, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Initiative Tracker'),
            actions: [
              if (initiativeModel.initiatives.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  onPressed: () => _confirmClear(context, initiativeModel),
                ),
            ],
          ),
          body: Column(
            children: [
              // Add Initiative Section
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('Add to Initiative', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                hintText: 'Character or Monster',
                              ),
                              onSubmitted: (name) => _addInitiative(context, initiativeModel, name),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'DEX Mod',
                                hintText: '+0',
                              ),
                              onSubmitted: (dexMod) {
                                // Handle submission
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _showAddDialog(context, initiativeModel),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // Initiative List
              Expanded(
                child: initiativeModel.initiatives.isEmpty
                    ? const Center(
                        child: Text(
                          'No initiatives rolled yet.\nAdd characters above to get started!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: initiativeModel.initiatives.length,
                        itemBuilder: (context, index) {
                          final initiative = initiativeModel.initiatives[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.deepPurple,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                initiative['name'],
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Rolled: ${initiative['roll']} + DEX ${initiative['dex_mod']} = ${initiative['total']}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => initiativeModel.removeInitiative(index),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addInitiative(BuildContext context, InitiativeModel model, String name, [int dexMod = 0]) {
    if (name.isNotEmpty) {
      model.addInitiative(name, dexMod);
    }
  }

  void _showAddDialog(BuildContext context, InitiativeModel initiativeModel) {
    final nameController = TextEditingController();
    final dexController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Initiative'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dexController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dexterity Modifier'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final dexMod = int.tryParse(dexController.text) ?? 0;
              if (name.isNotEmpty) {
                initiativeModel.addInitiative(name, dexMod);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Roll Initiative'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, InitiativeModel initiativeModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Initiative'),
        content: const Text('Are you sure you want to clear all initiative entries?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              initiativeModel.clearInitiatives();
              Navigator.of(context).pop();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
