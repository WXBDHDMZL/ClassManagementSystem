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

import 'package:flutter/material.dart';

import '../constants/app_version.dart';
import '../constants/app_theme.dart';

/// 公开源码的展示文字：仓库未公开时回退为邮件获取。
final String _sourceOffer = AppVersion.sourceCodeUrl.isEmpty
    ? '当前可通过 ${AppVersion.contactEmail} 联系作者获取对应源代码；该获取方式自本版本发布之日起至少三年内有效。'
    : AppVersion.sourceCodeUrl;

/// 开源许可与使用说明（AGPL-3.0-only）。
///
/// 这里只说明许可证、源码获取方式与数据隐私，不再使用限制复制、修改或
/// 商业使用的专有软件条款；完整法律文本以根目录 `LICENSE.txt` 为准。
final String _licenseText = '''程序版本：${AppVersion.version}｜许可证：AGPL-3.0-only
版权所有 © 2026 WXBDHDMZL

**一、许可证**

1. 本程序以 **GNU Affero General Public License version 3 only（AGPL-3.0-only）** 发布。
2. 你可以自由使用、研究、修改和再分发本程序；**商业使用也是允许的**。
3. 如果你分发修改后的程序，必须按 AGPL 第 6 条向接收者提供对应源代码；如果你修改程序并让它通过网络向用户提供服务，必须按 AGPL 第 13 条向这些用户提供对应源代码。
4. 本程序按“现状”提供，不提供任何明示或默示担保；责任限制以 AGPL 第 15、16 条为准。
5. 完整许可证文本见安装目录的 `LICENSE.txt`，也可访问 https://www.gnu.org/licenses/agpl-3.0.html。

**二、源码获取**

$_sourceOffer

**三、数据与隐私**

1. 记录、名单与设置只保存在本机 `文档\\班级管理系统\\`，程序不收集、不上传班级数据。
2. 天气功能会向 Open-Meteo、Photon 发送所选地区名称或坐标，不包含学生姓名、记录或名单。
3. 操作日志与错误日志在本机加密保存，但日志中的操作描述可能包含学生姓名；请勿把日志、数据文件或备份转发给无关人员。
4. 换电脑、重装系统或卸载前，请自行备份数据；本程序不提供云端同步或远程恢复。

**四、第三方组件**

本程序使用 Flutter 及若干开源依赖，其许可证可在“关于 → 开源组件许可”中查看。依赖均为 MIT、BSD 或 Apache-2.0 等与 AGPL 兼容的许可证。

**五、联系方式**

作者：WXBDHDMZL
邮箱：${AppVersion.contactEmail}''';

/// 开源许可与使用说明对话框。
class TermsOfServiceDialog extends StatelessWidget {
  const TermsOfServiceDialog({super.key});

  /// 把 `**加粗**` 标记解析为文本片段：按 `**` 切分，下标为奇数的片段加粗。
  static List<TextSpan> _buildTermSpans(String text, TextStyle base) {
    final parts = text.split('**');
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(
        TextSpan(
          text: parts[i],
          style: i.isOdd ? base.copyWith(fontWeight: FontWeight.bold) : base,
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.6,
    );

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      child: Container(
        width: clampDialogWidth(MediaQuery.sizeOf(context), 500),
        height: clampDialogHeight(MediaQuery.sizeOf(context), 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Text(
                '开源许可与使用说明',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text.rich(
                  TextSpan(children: _buildTermSpans(_licenseText, baseStyle)),
                  style: baseStyle,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.sheet,
                    ),
                  ),
                  child: const Text('我已了解'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
