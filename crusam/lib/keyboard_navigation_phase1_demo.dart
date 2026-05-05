import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DemoApp());

class KeyboardNavigationController {
  KeyboardNavigationController(this.nodes);

  final List<FocusNode> nodes;

  int get _currentIndex => nodes.indexWhere((node) => node.hasFocus);

  void next() {
    final index = _currentIndex;
    if (index == -1 && nodes.isNotEmpty) {
      nodes.first.requestFocus();
    } else if (index >= 0 && index < nodes.length - 1) {
      nodes[index + 1].requestFocus();
    }
  }

  void previous() {
    final index = _currentIndex;
    if (index > 0) nodes[index - 1].requestFocus();
  }
}

class NextIntent extends Intent {
  const NextIntent();
}

class PreviousIntent extends Intent {
  const PreviousIntent();
}

class KeyboardNavigableForm extends StatelessWidget {
  const KeyboardNavigableForm({super.key, required this.controller, required this.child});

  final KeyboardNavigationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): NextIntent(),
          SingleActivator(LogicalKeyboardKey.enter, shift: true): PreviousIntent(),
        },
        child: Actions(
          actions: {
            NextIntent: CallbackAction<NextIntent>(onInvoke: (_) => controller.next()),
            PreviousIntent: CallbackAction<PreviousIntent>(onInvoke: (_) => controller.previous()),
          },
          child: Focus(autofocus: true, child: child),
        ),
      );
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final List<FocusNode> _nodes;
  late final KeyboardNavigationController _controller;

  @override
  void initState() {
    super.initState();
    _nodes = List.generate(4, (_) => FocusNode());
    _controller = KeyboardNavigationController(_nodes);
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Phase 1 Keyboard Navigation')),
          body: Center(
            child: SizedBox(
              width: 360,
              child: KeyboardNavigableForm(
                controller: _controller,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('Field 1', _nodes[0]),
                    _field('Field 2', _nodes[1]),
                    _field('Field 3', _nodes[2]),
                    _field('Field 4', _nodes[3]),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _field(String label, FocusNode focusNode) => Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}