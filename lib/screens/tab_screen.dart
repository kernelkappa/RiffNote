import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/instrument.dart';
import '../services/tab/alphatex_builder.dart';
import '../services/tab/chord_event.dart';

/// Renders a transcription as guitar/bass tab using AlphaTab, loaded fully
/// offline from bundled assets (brief: "tutto locale", no cloud) inside a
/// WebView — per the project brief's suggested stack (section 5).
class TabScreen extends StatefulWidget {
  const TabScreen({
    super.key,
    required this.events,
    required this.tuning,
    required this.title,
  });

  final List<ChordEvent> events;
  final StringTuning tuning;
  final String title;

  @override
  State<TabScreen> createState() => _TabScreenState();
}

class _TabScreenState extends State<TabScreen> {
  late final WebViewController _controller;
  late final AlphaTexBuildResult _build;
  String? _renderError;

  @override
  void initState() {
    super.initState();
    _build = AlphaTexBuilder.build(
      events: widget.events,
      tuning: widget.tuning,
      title: widget.title,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'RiffNoteAlphaTab',
        onMessageReceived: (message) {
          if (message.message.startsWith('error:') && mounted) {
            setState(() => _renderError = message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _renderTab(),
        ),
      )
      ..loadFlutterAsset('assets/alphatab/index.html');
  }

  void _renderTab() {
    final encoded = jsonEncode(_build.tex);
    _controller.runJavaScript('window.renderTex($encoded);');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tab')),
      body: Column(
        children: [
          if (_build.droppedNoteCount > 0)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text(
                '${_build.droppedNoteCount} nota/e omesse: fuori dalla portata '
                'dello strumento o non suonabili insieme alle altre.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          if (_renderError != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text(
                'Errore nel rendering: $_renderError',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
