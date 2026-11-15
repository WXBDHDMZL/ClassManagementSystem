/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.10.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 数据设置页（数据路径、导入导出、注意力阈值）。
class DataSettingsPage extends StatelessWidget {
  const DataSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final muted = mutedTextColor(theme, 0.65);
    final settings = provider.appData.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('导出路径'),
        Row(
          children: [
            Expanded(
              child: _SettingTextField(
                // 复查 3.4：改用 controller 封装（见文件末尾 _SettingTextField）——
                // 既不被"随值变化的 Key"吞掉输入，也能在外部改动（点「更改」
                // 选目录）后刷新输入框。
                value: settings.exportPath,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(
                    borderRadius: AppRadius.card,
                  ),
                  hintText: '请选择导出路径',
                  hintStyle: TextStyle(color: mutedTextColor(theme, 0.5)),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  fillColor: theme.colorScheme.surfaceContainer,
                  filled: true,
                ),
                style: TextStyle(color: theme.colorScheme.onSurface),
                readOnly: true,
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: '更改',
              onPressed: () async {
                final result = await FilePicker.platform.getDirectoryPath();
                if (result == null || !context.mounted) return;
                provider.setExportPath(result);
                showTopSnackBar(context, '已设置导出路径，导出时会直接保存到该目录');
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: settings.exportPath.isEmpty
                  ? null
                  : () {
                      provider.setExportPath('');
                      showTopSnackBar(context, '已清除导出路径，导出时会询问保存位置');
                    },
              child: Text(
                '清除',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const SettingsHint('记录与统计的 Excel、下方记录表格导出都会使用该目录；留空则在每次导出时手动选择保存位置。'),
        const SizedBox(height: 18),
        const SettingsSectionTitle('表格与数据包'),
        _categoryRow(
          theme,
          title: '记录',
          hint: '表格文件（Excel/CSV）',
          onExport: () => _exportAllRecords(context, provider),
          onImport: () => _importRecords(context, provider),
        ),
        const SizedBox(height: 10),
        _categoryRow(
          theme,
          title: '学生名单',
          hint: '可以合并或替换现有名单',
          onImport: () => _importStudents(context, provider),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(
                label: '导出数据包',
                onPressed: () => _exportPackage(context, provider),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsActionButton(
                label: '导入数据包',
                onPressed: () => _importPackage(context, provider),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SettingsHint(
          AttendanceFeature.enabled
              ? '数据包含记录、名单、原因库、时间段、考勤与考勤状态项，'
                  '换电脑时可直接整包导入（不含管理密码）。'
              : '数据包含记录、名单、原因库与时间段，'
                  '换电脑时可直接整包导入（不含管理密码）。',
        ),
        const SizedBox(height: 22),
        const SettingsSectionTitle('导出选项'),
        _SettingTextField(
          // 复查 3.4：同上，controller 自持输入 + 非聚焦时同步外部值。
          value: settings.exportFilePrefix,
          decoration: const InputDecoration(
            border: OutlineInputBorder(borderRadius: AppRadius.card),
            labelText: '导出文件名前缀（可留空）',
            hintText: '例如：五年3班_',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onSubmitted: (value) {
            provider.setExportOptions(filePrefix: value.trim());
            showTopSnackBar(context, '已保存导出文件名前缀');
          },
        ),
        const SizedBox(height: 6),
        const SettingsHint('设置后，导出的记录、统计等文件名都会带上该前缀（回车保存）。'),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            '高级导出选项',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            '当前导出 ${settings.recordExportColumns.length} 列；需要精简表格时再展开调整。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '记录导出的列',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in [
                    ...AppSettings.defaultRecordExportColumns,
                    'recordedBy',
                  ])
                    FilterChip(
                      label: Text(
                        AppSettings.recordExportColumnTitles[key] ?? key,
                      ),
                      selected: settings.recordExportColumns.contains(key),
                      onSelected: (selected) {
                        final next = List<String>.from(
                          settings.recordExportColumns,
                        );
                        if (selected) {
                          if (!next.contains(key)) next.add(key);
                        } else {
                          if (next.length <= 1) {
                            showTopSnackBar(context, '至少要保留一列', isError: true);
                            return;
                          }
                          next.remove(key);
                        }
                        provider.setExportOptions(recordColumns: next);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 分类操作行：标题 + 说明 + 导出/导入按钮。
  Widget _categoryRow(
    ThemeData theme, {
    required String title,
    required String hint,
    required VoidCallback onImport,
    VoidCallback? onExport,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              SettingsHint(hint),
            ],
          ),
        ),
        if (onExport != null) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onExport,
            child: Text(
              '导出',
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: onImport,
          child: Text(
            '导入',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}

/// 备份与恢复：备份位置、自动备份频率、立即备份与从备份恢复。

class _DataPathText extends StatefulWidget {
  final TextStyle? style;

  const _DataPathText({this.style});

  @override
  State<_DataPathText> createState() => _DataPathTextState();
}

class _DataPathTextState extends State<_DataPathText> {
  // 修复（审查 四-5）：路径查询改由 provider 注入 —— 此前这里直接
  // `StorageService()` 新建服务，绕过依赖注入，单测无法替换实现。
  Future<String>? _pathFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pathFuture ??= Provider.of<AppDataProvider>(
      context,
      listen: false,
    ).dataFilePath;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _pathFuture,
      builder: (context, snapshot) {
        return SelectableText(
          snapshot.hasData ? snapshot.data! : '正在读取…',
          style: widget.style,
        );
      },
    );
  }
}

/// 统计口径里的单个阈值滑块（"需关注学生"的周 / 月 / 学期三档共用）。
class _AttentionThresholdSlider extends StatefulWidget {
  const _AttentionThresholdSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_AttentionThresholdSlider> createState() =>
      _AttentionThresholdSliderState();
}

class _AttentionThresholdSliderState extends State<_AttentionThresholdSlider> {
  // 修复（审查四 G-38）：拖动过程中只更新本地预览值，松手（onChangeEnd）才提交
  // 并触发一次写盘与通知 —— 此前 onChanged 逐 tick 写 provider，一次拖动触发
  // 几十次全库写盘与全 Consumer 重建。
  late int _preview = widget.value;

  @override
  void didUpdateWidget(covariant _AttentionThresholdSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _preview = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: mutedTextColor(theme, 0.7),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _preview.toDouble(),
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                divisions: widget.max - widget.min,
                label: '$_preview 次',
                onChanged: (raw) => setState(() => _preview = raw.round()),
                onChangeEnd: (raw) => widget.onChanged(raw.round()),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '$_preview 次',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 设置页文本字段（V2.30.3，复查 3.4）。
///
/// 为什么不用 `initialValue`：
///   · Key 随值变化 → 用户输入后（未回车）任何 rebuild 都会销毁重建字段、
///     回填旧值，刚打的字凭空消失；
///   · 去掉 Key → `FormFieldState` 只在首帧取一次 `initialValue`，**外部改动
///     （点「更改」选目录）不再刷新输入框**，用户以为没设上。
/// 这里两者都避开：controller 自持用户输入；外部值变化时只在字段**未聚焦**
/// 的情况下同步 —— 用户正在打字时绝不打断。
class _SettingTextField extends StatefulWidget {
  const _SettingTextField({
    required this.value,
    required this.decoration,
    this.style,
    this.readOnly = false,
    this.onSubmitted,
  });

  final String value;
  final InputDecoration decoration;
  final TextStyle? style;
  final bool readOnly;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_SettingTextField> createState() => _SettingTextFieldState();
}

class _SettingTextFieldState extends State<_SettingTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _SettingTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      readOnly: widget.readOnly,
      style: widget.style,
      decoration: widget.decoration,
      onSubmitted: widget.onSubmitted,
    );
  }
}
