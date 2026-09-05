import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:i_zerak_app/services/service_locator.dart';

enum _TestState { idle, running, ok, failed }

/// Reglages du serveur auto-heberge : connexion qBittorrent, agent de
/// supervision du Raspberry Pi et destination Emby.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final IServerConfig _configRepository = getIt<IServerConfig>();
  final ICredentials _credentials = getIt<ICredentials>();
  final QbService _qbService = getIt<QbService>();

  final _formKey = GlobalKey<FormState>();

  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _agentPortController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _agentTokenController = TextEditingController();
  final _tmdbTokenController = TextEditingController();
  final _savePathController = TextEditingController();
  final _categoryController = TextEditingController();

  ServerConfig _config = ServerConfig();
  bool _loading = true;
  bool _obscurePassword = true;
  _TestState _testState = _TestState.idle;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _agentPortController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _agentTokenController.dispose();
    _tmdbTokenController.dispose();
    _savePathController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final stored = await _configRepository.read();
    final password = await _credentials.read(SecretKey.qbPassword);
    final agentToken = await _credentials.read(SecretKey.agentToken);
    final tmdbToken = await _credentials.read(SecretKey.tmdbToken);
    if (!mounted) {
      return;
    }

    final config = stored ?? ServerConfig();
    setState(() {
      _config = config;
      _hostController.text = config.host;
      _portController.text = config.port.toString();
      _agentPortController.text = config.agentPort.toString();
      _usernameController.text = config.username;
      _passwordController.text = password ?? '';
      _agentTokenController.text = agentToken ?? '';
      _tmdbTokenController.text = tmdbToken ?? '';
      _savePathController.text = config.defaultSavePath ?? '';
      _categoryController.text = config.defaultCategory ?? '';
      _loading = false;
    });
  }

  /// Construit la configuration a partir des champs courants, sans
  /// l'enregistrer : le test de connexion doit pouvoir porter sur une saisie
  /// non encore validee.
  ServerConfig _draft() => _config.copyWith(
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text) ?? _config.port,
        agentPort: int.tryParse(_agentPortController.text) ?? _config.agentPort,
        username: _usernameController.text.trim(),
        defaultSavePath: _savePathController.text.trim(),
        defaultCategory: _categoryController.text.trim(),
      );

  String _messageFor(BuildContext context, QbException error) {
    final l10n = AppLocalizations.of(context)!;
    // Le switch est exhaustif grace a la hierarchie scellee : ajouter un cas
    // d'erreur sans lui donner de message deviendra une erreur de compilation.
    return switch (error) {
      QbNotConfiguredException() => l10n.error_not_configured,
      QbAuthException() => l10n.error_invalid_credentials,
      QbBannedException() => l10n.error_ip_banned,
      QbCertificateException() => l10n.error_certificate,
      QbNetworkException() => l10n.error_unreachable,
      QbTimeoutException() => l10n.error_timeout,
      QbHttpException() => l10n.error_unreachable,
      QbUnsupportedEndpointException() => l10n.error_unreachable,
    };
  }

  Future<void> _testConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _testState = _TestState.running;
      _testMessage = null;
    });

    final draft = _draft();
    try {
      final version = await _qbService.testConnection(draft, _passwordController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _config = draft;
        _testState = _TestState.ok;
        _testMessage = AppLocalizations.of(context)!.connection_ok(version);
      });
    } on QbCertificateException catch (error) {
      if (!mounted) {
        return;
      }
      final fingerprint = error.presentedFingerprint;
      if (fingerprint != null && await _confirmCertificate(fingerprint)) {
        if (!mounted) {
          return;
        }
        setState(() => _config = draft.copyWith(pinnedCertSha256: fingerprint));
        await _testConnection();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _testState = _TestState.failed;
        _testMessage = _messageFor(context, error);
      });
    } on QbException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _testState = _TestState.failed;
        _testMessage = _messageFor(context, error);
      });
    }
  }

  /// Demande l'adoption explicite d'un certificat inconnu.
  ///
  /// L'empreinte est affichee pour etre comparee a celle du serveur, obtenue
  /// par `openssl x509 -noout -fingerprint -sha256`. C'est cette comparaison
  /// manuelle, faite une seule fois, qui remplace une autorite de certification.
  Future<bool> _confirmCertificate(String fingerprint) async {
    final l10n = AppLocalizations.of(context)!;
    final grouped = _groupFingerprint(fingerprint);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.certificate_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.certificate_explanation),
            const SizedBox(height: 12),
            SelectableText(
              grouped,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: Text(l10n.certificate_trust)),
        ],
      ),
    );
    return accepted ?? false;
  }

  static String _groupFingerprint(String fingerprint) {
    final pairs = <String>[];
    for (var i = 0; i + 1 < fingerprint.length; i += 2) {
      pairs.add(fingerprint.substring(i, i + 2).toUpperCase());
    }
    return pairs.join(':');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final config = _draft();
    await _configRepository.save(config);
    await _writeOrDelete(SecretKey.qbPassword, _passwordController.text);
    await _writeOrDelete(SecretKey.agentToken, _agentTokenController.text);
    await _writeOrDelete(SecretKey.tmdbToken, _tmdbTokenController.text);

    // Sans cela, le service continuerait de parler a l'ancien hote avec
    // l'ancienne session.
    _qbService.invalidate();

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _writeOrDelete(SecretKey key, String value) =>
      value.isEmpty ? _credentials.delete(key) : _credentials.write(key, value);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _sectionTitle(context, l10n.server_section),
                  TextFormField(
                    controller: _hostController,
                    decoration: InputDecoration(
                      labelText: l10n.server_host,
                      hintText: 'nas.lan',
                      border: const OutlineInputBorder(),
                    ),
                    autocorrect: false,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? l10n.please_enter_a_host : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _portField(_portController, l10n.server_port, l10n)),
                      const SizedBox(width: 12),
                      Expanded(child: _portField(_agentPortController, l10n.agent_port, l10n)),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.use_https),
                    subtitle: Text(_config.useHttps
                        ? l10n.use_https_on_hint
                        : l10n.use_https_off_hint),
                    value: _config.useHttps,
                    onChanged: (value) => setState(() {
                      // Changer de schema invalide le certificat approuve.
                      _config = _config.copyWith(useHttps: value, clearPinnedCert: !value);
                    }),
                  ),
                  if (_config.useHttps && _draft().hostIsRawIpv4)
                    _warning(context, l10n.warning_raw_ip_certificate),
                  if (!_config.useHttps) _warning(context, l10n.warning_cleartext_blocked),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    autocorrect: false,
                    decoration: InputDecoration(
                        labelText: l10n.username, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l10n.password,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _config.pollIntervalSeconds,
                    decoration: InputDecoration(
                        labelText: l10n.poll_interval, border: const OutlineInputBorder()),
                    items: const [0, 2, 3, 5, 10]
                        .map((seconds) => DropdownMenuItem<int>(
                              value: seconds,
                              child: Text(seconds == 0 ? l10n.poll_interval_manual : '$seconds s'),
                            ))
                        .toList(),
                    onChanged: (value) => setState(
                        () => _config = _config.copyWith(pollIntervalSeconds: value ?? 3)),
                  ),
                  const SizedBox(height: 16),
                  _testButton(context, l10n),
                  if (_testMessage != null) _testFeedback(context),
                  const Divider(height: 32),
                  _sectionTitle(context, l10n.agent_section),
                  TextFormField(
                    controller: _agentTokenController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l10n.agent_token,
                      helperText: l10n.agent_token_hint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const Divider(height: 32),
                  _sectionTitle(context, l10n.advanced_section),
                  TextFormField(
                    controller: _savePathController,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l10n.default_save_path,
                      hintText: '/mnt/media/films',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryController,
                    autocorrect: false,
                    decoration: InputDecoration(
                        labelText: l10n.default_category, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tmdbTokenController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l10n.tmdb_token,
                      helperText: l10n.tmdb_token_hint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.tmdb_attribution,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _save, child: Text(l10n.save)),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _portField(TextEditingController controller, String label, AppLocalizations l10n) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (value) {
          final port = int.tryParse(value ?? '');
          return (port == null || !ServerConfig.isValidPort(port))
              ? l10n.please_enter_a_valid_port
              : null;
        },
      );

  Widget _warning(BuildContext context, String message) => Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, size: 18, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );

  Widget _testButton(BuildContext context, AppLocalizations l10n) => OutlinedButton.icon(
        onPressed: _testState == _TestState.running ? null : _testConnection,
        icon: switch (_testState) {
          _TestState.running =>
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          _TestState.ok => const Icon(Icons.check_circle, color: Colors.green),
          _TestState.failed => Icon(Icons.error, color: Theme.of(context).colorScheme.error),
          _TestState.idle => const Icon(Icons.network_check),
        },
        label: Text(l10n.test_connection),
      );

  Widget _testFeedback(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          _testMessage!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _testState == _TestState.ok
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
        ),
      );
}
