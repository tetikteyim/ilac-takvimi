import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------------------
// Renkler (kullanicinin v2 tasarimiyla ayni palet)
// ---------------------------------------------------------------------------
const kBg = Color(0xFFF8FAFC);
const kCard = Color(0xFFFFFFFF);
const kInk = Color(0xFF0F172A);
const kMuted = Color(0xFF64748B);
const kLine = Color(0xFFE2E8F0);
const kGridLine = Color(0xFFF1F5F9);
const kAc = Color(0xFFFEF3C7);
const kAcInk = Color(0xFF92400E);
const kAcBorder = Color(0xFFF59E0B);
const kTok = Color(0xFFE0F2FE);
const kTokInk = Color(0xFF075985);
const kTokBorder = Color(0xFF0EA5E9);
const kAccent = Color(0xFF0D9488);
const kAccentHover = Color(0xFF0F766E);
const kAccentSoft = Color(0xFFF0FDFA);
const kAccentSoftBorder = Color(0xFFCCFBF1);
const kTakenGreen = Color(0xFF10B981);
const kTakenGreenDark = Color(0xFF059669);
const kDanger = Color(0xFFEF4444);
const kDangerSoft = Color(0xFFFEF2F2);
const kDangerSoftBorder = Color(0xFFFECACA);

