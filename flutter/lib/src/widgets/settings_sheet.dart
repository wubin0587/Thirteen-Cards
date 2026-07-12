import 'package:flutter/material.dart';

import '../backend/app_settings.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// 设置面板 — 玩家昵称 / AI 难度 / 音效 / 语言。
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _nameCtrl;
  late double _difficulty;
  late bool _soundEnabled;
  late String _locale;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: AppSettings.playerName);
    _difficulty = AppSettings.difficulty;
    _soundEnabled = AppSettings.soundEnabled;
    _locale = AppSettings.locale;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTextTokens.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题 + 关闭
          Row(
            children: [
              Icon(Icons.settings_rounded,
                  color: AppColors.gold, size: 28),
              const SizedBox(width: 10),
              Text('游戏设置',
                  style: TextStyle(
                      fontSize: text.lg, fontWeight: FontWeight.w900)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                color: AppColors.dim,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 玩家昵称
          Text('玩家昵称',
              style: TextStyle(
                  fontSize: text.sm,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLength: 8,
            style: TextStyle(fontSize: text.md, color: AppColors.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: '输入昵称',
              hintStyle: TextStyle(color: AppColors.dim),
              filled: true,
              fillColor: AppColors.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),

          // AI 难度
          Text('AI 难度',
              style: TextStyle(
                  fontSize: text.sm,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _buildDifficultyChips(),
          const SizedBox(height: 20),

          // 音效
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('音效播报',
                style: TextStyle(
                    fontSize: text.sm,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700)),
            value: _soundEnabled,
            activeColor: AppColors.gold,
            onChanged: (v) => setState(() => _soundEnabled = v),
          ),
          const SizedBox(height: 8),

          // 语言
          Text('语言',
              style: TextStyle(
                  fontSize: text.sm,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'zh', label: Text('中文')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {_locale},
            onSelectionChanged: (v) => setState(() => _locale = v.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? AppColors.ink : AppColors.text),
              backgroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? AppColors.gold : AppColors.panel),
            ),
          ),
          const SizedBox(height: 28),

          // 保存按钮
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.ink,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('保存设置',
                style: TextStyle(
                    fontSize: text.md, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyChips() {
    const levels = [
      (label: '简单', value: 1.0),
      (label: '中等', value: 0.55),
      (label: '困难', value: 0.0),
    ];

    return SegmentedButton<double>(
      segments: [
        for (final l in levels) ButtonSegment(value: l.value, label: Text(l.label)),
      ],
      selected: {_difficulty},
      onSelectionChanged: (v) => setState(() => _difficulty = v.first),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.ink : AppColors.text),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.gold : AppColors.panel),
      ),
    );
  }

  void _save() {
    AppSettings.playerName = _nameCtrl.text.trim().isEmpty
        ? '玩家'
        : _nameCtrl.text.trim();
    AppSettings.difficulty = _difficulty;
    AppSettings.soundEnabled = _soundEnabled;
    if (_locale != AppSettings.locale) {
      AppSettings.locale = _locale;
      AppStrings.setLocale(_locale);
    }
    AppSettings.saveToDisk();
    Navigator.pop(context);
  }
}
