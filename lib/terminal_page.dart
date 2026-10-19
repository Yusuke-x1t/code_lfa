import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';

import 'terminal_controller.dart';
import 'terminal_theme.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final HomeController controller = Get.put(HomeController());
  final ManjaroTerminalTheme terminalTheme = ManjaroTerminalTheme();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: terminalTheme.background,
      body: SafeArea(
        child: PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              controller.pseudoTerminal?.writeString('\x03');
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: TerminalView(
                  controller.terminal,
                  readOnly: false,
                  backgroundOpacity: 1,
                  theme: terminalTheme,
                ),
              ),
              GetBuilder<HomeController>(
                builder: (controller) {
                  if (controller.webviewHasOpen) {
                    return const SizedBox.shrink();
                  }

                  final double progress =
                      controller.progress.clamp(0.0, 1.0).toDouble();

                  final String description =
                      controller.currentProgress.trim().isEmpty
                          ? 'Preparando el entorno...'
                          : controller.currentProgress.trim();

                  return Center(
                    child: Material(
                      elevation: 8,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 300,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LoadingProgress(
                                minRadius: 6,
                                strokeWidth: 3,
                                increaseRadius: 3,
                              ),
                              const SizedBox(height: 14),
                              Stack(
                                children: [
                                  Container(
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                    height: 6,
                                    width: 270 * progress,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(progress * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