const kDayNames = [
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
];
const kDayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const kMonths = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
];
const kPresetTimes = ['08:00', '10:00', '12:00', '14:00', '18:00', '20:00', '22:00'];

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Med {
  final String id;
  final String name;
  final String start; // YYYY-MM-DD
  final int days;
  final int qty;
  final String stomach; // 'ac' | 'tok'
  final List<String> times; // HH:MM

  Med({
    required this.id,
    required this.name,
    required this.start,
    required this.days,
    required this.qty,
    required this.stomach,
    required this.times,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'start': start, 'days': days,
        'qty': qty, 'stomach': stomach, 'times': times,
      };

  factory Med.fromJson(Map<String, dynamic> j) => Med(
        id: j['id'] as String,
        name: j['name'] as String,
        start: j['start'] as String,
        days: j['days'] as int,
        qty: (j['qty'] ?? 1) as int,
        stomach: (j['stomach'] ?? 'ac') as String,
        times: (j['times'] as List).map((e) => e.toString()).toList(),
      );
}

// ---------------------------------------------------------------------------
// Tarih yardımcıları
// ---------------------------------------------------------------------------
String toIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime fromIso(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

int dayDiff(String a, String b) => fromIso(b).difference(fromIso(a)).inDays;

String mondayOf(String iso) {
  final d = fromIso(iso);
  return toIso(d.subtract(Duration(days: (d.weekday - 1))));
}

String addDaysIso(String iso, int n) => toIso(fromIso(iso).add(Duration(days: n)));

bool isActiveOn(Med m, String iso) {
  final df = dayDiff(m.start, iso);
  return df >= 0 && df < m.days;
}

int remainingDays(Med m) {
  final df = dayDiff(m.start, toIso(DateTime.now()));
  if (df < 0) return m.days;
  final r = m.days - df;
  return r > 0 ? r : 0;
}

String doseKey(String medId, String iso, String t) => '$medId|$iso|$t';

// ---------------------------------------------------------------------------
// Kalıcı depolama
// ---------------------------------------------------------------------------
class Store {
  static Future<(List<Med>, Map<String, bool>)> load() async {
    final sp = await SharedPreferences.getInstance();
    List<Med> meds = [];
    Map<String, bool> taken = {};
    try {
      final m = sp.getString('meds');
      if (m != null) {
        meds = (jsonDecode(m) as List)
            .map((e) => Med.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    try {
      final t = sp.getString('taken');
      if (t != null) {
        (jsonDecode(t) as Map<String, dynamic>)
            .forEach((k, v) => taken[k] = v == true);
      }
    } catch (_) {}
    return (meds, taken);
  }

  static Future<void> saveMeds(List<Med> meds) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('meds', jsonEncode(meds.map((m) => m.toJson()).toList()));
  }

  static Future<void> saveTaken(Map<String, bool> taken) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('taken', jsonEncode(taken));
  }
}

// ---------------------------------------------------------------------------
// Bildirimler
// ---------------------------------------------------------------------------
class Notif {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'ilac_kanali',
      'İlaç hatırlatmaları',
      channelDescription: 'İlaç saati geldiğinde bildirim gönderir',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
    ),
  );

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
  }

  static Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
    }
  }

  static int _idOf(String medId, String iso, String t) =>
      doseKey(medId, iso, t).hashCode & 0x7fffffff;

  static Future<void> _scheduleOne(Med m, String iso, String t) async {
    final hp = t.split(':').map(int.parse).toList();
    final d = fromIso(iso);
    final dt = DateTime(d.year, d.month, d.day, hp[0], hp[1]);
    if (!dt.isAfter(DateTime.now())) return;
    final when = tz.TZDateTime.from(dt, tz.UTC);
    final title = 'İlaç zamanı: ${m.name.toUpperCase()}';
    final body =
        '$t — ${m.stomach == 'ac' ? 'AÇ' : 'TOK'} karnına ${m.qty} adet';
    try {
      await _plugin.zonedSchedule(
        _idOf(m.id, iso, t), title, body, when, _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Kesin alarm izni verilmemişse yaklaşık zamanlı planla.
      try {
        await _plugin.zonedSchedule(
          _idOf(m.id, iso, t), title, body, when, _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (_) {}
    }
  }

  /// Bir ilacın kür süresi boyunca tüm dozlarını planlar (en fazla 300 bildirim).
  static Future<void> scheduleMed(Med m) async {
    var count = 0;
    for (var d = 0; d < m.days && count < 300; d++) {
      final iso = addDaysIso(m.start, d);
      for (final t in m.times) {
        await _scheduleOne(m, iso, t);
        count++;
      }
    }
  }

  static Future<void> cancelMed(Med m) async {
    for (var d = 0; d < m.days; d++) {
      final iso = addDaysIso(m.start, d);
      for (final t in m.times) {
        await _plugin.cancel(_idOf(m.id, iso, t));
      }
    }
  }

  static Future<void> cancelDose(String medId, String iso, String t) =>
      _plugin.cancel(_idOf(medId, iso, t));

  static Future<void> rescheduleDose(Med m, String iso, String t) =>
      _scheduleOne(m, iso, t);
}

// ---------------------------------------------------------------------------
// Uygulama
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  tzdata.initializeTimeZones();
  await Notif.init();
  runApp(const IlacApp());
}

class IlacApp extends StatelessWidget {
  const IlacApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: kBg,
      colorScheme: ColorScheme.fromSeed(seedColor: kAccent),
    );
    return MaterialApp(
      title: 'İlaç Takvimi',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: base.copyWith(
        textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PageController _pc = PageController();
  int _page = 0;

  List<Med> meds = [];
  Map<String, bool> taken = {};
  String selectedDate = toIso(DateTime.now());
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final (m, t) = await Store.load();
    setState(() {
      meds = m;
      taken = t;
      loaded = true;
    });
    await Notif.requestPermissions();
  }

  Future<void> addMed(Med m) async {
    setState(() => meds.add(m));
    await Store.saveMeds(meds);
    await Notif.scheduleMed(m);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${m.name.toUpperCase()} kaydedildi, hatırlatmalar kuruldu ✓'),
        backgroundColor: kAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      _pc.animateToPage(0,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  Future<void> deleteMed(Med m) async {
    await Notif.cancelMed(m);
    setState(() {
      meds.removeWhere((x) => x.id == m.id);
      taken.removeWhere((k, _) => k.startsWith('${m.id}|'));
    });
    await Store.saveMeds(meds);
    await Store.saveTaken(taken);
  }

  Future<void> toggleDose(Med m, String iso, String t) async {
    final key = doseKey(m.id, iso, t);
    final nowTaken = !(taken[key] ?? false);
    setState(() {
      if (nowTaken) {
        taken[key] = true;
      } else {
        taken.remove(key);
      }
    });
    await Store.saveTaken(taken);
    // Alındı işaretlenen dozun bildirimi iptal edilir; işaret kaldırılırsa geri kurulur.
    if (nowTaken) {
      await Notif.cancelDose(m.id, iso, t);
    } else {
      await Notif.rescheduleDose(m, iso, t);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: kAccent)));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  SchedulePage(
                    meds: meds,
                    taken: taken,
                    selectedDate: selectedDate,
                    onSelectDate: (d) => setState(() => selectedDate = d),
                    onToggle: toggleDose,
                  ),
                  MedsPage(meds: meds, onDelete: _confirmDelete),
                  AddPage(onSave: addMed),
                ],
              ),
            ),
            _dots(),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Med m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${m.name.toUpperCase()} silinsin mi?'),
        content: const Text('Bu ilacın çizelgesi ve hatırlatmaları kaldırılacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil', style: TextStyle(color: kDanger)),
          ),
        ],
      ),
    );
    if (ok == true) await deleteMed(m);
  }

  Widget _topBar() {
    Widget tab(String label, int i) {
      final sel = _page == i;
      return GestureDetector(
        onTap: () => _pc.animateToPage(i,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? kCard : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: sel
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? kInk : kMuted)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: kCard,
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: Row(
        children: [
          const Text('İlaç Takvimi',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: kInk)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: kGridLine,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tab('Günün Çizelgesi', 0),
                const SizedBox(width: 6),
                tab('Kayıtlı İlaçlar', 1),
                const SizedBox(width: 6),
                tab('Yeni İlaç Ekle', 2),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Bildirim izinleri',
            onPressed: () async {
              await Notif.requestPermissions();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Bildirim izinleri kontrol edildi'),
                    behavior: SnackBarBehavior.floating));
              }
            },
            icon: const Icon(Icons.notifications_active_outlined, color: kAccent),
          ),
        ],
      ),
    );
  }

  Widget _dots() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final sel = i == _page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: sel ? 24 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: sel ? kAccent : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sayfa 1: Günün Çizelgesi
