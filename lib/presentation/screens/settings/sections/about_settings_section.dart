import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';

import '../../../../core/constants/app_version.dart';
import '../../../../core/services/diagnostic_log_export_service.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../widgets/settings_card.dart';
import '../widgets/settings_page_layout.dart';

/// 关于设置板块
///
/// 显示应用信息和版本号。
class AboutSettingsSection extends ConsumerStatefulWidget {
  const AboutSettingsSection({super.key});

  @override
  ConsumerState<AboutSettingsSection> createState() =>
      _AboutSettingsSectionState();
}

class _AboutSettingsSectionState extends ConsumerState<AboutSettingsSection> {
  bool _isExportingLogs = false;

  @override
  Widget build(BuildContext context) {
    final localStorageService = ref.watch(localStorageServiceProvider);
    final fileLoggingEnabled = localStorageService.getFileLoggingEnabled();

    return SettingsPageLayout(
      title: context.l10n.settings_about,
      children: [
        SettingsCard(
          title: context.l10n.settings_aboutApplicationSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(context.l10n.app_title),
                subtitle: Text(
                  context.l10n.settings_version(AppVersion.versionName),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.article_outlined),
                title: Text(context.l10n.settings_fileLogging),
                subtitle: Text(context.l10n.settings_fileLoggingSubtitle),
                value: fileLoggingEnabled,
                onChanged: (value) async {
                  await AppLogger.setFileLoggingEnabled(value);
                  await localStorageService.setFileLoggingEnabled(
                    AppLogger.fileLoggingEnabled,
                  );
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
              ListTile(
                key: const ValueKey('export-diagnostic-logs'),
                leading: const Icon(Icons.file_download_outlined),
                title: Text(context.l10n.settings_exportDiagnosticLogs),
                subtitle: Text(
                  context.l10n.settings_exportDiagnosticLogsSubtitle,
                ),
                trailing: _isExportingLogs
                    ? Semantics(
                        liveRegion: true,
                        label: context
                            .l10n
                            .settings_exportDiagnosticLogsInProgress,
                        child: const ExcludeSemantics(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _isExportingLogs ? null : _exportDiagnosticLogs,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportDiagnosticLogs() async {
    setState(() => _isExportingLogs = true);
    try {
      final result = await ref
          .read(diagnosticLogExportServiceProvider)
          .export(dialogTitle: context.l10n.settings_exportDiagnosticLogs);
      if (!mounted || result.status == DiagnosticLogExportStatus.cancelled) {
        return;
      }
      final message = switch (result.status) {
        DiagnosticLogExportStatus.exported =>
          context.l10n.settings_exportDiagnosticLogsSuccess,
        DiagnosticLogExportStatus.noLogs =>
          context.l10n.settings_exportDiagnosticLogsEmpty,
        DiagnosticLogExportStatus.cancelled => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        'Failed to export diagnostic logs',
        error,
        stackTrace,
        'Diagnostics',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.settings_exportDiagnosticLogsFailed),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingLogs = false);
      }
    }
  }
}
