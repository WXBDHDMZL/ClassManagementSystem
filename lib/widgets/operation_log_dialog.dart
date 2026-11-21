/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_theme.dart';
import '../constants/attendance_feature.dart';
import '../services/operation_log_service.dart';
import './record_list.dart';

/// 操作日志对话框：查看最近的数据操作记录（新增/删除/考勤/导入导出等），
/// 便于核对"某条数据什么时候被改动"。
class OperationLogDialog extends StatefulWidget {
  const OperationLogDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (context) => const OperationLogDialog(),
      );

  @override
  State<OperationLogDialog> createState() => _OperationLogDialogState();
}

class _OperationLogDialogState extends State<OperationLogDialog> {
  List<String> _lines = const [];
  String _path = '';
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<String> lines;
    String path;
    try {
      lines = await OperationLogService.recentLines();
      path = await OperationLogService.filePath();
    } catch (e) {
      // 读取失败（如文档目录被占用）也要退出加载态并给出提示，
      // 绝不能让界面永远停在转圈上。
      if (!mounted) return;
      setState(() {
        _lines = const [];
        _path = '';
        _loading = false;
        _loadError = '日志读取失败：$e';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _path = path;
      _loading = false;
      _loadError = null;
    });
  }

  Future<void> _copyAll() async {
    if (_lines.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (!mounted) return;
    showTopSnackBar(context, '已复制日志内容到剪贴板');
  }

  Future<void> _openLocation() async {
    // 修复（1.26）：日志读取失败时 _path 为空串，`lastIndexOf` 返回 -1 →
    // `substring(0, -1)` 抛 RangeError（用户只看到"打开失败"却不知原因）。
    if (_path.isEmpty) {
      showTopSnackBar(context, '日志文件路径不可用（可能是读取失败）', isError: true);
      return;
    }
    try {
      // 在资源管理器中选中日志文件；文件不存在时打开文档目录。
      final file = File(_path);
      if (await file.exists()) {
        await Process.start('explorer', ['/select,', _path]);
      } else {
        final directory = _path.substring(0, _path.lastIndexOf(RegExp(r'[/\\]')));
        await Process.start('explorer', [directory]);
      }
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, '打开日志位置失败：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.7);
    final screen = MediaQuery.of(context).size;
    final width = dialogWidthFor(screen);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: SizedBox(
        width: width,
        height: screen.height * 0.8,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.semantic.subtleBorder),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // 修复（6.10）：达到展示上限时明确告知，避免用户误以为
                      // "日志丢了"——完整内容可导出或打开文件位置查看。
                      _lines.length >= OperationLogService.displayLineLimit
                          ? '操作日志（仅显示最近 ${OperationLogService.displayLineLimit} 行）'
                          : '操作日志',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '刷新',
                    onPressed: _load,
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    tooltip: '打开日志文件位置',
                    onPressed: _openLocation,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '记录新增/修改/删除记录、${AttendanceFeature.enabled ? '考勤登记与撤销、' : ''}'
                    '名单与原因改动、导入导出、备份恢复等关键操作，全部保留，最近的在最上面。',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '文件：$_path',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  : _lines.isEmpty
                  ? Center(
                      child: Text(
                        '还没有操作日志（做一次增删改后就会出现在这里）',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    )
                  : Scrollbar(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _lines.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SelectableText(
                            _lines[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontFamily: 'Consolas',
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.semantic.subtleBorder),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _lines.isEmpty ? '暂无日志' : '共 ${_lines.length} 条（全量保留）',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyAll,
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: const Text('复制全部'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
