import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/instrument.dart';
import '../models/recording.dart';
import '../services/basic_pitch/basic_pitch_service.dart';
import '../services/tab/alphatex_builder.dart';
import '../services/tab/chord_event.dart';
import '../services/tab/string_fret_assigner.dart';

/// Transcribes a recording and renders it as real music notation (plus tab,
/// for guitar/bass) via AlphaTab — the primary, and only, way to view a
/// transcription.
///
/// There used to be an intermediate plain-text note list here. It did its
/// job validating Basic Pitch's on-device quality (brief section 12.2) but
/// doesn't scale to anything longer than a few notes, and real notation
/// (which AlphaTab already gives us "for free") is strictly more useful to
/// an actual musician — so it's gone from the user-facing flow.
class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key, required this.recording, required this.instrument});

  final Recording recording;
  final Instrument instrument;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  final _service = BasicPitchService();
  late final WebViewController _controller;
  late final Future<AlphaTexBuildResult> _buildFuture;

  bool _pageReady = false;
  AlphaTexBuildResult? _pendingResult;
  String? _renderError;

  @override
  void initState() {
    super.initState();

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
          onPageFinished: (_) {
            _pageReady = true;
            _maybeRender();
          },
        ),
      )
      ..loadFlutterAsset('assets/alphatab/index.html');

    _buildFuture = _transcribeAndBuild();
  }

  Future<AlphaTexBuildResult> _transcribeAndBuild() async {
    final notes = await _service.transcribeFile(widget.recording.file);
    final events = groupIntoChordEvents(notes);

    final tuning = StringTuning.forInstrument(widget.instrument);
    final AlphaTexBuildResult result;
    if (tuning != null) {
      StringFretAssigner(tuning).assign(events);
      result = AlphaTexBuilder.buildStringed(
        events: events,
        tuning: tuning,
        title: widget.instrument.label,
      );
    } else {
      result = AlphaTexBuilder.buildPitched(
        events: events,
        instrument: widget.instrument,
        title: widget.instrument.label,
      );
    }

    _pendingResult = result;
    _maybeRender();
    return result;
  }

  void _maybeRender() {
    final result = _pendingResult;
    if (_pageReady && result != null) {
      _controller.runJavaScript('window.renderTex(${jsonEncode(result.tex)});');
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spartito · ${widget.instrument.label}')),
      body: FutureBuilder<AlphaTexBuildResult>(
        future: _buildFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Trascrizione in corso (Basic Pitch on-device)...'),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Trascrizione non riuscita:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final result = snapshot.data!;
          return Column(
            children: [
              if (result.droppedNoteCount > 0)
                _Banner(
                  '${result.droppedNoteCount} nota/e omesse: fuori dalla portata '
                  'dello strumento o non suonabili insieme alle altre.',
                ),
              if (result.outOfRangeCount > 0)
                _Banner(
                  '${result.outOfRangeCount} nota/e fuori dall\'estensione tipica '
                  'di questo strumento (mostrate comunque: controllale).',
                ),
              if (_renderError != null) _Banner('Errore nel rendering: $_renderError'),
              Expanded(child: WebViewWidget(controller: _controller)),
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
