import 'package:flutter/material.dart';
import 'continuous_listener.dart';

void main() => runApp(const AphasiaApp());

class AphasiaApp extends StatelessWidget {
  const AphasiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aphasia Assistant (UI Demo)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

/* -------------------- SIMPLE APP STATE (in-memory) -------------------- */

class PatientProfile {
  String name = "Patient";
  String preferredLanguage = "English";
  String communicationStyle = "Short & simple"; // or "Formal & complete"
  bool prefersIcons = true;
  bool needsSlowSpeech = true;
  bool sensitiveToNoise = false;
  bool sensitiveToLight = false;

  String caregiverName = "";
  String caregiverPhone = "";
  String allergies = "";
  String medications = "";
  String favoriteFoods = "";
  String interests = "";
  String routineTimes = "";
  String customNotes = "";
}

class AppState extends InheritedWidget {
  AppState({super.key, required super.child});

  // global-ish demo state
  final PatientProfile profile = PatientProfile();
  bool listeningOn = false;

  static AppState of(BuildContext context) {
    final AppState? result =
        context.dependOnInheritedWidgetOfExactType<AppState>();
    assert(result != null, 'No AppState found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(AppState oldWidget) => true;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return AppState(
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: const [
            HomeScreen(),
            PatientScreen(), // personalization tab
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.person_rounded), label: 'Patient'),
          ],
        ),
      ),
    );
  }
}

/* -------------------- HOME (Listening only) -------------------- */

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ContinuousListener? _listener;
  bool _listenerReady = false;

  Map<String, dynamic> _profileJson() {
    final p = AppState.of(context).profile;
    return {
      "name": p.name,
      "preferred_language": p.preferredLanguage,
      "communication_style": p.communicationStyle,
      "prefers_icons": p.prefersIcons,
      "needs_slow_speech": p.needsSlowSpeech,
      "sensitivities": {"noise": p.sensitiveToNoise, "light": p.sensitiveToLight},
      "caregiver": {"name": p.caregiverName, "phone": p.caregiverPhone},
      "personalization": {
        "favorite_foods": p.favoriteFoods,
        "interests": p.interests,
        "routine_times": p.routineTimes,
        "custom_notes": p.customNotes
      }
    };
  }

 @override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (_listenerReady) return;
  _listenerReady = true;


_listener = ContinuousListener(
  suggester: FakeSuggestionEngine(),
  patientProfile: _profileJson(),
  onSuggestions: ({required String transcript, required List<String> options}) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Heard: $transcript',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final opt in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Confirm to speak: "$opt"')),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        opt,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  },
);
}


