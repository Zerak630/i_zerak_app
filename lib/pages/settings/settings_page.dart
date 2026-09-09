import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:i_zerak_app/services/service_locator.dart';

enum _TestState { idle, running, ok, failed }

/// Reglages du serveur auto-heberge.
///
/// L'ecran est decoupe par service et non par type de champ : une carte par
/// interlocuteur, chacune avec son port, ses identifiants et son propre test de
/// connexion. Seule la premiere carte est commune, parce que qBittorrent,
/// l'agent et Emby vivent sur la meme machine et partagent donc l'adresse, le
/// schema et le certificat epingle.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final IServerConfig _configRepository = getIt<IServerConfig>();
  final ICredentials _credentials = getIt<ICredentials>();
  final QbService _qbService = getIt<QbService>();
  final AgentService _agentService = getIt<AgentService>();

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
  bool _saving = false;
  bool _obscurePassword = true;

  // Chaque service porte son propre verdict : savoir que qBittorrent repond ne
  // dit rien de l'agent, et confondre les deux masquait la moitie des pannes.
  _TestState _qbState = _TestState.idle;
  String? _qbMessage;
  _TestState _agentState = _TestState.idle;
  String? _agentMessage;

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
  /// l'enregistrer : les tests de connexion doivent porter sur une saisie non
  /// encore validee.
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

  // --- Tests de connexion ---------------------------------------------------

  Future<void> _testQbittorrent() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _qbState = _TestState.running;
      _qbMessage = null;
    });

    final draft = _draft();
    try {
      final version = await _qbService.testConnection(draft, _passwordController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _config = draft;
        _qbState = _TestState.ok;
        _qbMessage = AppLocalizations.of(context)!.connection_ok(version);
      });
    } on QbCertificateException catch (error) {
      if (await _adoptCertificate(error, draft)) {
        await _testQbittorrent();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _qbState = _TestState.failed;
        _qbMessage = _messageFor(context, error);
      });
    } on QbException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _qbState = _TestState.failed;
        _qbMessage = _messageFor(context, error);
      });
    }
  }

  Future<void> _testAgent() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _agentState = _TestState.running;
      _agentMessage = null;
    });

    final draft = _draft();
    try {
      final version = await _agentService.testConnection(draft, _agentTokenController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _config = draft;
        _agentState = _TestState.ok;
        _agentMessage = AppLocalizations.of(context)!.agent_ok(version);
      });
    } on QbCertificateException catch (error) {
      if (await _adoptCertificate(error, draft)) {
        await _testAgent();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _agentState = _TestState.failed;
        _agentMessage = _messageFor(context, error);
      });
    } on QbException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _agentState = _TestState.failed;
        _agentMessage = _messageFor(context, error);
      });
    }
  }

  /// Propose d'adopter le certificat presente et retourne vrai s'il l'a ete.
  ///
  /// Partage par les deux tests : les deux services sont derriere le meme
  /// certificat, et l'empreinte approuvee depuis l'un vaut pour l'autre.
  Future<bool> _adoptCertificate(QbCertificateException error, ServerConfig draft) async {
    final fingerprint = error.presentedFingerprint;
    if (fingerprint == null || !mounted) {
      return false;
    }
    if (!await _confirmCertificate(fingerprint)) {
      return false;
    }
    if (!mounted) {
      return false;
    }
    setState(() => _config = draft.copyWith(pinnedCertSha256: fingerprint));
    return true;
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

  // --- Enregistrement -------------------------------------------------------

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    final config = _draft();
    try {
      await _configRepository.save(config);
      await _writeOrDelete(SecretKey.qbPassword, _passwordController.text);
      await _writeOrDelete(SecretKey.agentToken, _agentTokenController.text);
      await _writeOrDelete(SecretKey.tmdbToken, _tmdbTokenController.text);

      // Relecture depuis le depot, et non depuis la memoire : c'est le seul
      // moyen de distinguer une ecriture reellement persistee d'une valeur
      // simplement gardee en cache. Une configuration perdue au redemarrage
      // suivant est le pire des silences.
      final stored = await _configRepository.read();
      if (stored == null || stored.host != config.host || stored.port != config.port) {
        throw StateError('la configuration relue ne correspond pas a celle ecrite');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.settings_save_failed(error.toString())),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    // Sans cela, les services continueraient de parler a l'ancien hote avec
    // l'ancienne session et l'ancien jeton.
    _qbService.invalidate();
    _agentService.invalidate();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.settings_saved)));
    Navigator.pop(context, true);
  }

  Future<void> _writeOrDelete(SecretKey key, String value) =>
      value.isEmpty ? _credentials.delete(key) : _credentials.write(key, value);

  // --- Interface ------------------------------------------------------------

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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _piCard(context, l10n),
                  const SizedBox(height: 16),
                  // L'agent passe avant qBittorrent : c'est lui qui renseigne
                  // l'etat de la machine et du disque, donc le premier a
                  // eprouver quand quelque chose ne repond pas.
                  _agentCard(context, l10n),
                  const SizedBox(height: 16),
                  _qbittorrentCard(context, l10n),
                  const SizedBox(height: 16),
                  _embyCard(context, l10n),
                  const SizedBox(height: 16),
                  _tmdbCard(context, l10n),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(l10n.save),
                  ),
                ],
              ),
            ),
    );
  }

  /// Ce qui est commun aux trois services : ils tournent sur la meme machine.
  Widget _piCard(BuildContext context, AppLocalizations l10n) => _card(
        context,
        icon: Icons.developer_board,
        title: l10n.pi_section,
        hint: l10n.pi_section_hint,
        children: [
          TextFormField(
            controller: _hostController,
            decoration: InputDecoration(
              labelText: l10n.server_host,
              hintText: 'raspberrypi.local',
              border: const OutlineInputBorder(),
            ),
            autocorrect: false,
            keyboardType: TextInputType.url,
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? l10n.please_enter_a_host : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.use_https),
            subtitle: Text(_config.useHttps ? l10n.use_https_on_hint : l10n.use_https_off_hint),
            value: _config.useHttps,
            onChanged: (value) => setState(() {
              // Changer de schema invalide le certificat approuve.
              _config = _config.copyWith(useHttps: value, clearPinnedCert: !value);
              _qbState = _TestState.idle;
              _agentState = _TestState.idle;
            }),
          ),
          if (_config.useHttps && _draft().hostIsRawIpv4)
            _warning(context, l10n.warning_raw_ip_certificate),
          if (!_config.useHttps) _warning(context, l10n.warning_cleartext_blocked),
          if (_config.useHttps) _certificateRow(context, l10n),
        ],
      );

  /// Etat de l'epinglage, avec la possibilite de repartir de zero.
  ///
  /// Indispensable le jour ou le certificat du Pi est regenere : sans ce
  /// bouton, l'application refuserait la nouvelle empreinte sans jamais
  /// proposer de l'adopter.
  Widget _certificateRow(BuildContext context, AppLocalizations l10n) {
    final pinned = _config.pinnedCertSha256;
    final theme = Theme.of(context);
    // Les huit premiers octets suffisent a reconnaitre une empreinte deja
    // comparee ; les afficher en entier noierait le reste de la carte.
    const shortLength = 8 * 3 - 1;

    if (pinned == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          l10n.certificate_none,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.certificate_pinned, style: theme.textTheme.bodySmall),
                Builder(builder: (context) {
                  final grouped = _groupFingerprint(pinned);
                  return Text(
                    grouped.length <= shortLength
                        ? grouped
                        : '${grouped.substring(0, shortLength)}…',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  );
                }),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _config = _config.copyWith(clearPinnedCert: true);
              _qbState = _TestState.idle;
              _agentState = _TestState.idle;
            }),
            child: Text(l10n.certificate_forget),
          ),
        ],
      ),
    );
  }

  Widget _qbittorrentCard(BuildContext context, AppLocalizations l10n) => _card(
        context,
        icon: Icons.download,
        title: l10n.qbittorrent_section,
        hint: l10n.qbittorrent_section_hint,
        children: [
          _portField(_portController, l10n.server_port, l10n),
          TextFormField(
            controller: _usernameController,
            autocorrect: false,
            decoration:
                InputDecoration(labelText: l10n.username, border: const OutlineInputBorder()),
          ),
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
          TextFormField(
            controller: _categoryController,
            autocorrect: false,
            decoration: InputDecoration(
                labelText: l10n.default_category, border: const OutlineInputBorder()),
          ),
          DropdownButtonFormField<int>(
            initialValue: _config.pollIntervalSeconds,
            decoration:
                InputDecoration(labelText: l10n.poll_interval, border: const OutlineInputBorder()),
            items: const [0, 2, 3, 5, 10]
                .map((seconds) => DropdownMenuItem<int>(
                      value: seconds,
                      child: Text(seconds == 0 ? l10n.poll_interval_manual : '$seconds s'),
                    ))
                .toList(),
            onChanged: (value) =>
                setState(() => _config = _config.copyWith(pollIntervalSeconds: value ?? 3)),
          ),
          _testButton(context, l10n.test_connection, _qbState, _testQbittorrent),
          if (_qbMessage != null) _testFeedback(context, _qbMessage!, _qbState),
        ],
      );

  Widget _agentCard(BuildContext context, AppLocalizations l10n) => _card(
        context,
        icon: Icons.memory,
        title: l10n.agent_section,
        hint: l10n.agent_section_hint,
        children: [
          _portField(_agentPortController, l10n.agent_port, l10n),
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
          _testButton(context, l10n.test_agent, _agentState, _testAgent),
          if (_agentMessage != null) _testFeedback(context, _agentMessage!, _agentState),
        ],
      );

  Widget _embyCard(BuildContext context, AppLocalizations l10n) => _card(
        context,
        icon: Icons.movie_outlined,
        title: l10n.emby_section,
        hint: l10n.emby_section_hint,
        children: [
          TextFormField(
            controller: _savePathController,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.default_save_path,
              hintText: '/media/theo/NAS1/done',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      );

  Widget _tmdbCard(BuildContext context, AppLocalizations l10n) => _card(
        context,
        icon: Icons.local_movies_outlined,
        title: l10n.tmdb_section,
        hint: l10n.tmdb_section_hint,
        children: [
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
          Text(
            l10n.tmdb_attribution,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      );

  /// Carte d'un service : en-tete puis champs, separes d'un espacement egal.
  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String hint,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

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

  Widget _warning(BuildContext context, String message) => Row(
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
      );

  Widget _testButton(
    BuildContext context,
    String label,
    _TestState state,
    Future<void> Function() onPressed,
  ) =>
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: state == _TestState.running ? null : onPressed,
          icon: switch (state) {
            _TestState.running => const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            _TestState.ok => const Icon(Icons.check_circle, color: Colors.green),
            _TestState.failed => Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            _TestState.idle => const Icon(Icons.network_check),
          },
          label: Text(label),
        ),
      );

  Widget _testFeedback(BuildContext context, String message, _TestState state) => Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: state == _TestState.ok ? Colors.green : Theme.of(context).colorScheme.error,
            ),
      );
}
