import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers.dart';

/// E-posta/şifre ile giriş ve kayıt (Supabase Auth).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.showSkip});

  /// İlk açılışta "hesapsız devam et" seçeneğini gösterir.
  final bool showSkip;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  GoTrueClient? get _auth => ref.read(syncServiceProvider).client?.auth;

  void _show(String message, {bool error = true}) =>
      setState(() {
        _message = message;
        _isError = error;
      });

  Future<void> _submit() async {
    final auth = _auth;
    final email = _email.text.trim();
    final password = _password.text;
    if (auth == null) return;
    if (!email.contains('@') || password.length < 6) {
      _show('Geçerli bir e-posta ve en az 6 karakterli şifre gir.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_signUp) {
        final res = await auth.signUp(email: email, password: password);
        if (res.session == null) {
          _show(
            'Kayıt oluşturuldu. E-postana gelen bağlantıyla hesabını doğrula, '
            'sonra buradan giriş yap.',
            error: false,
          );
          setState(() => _signUp = false);
          return;
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } on AuthException catch (e) {
      _show(_translate(e.message));
    } catch (e) {
      _show('Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final auth = _auth;
    final email = _email.text.trim();
    if (auth == null) return;
    if (!email.contains('@')) {
      _show('Önce e-posta adresini yaz.');
      return;
    }
    try {
      await auth.resetPasswordForEmail(email);
      _show('Şifre sıfırlama bağlantısı e-postana gönderildi.', error: false);
    } on AuthException catch (e) {
      _show(_translate(e.message));
    }
  }

  String _translate(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login')) return 'E-posta veya şifre hatalı.';
    if (m.contains('email not confirmed')) {
      return 'E-posta adresin henüz doğrulanmamış. Gelen kutunu kontrol et.';
    }
    if (m.contains('already registered')) {
      return 'Bu e-posta ile zaten bir hesap var. Giriş yapmayı dene.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.showSkip ? null : AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.hourglass_bottom_rounded,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Zamanla',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'İşini ve kişisel hayatını tek yerden planla. Giriş yaparak '
                      'telefonun ve bilgisayarın arasında her şeyi eşitle.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                          labelText: 'E-posta', prefixIcon: Icon(Icons.mail_outline)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: [
                        _signUp ? AutofillHints.newPassword : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(
                          labelText: 'Şifre', prefixIcon: Icon(Icons.lock_outline)),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!,
                          style: TextStyle(
                              color: _isError
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_signUp ? 'Hesap oluştur' : 'Giriş yap'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _signUp = !_signUp;
                            _message = null;
                          }),
                          child: Text(_signUp
                              ? 'Hesabın var mı? Giriş yap'
                              : 'Hesabın yok mu? Kayıt ol'),
                        ),
                        if (!_signUp)
                          TextButton(
                            onPressed: _resetPassword,
                            child: const Text('Şifremi unuttum'),
                          ),
                      ],
                    ),
                    if (widget.showSkip) ...[
                      const Divider(height: 32),
                      OutlinedButton(
                        onPressed: () => ref
                            .read(settingsProvider.notifier)
                            .update((s) => s.copyWith(authSkipped: true)),
                        child: const Text('Şimdilik hesapsız devam et'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Verilerin bu cihazda kalır. İstediğin zaman Ayarlar\'dan giriş yapabilirsin; '
                        'mevcut verilerin hesabına yüklenir.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
