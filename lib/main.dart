import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String apiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);

// يمكنك تغيير النموذج لاحقاً إلى أي نموذج متاح لحسابك في Google AI Studio.
const String geminiModel = 'gemini-3.8-flash';

const Color bgColor = Color(0xFF0F172A);
const Color surfaceColor = Color(0xFF1E293B);
const Color accentColor = Color(0xFF38BDF8);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NoorApp());
}

class NoorApp extends StatelessWidget {
  const NoorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نور AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
          surface: surfaceColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceColor,
          centerTitle: true,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: accentColor),
          ),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const HomeScreen(),
    );
  }
}

/// اتصال مبسط بواجهة Gemini GenerateContent.
class GeminiService {
  static Future<String> generate({
    required List<Map<String, String>> history,
    String? systemPrompt,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception(
        'مفتاح Gemini غير موجود. أضف GEMINI_API_KEY في GitHub Secrets ثم أعد البناء.',
      );
    }

    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$geminiModel:generateContent',
      {'key': apiKey},
    );

    final contents = history.map((item) {
      return {
        'role': item['role'] == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': item['text'] ?? ''}
        ],
      };
    }).toList();

    final body = <String, dynamic>{
      'contents': contents,
      if (systemPrompt != null)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt}
          ]
        },
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 2048,
      },
    };

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // سيُعرض أدناه خطأ HTTP مفهوم عند تعذر قراءة الاستجابة.
    }

    if (response.statusCode == 200) {
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('لم يصل رد من Gemini. جرّب صياغة طلبك بطريقة أخرى.');
      }

      final content = candidates.first['content'];
      final parts = content is Map ? content['parts'] as List? : null;
      final answer = parts
          ?.whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join('\n')
          .trim();

      if (answer == null || answer.isEmpty) {
        throw Exception('وصل رد فارغ من Gemini. حاول مرة أخرى.');
      }
      return answer;
    }

    final apiMessage = data['error'] is Map
        ? data['error']['message']?.toString()
        : null;

    if (response.statusCode == 400 || response.statusCode == 403) {
      throw Exception(apiMessage ?? 'تحقق من صحة مفتاح Gemini وإعدادات المشروع.');
    }
    if (response.statusCode == 429) {
      throw Exception('تم تجاوز حد الطلبات. انتظر قليلاً ثم حاول مجدداً.');
    }
    throw Exception(
      apiMessage ?? 'تعذر الاتصال بخدمة Gemini (رمز ${response.statusCode}).',
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, color: accentColor),
            SizedBox(width: 8),
            Text('نور AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: IndexedStack(
        index: selectedIndex,
        children: const [ChatScreen(), ImproveScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        backgroundColor: surfaceColor,
        indicatorColor: accentColor.withOpacity(0.18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'الدردشة',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_fix_high),
            selectedIcon: Icon(Icons.auto_fix_high),
            label: 'تحسين النصوص',
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final List<Map<String, String>> messages = [];
  bool loading = false;

  Future<void> sendMessage() async {
    final question = controller.text.trim();
    if (question.isEmpty || loading) return;

    controller.clear();
    setState(() {
      messages.add({'role': 'user', 'text': question});
      loading = true;
    });
    _scrollToBottom();

    try {
      final answer = await GeminiService.generate(
        history: List<Map<String, String>>.from(messages),
        systemPrompt:
            'أنت نور AI، مساعد ذكي ومفيد. أجب باللغة العربية الواضحة ما لم يطلب المستخدم لغة أخرى. كن دقيقاً ومنظماً.',
      );
      if (!mounted) return;
      setState(() {
        messages.add({'role': 'assistant', 'text': answer});
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        messages.add({
          'role': 'assistant',
          'text': 'تعذر إكمال الطلب:\n${_friendlyError(error)}',
        });
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
        _scrollToBottom();
      }
    }
  }

  String _friendlyError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void newChat() {
    if (loading) return;
    setState(messages.clear);
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'تحدث مع نور، واسأله عمّا تريد',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              IconButton(
                tooltip: 'محادثة جديدة',
                onPressed: newChat,
                icon: const Icon(Icons.add_comment_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'مرحباً بك في نور AI',
                  subtitle: 'اكتب سؤالك في الأسفل لبدء محادثة ذكية.',
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isUser = message['role'] == 'user';
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: isUser ? const Color(0xFF075985) : surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(
                          message['text'] ?? '',
                          style: const TextStyle(height: 1.55, fontSize: 15),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('نور يفكر...'),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالتك هنا...',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: loading ? null : sendMessage,
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: bgColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ImproveScreen extends StatefulWidget {
  const ImproveScreen({super.key});

  @override
  State<ImproveScreen> createState() => _ImproveScreenState();
}

class _ImproveScreenState extends State<ImproveScreen> {
  final TextEditingController controller = TextEditingController();
  String result = '';
  String selectedStyle = 'احترافي';
  bool loading = false;

  final List<String> styles = const [
    'احترافي',
    'أدبي وثقافي',
    'إعلامي',
    'رسمي',
    'مختصر',
    'ودّي',
  ];

  Future<void> improveText() async {
    final input = controller.text.trim();
    if (input.isEmpty || loading) return;

    setState(() {
      loading = true;
      result = '';
    });

    try {
      final answer = await GeminiService.generate(
        history: [
          {
            'role': 'user',
            'text': 'أعد صياغة النص التالي بأسلوب $selectedStyle. '
                'صحح الأخطاء اللغوية والإملائية، وحسّن الترابط والوضوح، '
                'وحافظ على المعنى الأصلي دون إضافة معلومات غير موجودة. '
                'أعد النص المحسّن فقط:\n\n$input',
          },
        ],
        systemPrompt:
            'أنت محرر لغوي عربي محترف ومتخصص في تحسين النصوص والمنشورات.',
      );
      if (!mounted) return;
      setState(() => result = answer);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        result = 'تعذر تحسين النص:\n'
            '${error.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> copyResult() async {
    if (result.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: result));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ النص')),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'اجعل كلماتك أكثر تأثيراً ✨',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 7),
        const Text(
          'أدخل النص واختر الأسلوب الذي يناسب منشورك.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: controller,
          minLines: 6,
          maxLines: 10,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: 'الصق النص الذي تريد تحسينه هنا...',
            contentPadding: EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'أسلوب الصياغة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedStyle,
          decoration: const InputDecoration(contentPadding: EdgeInsets.all(14)),
          items: styles
              .map((style) => DropdownMenuItem(
                    value: style,
                    child: Text(style),
                  ))
              .toList(),
          onChanged: loading
              ? null
              : (value) {
                  if (value != null) setState(() => selectedStyle = value);
                },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: loading ? null : improveText,
          icon: const Icon(Icons.auto_awesome),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Text('حسّن النص الآن', style: TextStyle(fontSize: 16)),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: bgColor,
          ),
        ),
        if (loading) ...[
          const SizedBox(height: 22),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
          const Center(child: Text('نور يعمل على تحسين النص...')),
        ],
        if (result.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'النص المحسّن',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'نسخ النص',
                onPressed: copyResult,
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(
              result,
              style: const TextStyle(fontSize: 16, height: 1.8),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: accentColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