//USING WHISPER
//   _listener = ContinuousListener(
//     stt: WhisperStt(
//       apiKey: "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",     // <-- real Whisper STT
//       model: 'whisper-1',    // or 'gpt-4o-mini-transcribe' if enabled
//       language: 'en',        // optional
//     ),
//     suggester: FakeSuggestionEngine(), // keep your stub suggester for now
//     patientProfile: _profileJson(),
//     onSuggestions: ({required String transcript, required List<String> options}) {
//       if (!mounted) return;
//       showModalBottomSheet(
//         context: context,
//         backgroundColor: Colors.grey[900],
//         shape: const RoundedRectangleBorder(
//           borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//         ),
//         builder: (ctx) {
//           return Padding(
//             padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text('Heard: $transcript',
//                   style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
//                 const SizedBox(height: 12),
//                 for (final opt in options)
//                   Padding(
//                     padding: const EdgeInsets.only(bottom: 8),
//                     child: ElevatedButton(
//                       onPressed: () {
//                         Navigator.pop(ctx);
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           SnackBar(content: Text('Confirm to speak: "$opt"')),
//                         );
//                         // TODO: add TTS + learning hook here
//                       },
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                         child: Text(
//                           opt,
//                           style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//                         ),
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           );
//         },
//       );
//     },
//   );
// }


  @override
  Widget build(BuildContext context) {
    final app = AppState.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("Aphasia Assistant — ${app.profile.name}"),
        centerTitle: true,
        actions: [
          _ListeningStatusPill(on: app.listeningOn),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 120),
                    backgroundColor:
                        app.listeningOn ? Colors.redAccent : Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () async {
                    final turnOn = !app.listeningOn;

                    if (turnOn) {
                      final ok = await _listener?.start() ?? false;
                      if (!ok) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mic permission needed or unavailable'),
                          ),
                        );
                        return;
                      }
                    } else {
                      await _listener?.stop();
                    }

                    setState(() => app.listeningOn = turnOn);
                    final status =
                        app.listeningOn ? "Listening ON" : "Listening OFF";
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(status)));
                  },
                  icon: Icon(
                    app.listeningOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    size: 44,
                  ),
                  label: Text(
                    app.listeningOn ? "Stop Listening" : "Start Listening",
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 28),
                _InfoCard(
                  title: "What happens here?",
                  child: const Text(
                    "When Listening is ON, the app streams the mic, splits speech into "
                    "short chunks, sends them to a stub STT + suggestion engine, and "
                    "shows 2–3 options. Raw audio is discarded immediately. "
                    "Swap the stubs for real STT/LLM later.",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class _ListeningStatusPill extends StatelessWidget {
  const _ListeningStatusPill({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final bg = on ? Colors.greenAccent : Colors.white24;
    final label = on ? "Listening ON" : "Listening OFF";
    return Container(
      margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(on ? Icons.mic_rounded : Icons.mic_off_rounded,
              size: 18, color: Colors.black),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }
}

/* -------------------- PATIENT TAB (Personalization fields) -------------------- */

class PatientScreen extends StatefulWidget {
  const PatientScreen({super.key});
  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen> {
  // Controllers (created after we can read InheritedWidget)
  TextEditingController? nameCtrl;
  TextEditingController? caregiverNameCtrl;
  TextEditingController? caregiverPhoneCtrl;
  TextEditingController? allergiesCtrl;
  TextEditingController? medsCtrl;
  TextEditingController? foodsCtrl;
  TextEditingController? interestsCtrl;
  TextEditingController? routineCtrl;
  TextEditingController? notesCtrl;

  String languageValue = "English";
  String styleValue = "Short & simple";
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;

    final p = AppState.of(context).profile;

    nameCtrl = TextEditingController(text: p.name);
    caregiverNameCtrl = TextEditingController(text: p.caregiverName);
    caregiverPhoneCtrl = TextEditingController(text: p.caregiverPhone);
    allergiesCtrl = TextEditingController(text: p.allergies);
    medsCtrl = TextEditingController(text: p.medications);
    foodsCtrl = TextEditingController(text: p.favoriteFoods);
    interestsCtrl = TextEditingController(text: p.interests);
    routineCtrl = TextEditingController(text: p.routineTimes);
    notesCtrl = TextEditingController(text: p.customNotes);

    languageValue = p.preferredLanguage;
    styleValue = p.communicationStyle;

    _inited = true;
  }

  @override
  void dispose() {
    nameCtrl?.dispose();
    caregiverNameCtrl?.dispose();
    caregiverPhoneCtrl?.dispose();
    allergiesCtrl?.dispose();
    medsCtrl?.dispose();
    foodsCtrl?.dispose();
    interestsCtrl?.dispose();
    routineCtrl?.dispose();
    notesCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.of(context);

    if (!_inited) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Patient Profile"),
        actions: [
          IconButton(
            tooltip: "Save",
            onPressed: () {
              final p = app.profile;
              setState(() {
                p.name = _safe(nameCtrl!.text, fallback: p.name);
                p.caregiverName = caregiverNameCtrl!.text.trim();
                p.caregiverPhone = caregiverPhoneCtrl!.text.trim();
                p.allergies = allergiesCtrl!.text.trim();
                p.medications = medsCtrl!.text.trim();
                p.favoriteFoods = foodsCtrl!.text.trim();
                p.interests = interestsCtrl!.text.trim();
                p.routineTimes = routineCtrl!.text.trim();
                p.customNotes = notesCtrl!.text.trim();
                p.preferredLanguage = languageValue;
                p.communicationStyle = styleValue;
              });
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("Profile saved")));
            },
            icon: const Icon(Icons.save_alt_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: "Identity",
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Name",
                  prefixIcon: Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: 8),
              _TwoColumn(
                left: DropdownButtonFormField<String>(
                  value: languageValue,
                  decoration: const InputDecoration(
                      labelText: "Preferred language",
                      prefixIcon: Icon(Icons.language_rounded)),
                  items: const [
                    DropdownMenuItem(value: "English", child: Text("English")),
                    DropdownMenuItem(value: "Spanish", child: Text("Spanish")),
                    DropdownMenuItem(value: "French", child: Text("French")),
                    DropdownMenuItem(value: "Other", child: Text("Other")),
                  ],
                  onChanged: (v) => setState(() => languageValue = v ?? "English"),
                ),
                right: DropdownButtonFormField<String>(
                  value: styleValue,
                  decoration: const InputDecoration(
                      labelText: "Communication style",
                      prefixIcon: Icon(Icons.chat_bubble_rounded)),
                  items: const [
                    DropdownMenuItem(
                        value: "Short & simple", child: Text("Short & simple")),
                    DropdownMenuItem(
                        value: "Formal & complete",
                        child: Text("Formal & complete")),
                  ],
                  onChanged: (v) => setState(() => styleValue = v ?? "Short & simple"),
                ),
              ),
              const SizedBox(height: 8),
              _TwoSwitches(
                title1: "Prefer icons",
                value1: app.profile.prefersIcons,
                onChanged1: (v) => setState(() => app.profile.prefersIcons = v),
                title2: "Needs slow speech",
                value2: app.profile.needsSlowSpeech,
                onChanged2: (v) => setState(() => app.profile.needsSlowSpeech = v),
              ),
            ],
          ),
          _Section(
            title: "Sensitivities",
            children: [
              _TwoSwitches(
                title1: "Noise sensitive",
                value1: app.profile.sensitiveToNoise,
                onChanged1: (v) =>
                    setState(() => app.profile.sensitiveToNoise = v),
                title2: "Light sensitive",
                value2: app.profile.sensitiveToLight,
                onChanged2: (v) =>
                    setState(() => app.profile.sensitiveToLight = v),
              ),
            ],
          ),
          _Section(
            title: "Caregiver",
            children: [
              TextField(
                controller: caregiverNameCtrl,
                decoration: const InputDecoration(
                  labelText: "Caregiver name",
                  prefixIcon: Icon(Icons.diversity_3_rounded),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: caregiverPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Caregiver phone",
                  prefixIcon: Icon(Icons.call_rounded),
                ),
              ),
            ],
          ),
          _Section(
            title: "Medical context (optional)",
            children: [
              TextField(
                controller: allergiesCtrl,
                decoration: const InputDecoration(
                  labelText: "Allergies",
                  prefixIcon: Icon(Icons.medication_liquid_rounded),
                ),
                minLines: 1,
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: medsCtrl,
                decoration: const InputDecoration(
                  labelText: "Medications",
                  prefixIcon: Icon(Icons.local_pharmacy_rounded),
                ),
                minLines: 1,
                maxLines: 3,
              ),
            ],
          ),
          _Section(
            title: "Personalization for LLM (later)",
            children: [
              TextField(
                controller: foodsCtrl,
                decoration: const InputDecoration(
                  labelText: "Favorite foods",
                  prefixIcon: Icon(Icons.restaurant_rounded),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: interestsCtrl,
                decoration: const InputDecoration(
                  labelText: "Interests / topics they enjoy",
                  prefixIcon: Icon(Icons.interests_rounded),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: routineCtrl,
                decoration: const InputDecoration(
                  labelText: "Routine times (meals/meds/sleep)",
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: "Custom notes for personalization",
                  prefixIcon: Icon(Icons.note_alt_rounded),
                ),
                minLines: 2,
                maxLines: 5,
              ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final p = AppState.of(context).profile;
          final preview = _profilePreview(p);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text("LLM Profile Preview (UI-only)"),
              content: SingleChildScrollView(child: Text(preview)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
              ],
            ),
          );
        },
        icon: const Icon(Icons.visibility_rounded),
        label: const Text("Preview Personalization"),
      ),
    );
  }

  String _profilePreview(PatientProfile p) {
    return """
{
  "name": "${p.name}",
  "preferred_language": "${p.preferredLanguage}",
  "communication_style": "${p.communicationStyle}",
  "prefers_icons": ${p.prefersIcons},
  "needs_slow_speech": ${p.needsSlowSpeech},
  "sensitivities": {
    "noise": ${p.sensitiveToNoise},
    "light": ${p.sensitiveToLight}
  },
  "caregiver": {
    "name": "${p.caregiverName}",
    "phone": "${p.caregiverPhone}"
  },
  "medical": {
    "allergies": "${p.allergies}",
    "medications": "${p.medications}"
  },
  "personalization": {
    "favorite_foods": "${p.favoriteFoods}",
    "interests": "${p.interests}",
    "routine_times": "${p.routineTimes}",
    "custom_notes": "${p.customNotes}"
  }
}
""";
  }

  String _safe(String v, {required String fallback}) =>
      v.trim().isEmpty ? fallback : v.trim();
}

/* -------------------- small reusable UI bits -------------------- */

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 520) {
        return Column(children: [left, const SizedBox(height: 8), right]);
      }
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
    });
  }
}

class _TwoSwitches extends StatelessWidget {
  const _TwoSwitches({
    required this.title1,
    required this.value1,
    required this.onChanged1,
    required this.title2,
    required this.value2,
    required this.onChanged2,
  });

  final String title1;
  final bool value1;
  final ValueChanged<bool> onChanged1;
  final String title2;
  final bool value2;
  final ValueChanged<bool> onChanged2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final row = Row(
        children: [
          Expanded(
            child: SwitchListTile(
              title: Text(title1),
              value: value1,
              onChanged: onChanged1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SwitchListTile(
              title: Text(title2),
              value: value2,
              onChanged: onChanged2,
            ),
          ),
        ],
      );
      if (c.maxWidth < 520) {
        return Column(children: [
          SwitchListTile(title: Text(title1), value: value1, onChanged: onChanged1),
          SwitchListTile(title: Text(title2), value: value2, onChanged: onChanged2),
        ]);
      }
      return row;
    });
  }
}
