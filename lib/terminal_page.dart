import 'package:code_lfa/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';
import 'terminal_controller.dart';
import 'terminal_theme.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  HomeController controller = Get.put(HomeController());
  ManjaroTerminalTheme terminalTheme = ManjaroTerminalTheme();
  bool visible = false || kDebugMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: visible
          ? terminalTheme.background
          : Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              controller.pseudoTerminal?.writeString('\x03');
            }
          },
          canPop: true,
          child: GestureDetector(
            onTap: () {
              visible = !visible;
              setState(() {});
            },
            behavior: HitTestBehavior.translucent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Visibility(
                    visible: visible,
                    child: AbsorbPointer(
                      absorbing: false,
                      child: TerminalView(
                        controller.terminal,
                        readOnly: false,
                        backgroundOpacity: 1,
                        theme: ManjaroTerminalTheme(),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Material(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Theme.of(context).colorScheme.surface,
                    child: SizedBox(
                      width: 300.0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Center(
                              child: RepaintBoundary(
                                child: LoadingProgress(
                                  minRadius: 6,
                                  strokeWidth: 3,
                                  increaseRadius: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12.0),
                            GetBuilder<HomeController>(
                              builder: (controller) {
                                return Column(
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          height: 5.0,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.02),
                                            borderRadius:
                                                BorderRadius.circular(3.0),
                                          ),
                                        ),
                                        AnimatedContainer(
                                          duration: 300.milliseconds,
                                          height: 5.0,
                                          width: 300.0 * controller.progress,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            borderRadius:
                                                BorderRadius.circular(3.0),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8.0),
                                    Text(
                                      controller.currentProgress.trim(),
                                      style: TextStyle(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
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
