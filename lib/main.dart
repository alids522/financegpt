import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'store.dart';
import 'theme.dart';
import 'shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: defaultSupabaseUrl,
    ),
    anonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: defaultAnonKey,
    ),
  );
  runApp(FinanceApp(preferences: await SharedPreferences.getInstance()));
}

class FinanceApp extends StatefulWidget {
  final SharedPreferences preferences;
  const FinanceApp({super.key, required this.preferences});
  @override
  State<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends State<FinanceApp> {
  late ThemeMode mode = ThemeMode.values.byName(
    widget.preferences.getString('theme') ?? 'system',
  );
  void setTheme(String value) {
    setState(() => mode = ThemeMode.values.byName(value));
    widget.preferences.setString('theme', value);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Finance Tracker',
    debugShowCheckedModeBanner: false,
    theme: financeTheme(Brightness.light),
    darkTheme: financeTheme(Brightness.dark),
    themeMode: mode,
    locale: const Locale('id', 'ID'),
    supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) =>
          Supabase.instance.client.auth.currentSession == null
          ? const AuthPage()
          : FinanceShell(
              key: ValueKey(Supabase.instance.client.auth.currentUser!.id),
              onTheme: setTheme,
              preferences: widget.preferences,
            ),
    ),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool signup = false, busy = false, visible = false;
  String? error;
  @override
  void dispose() {
    for (final c in [username, email, password, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (signup) {
        final result = await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {
            'username': username.text.trim().toLowerCase(),
            'app': 'financegpt',
          },
        );
        if (result.session == null) {
          throw Exception(
            'Server belum mengaktifkan signup langsung. Hubungi administrator.',
          );
        }
      } else if (email.text.contains('@')) {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        final res = await http.post(
          Uri.parse('$apiUrl/api/v1/auth/login'),
          headers: {
            'Content-Type': 'application/json',
            'apikey': const String.fromEnvironment(
              'SUPABASE_ANON_KEY',
              defaultValue: defaultAnonKey,
            ),
          },
          body: jsonEncode({
            'identifier': email.text.trim(),
            'password': password.text,
          }),
        );
        final value = jsonDecode(res.body);
        if (res.statusCode != 200) {
          throw Exception('Username/email atau password tidak sesuai.');
        }
        await auth.setSession(value['refresh_token']);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = signup
              ? readableError(e)
              : 'Login gagal. Periksa username/email dan password, lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'FINANCE TRACKER',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Text(
                signup ? 'Mulai kelola keuangan.' : 'Selamat datang kembali.',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                signup
                    ? 'Satu tempat untuk keuangan yang lebih terarah.'
                    : 'Masuk untuk melihat keuangan Anda.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (signup) ...[
                          TextFormField(
                            controller: username,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (v) =>
                                RegExp(
                                  r'^[a-zA-Z0-9_]{3,24}$',
                                ).hasMatch(v ?? '')
                                ? null
                                : '3–24 huruf, angka, atau underscore.',
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: email,
                          decoration: InputDecoration(
                            labelText: signup ? 'Email' : 'Username atau Email',
                          ),
                          keyboardType: signup
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          textInputAction: TextInputAction.next,
                          validator: (v) => signup
                              ? (RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(v ?? '')
                                    ? null
                                    : 'Masukkan email yang valid.')
                              : (v!.trim().isEmpty
                                    ? 'Masukkan username atau email.'
                                    : null),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: password,
                          obscureText: !visible,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            helperText: signup
                                ? 'Minimal 8 karakter; disarankan 12 atau lebih.'
                                : null,
                            suffixIcon: IconButton(
                              tooltip: visible
                                  ? 'Sembunyikan password'
                                  : 'Tampilkan password',
                              onPressed: () =>
                                  setState(() => visible = !visible),
                              icon: Icon(
                                visible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          onFieldSubmitted: (_) {
                            if (!signup) submit();
                          },
                          validator: (v) {
                            if ((v ?? '').length < 8) {
                              return 'Minimal 8 karakter.';
                            }
                            if (signup &&
                                (v == username.text || v == email.text)) {
                              return 'Password harus berbeda dari identitas Anda.';
                            }
                            return null;
                          },
                        ),
                        if (signup) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: confirm,
                            obscureText: !visible,
                            decoration: const InputDecoration(
                              labelText: 'Konfirmasi password',
                            ),
                            validator: (v) => v == password.text
                                ? null
                                : 'Password belum sama.',
                            onFieldSubmitted: (_) => submit(),
                          ),
                        ],
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: busy ? null : submit,
                          child: busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(signup ? 'Buat akun' : 'Masuk'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  setState(() {
                                    signup = !signup;
                                    error = null;
                                  });
                                  form.currentState?.reset();
                                },
                          child: Text(
                            signup
                                ? 'Sudah punya akun? Masuk'
                                : 'Belum punya akun? Daftar',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                signup
                    ? 'Akun langsung aktif tanpa konfirmasi email. Pastikan alamat email milik Anda.'
                    : 'Butuh bantuan akses? Hubungi administrator.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
