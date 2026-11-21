/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

// 通用"单行/多行文本输入"对话框（V2.30.5，审查报告 四-4 / 五-5）。
//
// 为什么必须是 StatefulWidget（而不是"外部建 controller + await 后 dispose"）：
//   `await showDialog(...)` 在路由被 pop 时**立刻返回**，而对话框退场动画还要跑
//   约 200ms；这期间若发生重建（主题/MediaQuery 变化），输入框会用到**已经释放的
//   controller** → 触发断言或崩溃。项目在 V2.27.7 已经为密码框修过这个 bug，
//   这里把同一修法推广到其它输入对话框，并把散落的重复实现收拢到一处。
//
// 用法：`final text = await showTextPrompt(context, title: '…', label: '…');`

import 'package:flutter/material.dart';

class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    this.label = '名称',
    this.initialValue = '',
    this.maxLines = 1,
    this.hintText,
    this.helperText,
    this.confirmLabel = '确定',
  });

  final String title;
  final String label;
  final String initialValue;
  final int maxLines;
  final String? hintText;
  final String? helperText;
  final String confirmLabel;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    // 由对话框自己持有并释放 —— 退场动画期间的重建不会碰到已释放的控制器。
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiline = widget.maxLines > 1;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: multiline ? 520 : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.helperText != null) ...[
              Text(
                widget.helperText!,
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: multiline ? widget.maxLines : null,
              maxLines: multiline ? widget.maxLines + 4 : 1,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hintText,
                border: const OutlineInputBorder(),
              ),
              // 单行时回车即确认；多行时回车用于换行。
              onSubmitted: multiline
                  ? null
                  : (value) => Navigator.pop(context, value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 便捷入口：弹出输入框，返回输入内容（取消返回 null）。
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String label = '名称',
  String initialValue = '',
  int maxLines = 1,
  String? hintText,
  String? helperText,
  String confirmLabel = '确定',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => TextPromptDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      maxLines: maxLines,
      hintText: hintText,
      helperText: helperText,
      confirmLabel: confirmLabel,
    ),
  );
}