// ---------------------------------------------------------------------------
class SchedulePage extends StatelessWidget {
  final List<Med> meds;
  final Map<String, bool> taken;
  final String selectedDate;
  final ValueChanged<String> onSelectDate;
  final Future<void> Function(Med, String, String) onToggle;

  const SchedulePage({
    super.key,
    required this.meds,
    required this.taken,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final active = meds.where((m) => isActiveOn(m, selectedDate)).toList();
    final times = active.expand((m) => m.times).toSet().toList()..sort();

    var total = 0, done = 0;
    for (final m in active) {
      for (final t in m.times) {
        total++;
        if (taken[doseKey(m.id, selectedDate, t)] == true) done++;
      }
    }

    final d = fromIso(selectedDate);
    final dateLabel =
        '${d.day} ${kMonths[d.month - 1]} • ${kDayNames[d.weekday - 1]}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(dateLabel,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
                const Spacer(),
                if (total > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kAccentSoft,
                      border: Border.all(color: kAccentSoftBorder),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      done == total
                          ? 'Tüm dozlar alındı ✓'
                          : 'Alınan: $done / $total',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kAccent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _dayTabs(),
            const SizedBox(height: 16),
            if (active.isEmpty)
              _emptyBox('Bu gün için planlanmış ilaç yok.')
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kLine),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _grid(active, times),
                ),
              ),
            const SizedBox(height: 14),
            _legend(),
          ],
        ),
      ),
    );
  }

  Widget _dayTabs() {
    final todayIso = toIso(DateTime.now());
    final mon = mondayOf(todayIso);
    return Row(
      children: List.generate(7, (i) {
        final iso = addDaysIso(mon, i);
        final sel = iso == selectedDate;
        final isToday = iso == todayIso;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelectDate(iso),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(right: i < 6 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: sel ? kInk : (isToday ? kAccentSoft : kBg),
                border: Border.all(
                    color: sel ? kInk : (isToday ? kAccent : kLine)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: sel
                    ? [
                        BoxShadow(
                            color: kInk.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  Text(kDayShort[i].toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: sel
                              ? Colors.white
                              : (isToday ? kAccent : kMuted))),
                  const SizedBox(height: 2),
                  Text('${fromIso(iso).day}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: sel ? Colors.white : kInk)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _grid(List<Med> active, List<String> times) {
    const cellBorder = BorderSide(color: kGridLine, width: 1);

    Widget header(String s) => Container(
          color: kBg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.center,
          child: Text(s,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: kMuted)),
        );

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: const TableBorder(
        horizontalInside: cellBorder,
        verticalInside: cellBorder,
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          Container(color: kBg, width: 120, height: 44),
          ...times.map(header),
        ]),
        ...active.map((m) => TableRow(children: [
              Container(
                color: const Color(0xFFFCFDFD),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Text(m.name.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kInk)),
              ),
              ...times.map((t) {
                if (!m.times.contains(t)) {
                  return const SizedBox(width: 80, height: 48);
                }
                final key = doseKey(m.id, selectedDate, t);
                final isTaken = taken[key] == true;
                final isAc = m.stomach == 'ac';
                final bg = isTaken ? kTakenGreen : (isAc ? kAc : kTok);
                final fg = isTaken ? Colors.white : (isAc ? kAcInk : kTokInk);
                final bd = isTaken
                    ? kTakenGreenDark
                    : (isAc ? kAcBorder : kTokBorder).withOpacity(0.3);
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onToggle(m, selectedDate, t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: bd),
                        boxShadow: isTaken
                            ? [
                                BoxShadow(
                                    color: kTakenGreen.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2))
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (isAc ? 'AÇ' : 'TOK') +
                                (m.qty > 1 ? ' ×${m.qty}' : ''),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: fg),
                          ),
                          if (isTaken)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Text('✓',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ])),
      ],
    );
  }

  Widget _legend() {
    Widget sw(Color c, Color b, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: c,
                border: Border.all(color: b),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: kMuted)),
          ],
        );
    return Row(
      children: [
        sw(kAc, kAcBorder, 'AÇ karnına'),
        const SizedBox(width: 16),
        sw(kTok, kTokBorder, 'TOK karnına'),
        const Spacer(),
        const Flexible(
          child: Text('💡 İlacı aldığınızda kutusuna dokunarak onaylayın',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: kAccent),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sayfa 2: Kayıtlı İlaçlar
// ---------------------------------------------------------------------------
class MedsPage extends StatelessWidget {
  final List<Med> meds;
  final Future<void> Function(Med) onDelete;

  const MedsPage({super.key, required this.meds, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Kayıtlı İlaç Listesi'),
            const SizedBox(height: 12),
            if (meds.isEmpty)
              _emptyBox(
                  'Henüz ilaç eklenmedi. Sağa kaydırarak ekleme sayfasına geçin.')
            else
              ...meds.map((m) => _item(m)),
          ],
        ),
      ),
    );
  }

  Widget _item(Med m) {
    final rem = remainingDays(m);
    final s = fromIso(m.start);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFE),
        border: Border.all(color: kLine),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(m.name.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: kInk)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: rem > 0 ? kAccentSoftBorder : kGridLine,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        rem > 0 ? '$rem gün kaldı' : 'Tamamlandı',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: rem > 0 ? kAccentHover : kMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${m.stomach == 'ac' ? 'Aç' : 'Tok'} karnına • ${m.times.join(', ')} • '
                  'her seferde ${m.qty} adet • ${s.day} ${kMonths[s.month - 1]} başlangıç, toplam ${m.days} gün',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: kMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => onDelete(m),
            style: OutlinedButton.styleFrom(
              backgroundColor: kDangerSoft,
              foregroundColor: kDanger,
              side: const BorderSide(color: kDangerSoftBorder),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sil',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sayfa 3: Yeni İlaç Ekle
// ---------------------------------------------------------------------------
class AddPage extends StatefulWidget {
  final Future<void> Function(Med) onSave;
  const AddPage({super.key, required this.onSave});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _name = TextEditingController();
  final _days = TextEditingController(text: '7');
  final _qty = TextEditingController(text: '1');
  DateTime _start = DateTime.now();
  String _stomach = 'ac';
  final Set<String> _times = {};
  final List<String> _customTimes = [];

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _pickCustomTime() async {
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (t != null) {
      final s =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (!kPresetTimes.contains(s) && !_customTimes.contains(s)) {
          _customTimes.add(s);
          _customTimes.sort();
        }
        _times.add(s);
      });
    }
  }

  void _save() {
    final name = _name.text.trim();
    final days = int.tryParse(_days.text) ?? 0;
    final qty = int.tryParse(_qty.text) ?? 1;
    String? err;
    if (name.isEmpty) {
      err = 'İlaç adını yazın.';
    } else if (days < 1) {
      err = 'Kullanım süresini yazın.';
    } else if (_times.isEmpty) {
      err = 'En az bir saat seçin.';
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: kDanger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }
    final med = Med(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      name: name,
      start: toIso(_start),
      days: days,
      qty: qty < 1 ? 1 : qty,
      stomach: _stomach,
      times: _times.toList()..sort(),
    );
    widget.onSave(med);
    setState(() {
      _name.clear();
      _days.text = '7';
      _qty.text = '1';
      _times.clear();
      _customTimes.clear();
      _stomach = 'ac';
      _start = DateTime.now();
    });
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFCFDFE),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kAccent, width: 2),
        ),
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
      );

  @override
  Widget build(BuildContext context) {
    final allTimes = [...kPresetTimes, ..._customTimes]..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Yeni İlaç Ekle'),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('İlaç Adı'),
                      TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.characters,
                          decoration: _dec('Örn. Augmentin 1000mg')),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Başlangıç Günü'),
                      OutlinedButton(
                        onPressed: _pickDate,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kInk,
                          backgroundColor: const Color(0xFFFCFDFE),
                          side: const BorderSide(color: kLine),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                            '${_start.day} ${kMonths[_start.month - 1]} ${_start.year}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Kullanım Süresi (Gün)'),
                      TextField(
                          controller: _days,
                          keyboardType: TextInputType.number,
                          decoration: _dec('7')),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Doz (Adet/Ölçek)'),
                      TextField(
                          controller: _qty,
                          keyboardType: TextInputType.number,
                          decoration: _dec('1')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Karın Durumu'),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: kBg,
                        border: Border.all(color: kLine),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _segBtn('AÇ karnına', 'ac', kAc, kAcInk),
                          const SizedBox(width: 4),
                          _segBtn('TOK karnına', 'tok', kTok, kTokInk),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Kullanım Saatleri'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...allTimes.map((t) {
                            final sel = _times.contains(t);
                            return GestureDetector(
                              onTap: () => setState(() =>
                                  sel ? _times.remove(t) : _times.add(t)),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel ? kInk : kCard,
                                  border: Border.all(
                                      color: sel ? kInk : kLine),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: sel
                                      ? [
                                          BoxShadow(
                                              color: kInk.withOpacity(0.2),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2))
                                        ]
                                      : null,
                                ),
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            sel ? Colors.white : kMuted)),
                              ),
                            );
                          }),
                          OutlinedButton(
                            onPressed: _pickCustomTime,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kMuted,
                              side: const BorderSide(color: kLine),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999)),
                            ),
                            child: const Text('+ Saat Ekle',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 4,
                shadowColor: kAccent.withOpacity(0.25),
              ),
              child: const Text('İlacı Kaydet',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segBtn(String label, String value, Color bg, Color fg) {
    final sel = _stomach == value;
    return GestureDetector(
      onTap: () => setState(() => _stomach = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? bg : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1))
                ]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sel ? fg : kMuted)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ortak parçalar
// ---------------------------------------------------------------------------
Widget _card({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kLine.withOpacity(0.8)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );

Widget _sectionTitle(String s) => Text(s.toUpperCase(),
    style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
        color: kMuted));

Widget _emptyBox(String msg) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: kBg,
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(msg,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: kMuted)),
    );
