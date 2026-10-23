import 'dart:async';
import 'package:flutter/material.dart';

/// Host availability is confirmed by IPC, never by a successful button click.
class ServiceStatusCard extends StatefulWidget {
  const ServiceStatusCard(
      {super.key,
      required this.stopped,
      required this.connected,
      required this.online,
      required this.onStart,
      required this.text});

  final bool stopped;
  final bool? connected;
  final bool online;
  final Future<void> Function() onStart;
  final String Function(String) text;

  @override
  State<ServiceStatusCard> createState() => _ServiceStatusCardState();
}

class _ServiceStatusCardState extends State<ServiceStatusCard> {
  bool _starting = false;
  bool _failed = false;
  Timer? _deadline;

  @override
  void didUpdateWidget(covariant ServiceStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected == true && !widget.stopped) {
      _deadline?.cancel();
      _starting = false;
      _failed = false;
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _failed = false;
    });
    _deadline = Timer(const Duration(seconds: 20), _fail);
    try {
      await widget.onStart();
      // Keep the pending state until a subsequent IPC poll confirms the host.
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    _deadline?.cancel();
    if (mounted && _starting) {
      setState(() {
        _starting = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _deadline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = widget.stopped || widget.connected == false;
    final ready = !unavailable && widget.connected == true && widget.online;
    final checking = widget.connected == null && !widget.stopped;
    final title = _starting
        ? 'Starting support service…'
        : unavailable
            ? 'Connections unavailable'
            : ready
                ? 'Ready for support'
                : 'Waiting for connection';
    final detail = _failed
        ? 'Service did not start. Confirm the system permission prompt and try again.'
        : _starting
            ? 'Confirm the system permission prompt if it appears.'
            : unavailable
                ? 'The app is open, but support cannot connect. Enable the service below.'
                : ready
                    ? 'Share your ID with support. Connection still requires your approval or password.'
                    : checking
                        ? 'Checking the support service…'
                        : 'Service is running, but the server is not connected yet. Check your internet connection.';
    final color = ready ? Colors.teal : Colors.orange;
    final t = widget.text;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ready ? Icons.check_circle_outline : Icons.info_outline,
              color: color),
          const SizedBox(height: 8),
          Text(t(title),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t(detail)),
          if (unavailable || _starting) ...[
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.power_settings_new),
                  label: Text(
                      t(_starting ? 'Starting…' : 'Enable support service')),
                )),
          ],
        ]),
      ),
    );
  }
}
