/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../app_data_provider.dart';

/// AppDataProvider——设置域（外观/窗口/行为/导出选项等全部 set* 方法与天气开关）。
///
/// `_ProviderBase` 的一个功能域（mixin 方法就是真正的类成员，
/// 可跨域调用、触发 notifyListeners；on 同 library 基类，其
/// 私有成员在此直接可见）。
mixin _SettingsDomain on _ProviderBase {
  void setThemeMode(ThemeModeType mode) {
    _appData.settings = _appData.settings.copyWith(themeMode: mode);
    _log('外观设置', '主题模式改为 $mode');
    _save();
  }

  void setExportPath(String path) {
    _appData.settings = _appData.settings.copyWith(exportPath: path);
    _log('导出设置', '默认导出目录改为 $path');
    _save();
  }

  /// 设置关闭窗口时的行为（每次询问 / 直接退出 / 最小化到托盘 / 最小化到悬浮球）。
  void setCloseAction(CloseActionType action) {
    _appData.settings = _appData.settings.copyWith(closeAction: action);
    _log('窗口设置', '关闭按钮行为改为 $action');
    _save();
  }

  /// 记录悬浮球停留位置（屏幕物理像素），供下次进入球模式时恢复。
  void setBallPosition(int x, int y) {
    if (_appData.settings.ballX == x && _appData.settings.ballY == y) return;
    _appData.settings = _appData.settings.copyWith(ballX: x, ballY: y);
    _log('悬浮球', '位置移动到 $x, $y');
    _save();
  }

  /// 保存管理密码哈希（空字符串表示恢复出厂默认密码）。
  ///
  /// 审计 A-19：返回是否已真正落盘。密码改动是安全相关写入，
  /// 调用方必须等到结果再提示成功，否则断电/写盘失败会让用户
  /// 以为密码已改，重启后仍是旧密码。
  Future<bool> setPasswordHash(String hash) async {
    // 修复（审计 M1）：provider 方法也必须校验，不能只靠设置页 UI。
    // 使用出厂默认密码（哈希为空）时允许首次改密，否则要求管理会话。
    if (_appData.settings.passwordEnabled &&
        _appData.settings.passwordHash.isNotEmpty &&
        !_canManageSecuritySettings) {
      _log('密码设置', '拒绝未授权的管理密码哈希修改');
      return false;
    }
    _appData.settings = _appData.settings.copyWith(passwordHash: hash);
    _log('密码设置', hash.isEmpty ? '清除管理密码' : '设置/修改管理密码');
    final saved = await saveNow();
    if (!saved) {
      _log('密码设置', '管理密码写入失败，本次修改未落盘');
    }
    return saved;
  }

  /// 设置/重新生成恢复码：只保存加盐哈希与创建日期，不保存明文。
  Future<void> setRecoveryCode(String code) async {
    if (!_canManageSecuritySettings) {
      _log('密码设置', '拒绝未授权的恢复码修改');
      return;
    }
    final normalized = SecurityService.normalizeRecoveryCode(code);
    if (normalized.isEmpty) return;
    final hash = await SecurityService.hashPasswordAsync(normalized);
    _appData.settings = _appData.settings.copyWith(
      recoveryCodeHash: hash,
      recoveryCodeCreatedAt: _getTodayString(),
    );
    _log('密码设置', '已生成/更新恢复码');
    _save();
  }

  /// 关闭恢复码（不影响力管理密码）。
  void clearRecoveryCode() {
    if (!_canManageSecuritySettings) {
      _log('密码设置', '拒绝未授权的恢复码关闭');
      return;
    }
    _appData.settings = _appData.settings.copyWith(
      recoveryCodeHash: '',
      recoveryCodeCreatedAt: '',
    );
    _log('密码设置', '已关闭恢复码');
    _save();
  }

  /// 用恢复码验证成功后：把管理密码重置为 [newPassword]，
  /// 同时作废恢复码并清除锁定；返回是否成功落盘。
  Future<bool> resetPasswordsWithRecoveryCode(
    String newPassword, {
    required String recoveryCode,
  }) async {
    // 安全审计 M1：不能只靠 UI 先验一次恢复码；provider 自己必须再验。
    final normalized = SecurityService.normalizeRecoveryCode(recoveryCode);
    if (normalized.isEmpty) {
      _log('密码设置', '拒绝无恢复码的密码重置');
      return false;
    }
    final verified = await AuthService.verify(
      _appData.settings,
      AuthCredential.recoveryCode,
      normalized,
    );
    if (!verified.success) {
      _log('密码设置', '拒绝恢复码校验失败的密码重置');
      return false;
    }
    final hash = await SecurityService.hashPasswordAsync(newPassword);
    final previousSettings = _appData.settings;
    _appData.settings = _appData.settings.copyWith(
      passwordEnabled: true,
      passwordHash: hash,
      // 恢复码一次性：用后立即作废，避免明文码长期留在用户手里。
      recoveryCodeHash: '',
      recoveryCodeCreatedAt: '',
    );
    await AuthService.clearAllLocks();
    final saved = await saveNow();
    if (!saved) {
      // 落盘失败时回滚内存，避免“界面显示已重置但重启后又是旧密码”。
      _appData.settings = previousSettings;
      _save();
      return false;
    }
    _log('密码设置', '已通过恢复码重置管理密码（恢复码已作废）');
    return true;
  }

  /// 保存完整的自定义时段列表（可增删）并立即生效；空列表表示恢复出厂时段。
  void setPeriods(List<Map<String, String>> periods) {
    if (!_authorizedFor('periods', action: PasswordAction.periodModify)) {
      return;
    }
    // G-9/G-19：深拷贝 + 与运行时同一口径过滤后再落库 —— 此前直接把外部 List
    // 存进 settings（调用方后续改写会污染内部状态），且存的是**未过滤**的原始
    // 列表（落盘与运行时口径不一致）。
    final clean = sanitizePeriods(periods);
    _appData.settings = _appData.settings.copyWith(
      periods: clean,
    );
    applyCustomPeriods(clean);
    _log('时间段设置', clean.isEmpty ? '恢复出厂时段' : '自定义时段 ${clean.length} 段');
    _save();
  }

  /// 设置启动时的窗口状态（记住上次 / 默认大小 / 启动即最大化）。
  void setStartupWindowMode(StartupWindowMode mode) {
    _appData.settings = _appData.settings.copyWith(startupWindowMode: mode);
    _log('窗口设置', '启动时窗口状态改为 $mode');
    _save();
  }

  /// 记录退出时的窗口大小与位置，供下次启动还原。
  void setWindowBounds(
    int x,
    int y,
    int width,
    int height, {
    required bool maximized,
  }) {
    _appData.settings = _appData.settings.copyWith(
      windowX: x,
      windowY: y,
      windowWidth: width,
      windowHeight: height,
      windowMaximized: maximized,
    );
    _log(
      '窗口设置',
      '退出前记录窗口位置 x=$x y=$y 大小 $width×$height${maximized ? '（最大化）' : ''}',
    );
    _save();
  }

  /// 界面与行为相关的自定义项（字号、启用类型、原因排序、导出选项等）。
  void setUiScale(double scale) {
    if (scale < 0.85 || scale > 1.3) return;
    _appData.settings = _appData.settings.copyWith(uiScale: scale);
    _log('外观设置', '界面字号缩放改为 $scale');
    _save();
  }

  /// 开机自动启动（由 DesktopService 写入/移除系统启动项后调用本方法记录状态）。
  void setAutoStart(bool enabled) {
    _appData.settings = _appData.settings.copyWith(autoStart: enabled);
    _log('启动项', enabled ? '开启开机自动启动' : '关闭开机自动启动');
    _save();
  }

  /// 开机自启动后进入托盘还是悬浮球（autoStart 开启时由设置页同时重写注册表）。
  void setStartupTarget(StartupTarget target) {
    if (_appData.settings.startupTarget == target) return;
    _appData.settings = _appData.settings.copyWith(startupTarget: target);
    _log('启动项', '开机启动目标改为${target == StartupTarget.ball ? '悬浮球' : '托盘'}');
    _save();
  }

  // -------------------- 操作身份 --------------------

  void setIdentityFeatureEnabled(bool enabled) {
    if (!_canManageSecuritySettings) {
      _log('操作身份', '拒绝未授权的身份功能开关修改');
      return;
    }
    final settings = _appData.settings;
    if (settings.identityFeatureEnabled == enabled) return;
    _appData.settings = settings.copyWith(identityFeatureEnabled: enabled);
    _log('操作身份', enabled ? '启用操作身份' : '关闭操作身份');
    _save();
    _syncIdentitySession();
  }

  void setIdentityIdleMinutes(int minutes) {
    if (!_canManageSecuritySettings) {
      _log('操作身份', '拒绝未授权的身份闲置设置修改');
      return;
    }
    if (!AppSettings.identityIdleMinuteOptions.contains(minutes)) return;
    final settings = _appData.settings;
    if (settings.identityIdleMinutes == minutes) return;
    _appData.settings = settings.copyWith(identityIdleMinutes: minutes);
    _log('操作身份', minutes == 0 ? '关闭闲置自动退出' : '非班主任身份闲置 $minutes 分钟自动退出');
    _save();
    _syncIdentitySession();
  }

  void setManagementSessionMinutes(int minutes) {
    if (!_canManageSecuritySettings) {
      _log('操作身份', '拒绝未授权的管理会话时长修改');
      return;
    }
    if (!AppSettings.managementSessionMinuteOptions.contains(minutes)) return;
    final settings = _appData.settings;
    if (settings.managementSessionMinutes == minutes) return;
    _appData.settings =
        settings.copyWith(managementSessionMinutes: minutes);
    _log('操作身份', '班主任管理保持 $minutes 分钟');
    _save();
    notifyListeners();
  }

  void setSelfEditWindowMinutes(int minutes) {
    if (!_canManageSecuritySettings) {
      _log('操作身份', '拒绝未授权的本人编辑窗口修改');
      return;
    }
    if (!AppSettings.selfEditWindowMinuteOptions.contains(minutes)) return;
    final settings = _appData.settings;
    if (settings.selfEditWindowMinutes == minutes) return;
    _appData.settings = settings.copyWith(selfEditWindowMinutes: minutes);
    _log(
      '操作身份',
      minutes == 0 ? '关闭本人编辑窗口' : '本人编辑窗口 $minutes 分钟',
    );
    _save();
    notifyListeners();
  }

  /// 新增自定义身份，返回新身份；名称为空时返回 null。
  Identity? addIdentity({
    required String name,
    String nickname = '',
    required IdentityKind kind,
    bool allowSelfEdit = true,
    bool allowAddRecord = true,
    bool allowAttendanceRegister = true,
  }) {
    if (!_canManageSecuritySettings) {
      _log('操作身份', '拒绝未授权的新增身份');
      return null;
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;
    final settings = _appData.settings;
    var id = 'identity_${DateTime.now().microsecondsSinceEpoch}';
    var suffix = 0;
    while (settings.identities.any((identity) => identity.id == id)) {
      id = 'identity_${DateTime.now().microsecondsSinceEpoch}_${suffix++}';
    }
    final identity = Identity(
      id: id,
      name: trimmedName,
      nickname: nickname.trim(),
      kind: kind,
      allowSelfEdit: allowSelfEdit,
      allowAddRecord: allowAddRecord,
      allowAttendanceRegister: allowAttendanceRegister,
    );
    _appData.settings = settings.copyWith(
      identities: [...settings.identities, identity],
    );
    _log('操作身份', '新增身份 ${identity.displayLabel}');
    _save();
    _syncIdentitySession();
    return identity;
  }

  /// 修改身份名称/昵称/类别；班主任只能修改昵称，不能改名或换类别。
  bool updateIdentity(
    String id, {
    String? name,
    String? nickname,
    IdentityKind? kind,
    bool? allowSelfEdit,
    bool? allowAddRecord,
    bool? allowAttendanceRegister,
  }) {
    if (!_canManageSecuritySettings) {
      _log('操作身份', '拒绝未授权的身份修改');
      return false;
    }
    final settings = _appData.settings;
    final index = settings.identities.indexWhere(
      (identity) => identity.id == id,
    );
    if (index < 0) return false;
    final current = settings.identities[index];
    final nextName = current.isHeadTeacher
        ? current.name
        : (name ?? current.name).trim();
    if (nextName.isEmpty) return false;
    final next = current.copyWith(
      name: nextName,
      nickname: nickname?.trim() ?? current.nickname,
      kind: current.isHeadTeacher ? current.kind : (kind ?? current.kind),
      allowSelfEdit: allowSelfEdit ?? current.allowSelfEdit,
      allowAddRecord: allowAddRecord ?? current.allowAddRecord,
      allowAttendanceRegister:
          allowAttendanceRegister ?? current.allowAttendanceRegister,
    );
    final identities = List<Identity>.from(settings.identities);
    identities[index] = next;
    _appData.settings = settings.copyWith(identities: identities);
    _log('操作身份', '修改身份 ${next.displayLabel}');
    _save();
    _syncIdentitySession();
    return true;
  }

  /// 删除身份；班主任受保护不可删除。
  bool deleteIdentity(String id) {
    if (!_canManageSecuritySettings) {
      _log('操作身份', '拒绝未授权的身份删除');
      return false;
    }
    final settings = _appData.settings;
    final target = settings.identities.where((identity) => identity.id == id);
    if (target.isEmpty || target.first.isHeadTeacher) return false;
    _appData.settings = settings.copyWith(
      identities: [
        for (final identity in settings.identities)
          if (identity.id != id) identity,
      ],
    );
    if (_activeIdentityId == id) {
      _activeIdentityId = null;
    }
    _log('操作身份', '删除身份 ${target.first.displayLabel}');
    _save();
    _syncIdentitySession();
    return true;
  }

  /// 表扬/批评是否启用；两者不能同时关闭（至少保留一个）。
  void setRecordTypesEnabled({bool? praise, bool? criticism}) {
    final nextPraise = praise ?? _appData.settings.praiseEnabled;
    final nextCriticism = criticism ?? _appData.settings.criticismEnabled;
    if (!nextPraise && !nextCriticism) return;

    // 默认类型被停用时同步切换到仍启用的类型，避免摘要显示
    // “默认表扬”但记录对话框实际回退到批评。
    final currentDefault = _appData.settings.recordDefaultType;
    var nextDefault = currentDefault;
    if (currentDefault == 0 && !nextPraise) {
      nextDefault = 1;
    } else if (currentDefault == 1 && !nextCriticism) {
      nextDefault = 0;
    }

    _appData.settings = _appData.settings.copyWith(
      praiseEnabled: nextPraise,
      criticismEnabled: nextCriticism,
      recordDefaultType: nextDefault,
    );
    _log(
      '记录类型',
      '表扬${nextPraise ? '启用' : '停用'} · 批评${nextCriticism ? '启用' : '停用'}'
      '${nextDefault != currentDefault ? ' · 默认类型自动切换' : ''}',
    );
    _save();
  }

  /// 原因是否按使用频率排序。
  void setReasonSortByUsage(bool enabled) {
    _appData.settings = _appData.settings.copyWith(reasonSortByUsage: enabled);
    _log('记录设置', '原因按使用频率排序 ${enabled ? '开启' : '关闭'}');
    _save();
  }

  /// 记录统计看板上次使用的区间（含自定义起止）。
  void setStatisticsRange(int range, {String? start, String? end}) {
    _appData.settings = _appData.settings.copyWith(
      statisticsRange: range,
      statisticsRangeStart: start,
      statisticsRangeEnd: end,
    );
    _log('统计设置', '看板区间改为 $range${start != null ? '（$start ~ $end）' : ''}');
    _save();
  }

  /// 保存统计口径：需关注学生的三档阈值与排行条数（设置 → 日常使用 → 统计口径）。
  void setStatisticsOptions({
    int? attentionThreshold,
    int? attentionMonthThreshold,
    int? attentionSemesterThreshold,
    int? rankingTopN,
  }) {
    final settings = _appData.settings;
    // 修复（审查四 G-8）：setter 入口 clamp 到合法范围（此前只靠 UI，非法值
    // 会运行期生效、直到下次重启才被 fromJson 清洗）。
    final weekly = (attentionThreshold ?? settings.attentionThreshold).clamp(
      AppSettings.minAttentionThreshold,
      AppSettings.maxAttentionThreshold,
    );
    final monthly =
        (attentionMonthThreshold ?? settings.attentionMonthThreshold).clamp(
          AppSettings.minAttentionMonthThreshold,
          AppSettings.maxAttentionMonthThreshold,
        );
    final semester =
        (attentionSemesterThreshold ?? settings.attentionSemesterThreshold)
            .clamp(
              AppSettings.minAttentionSemesterThreshold,
              AppSettings.maxAttentionSemesterThreshold,
            );
    final topN = (rankingTopN ?? settings.rankingTopN).clamp(
      AppSettings.minRankingTopN,
      AppSettings.maxRankingTopN,
    );
    if (weekly == settings.attentionThreshold &&
        monthly == settings.attentionMonthThreshold &&
        semester == settings.attentionSemesterThreshold &&
        topN == settings.rankingTopN) {
      return;
    }
    _appData.settings = settings.copyWith(
      attentionThreshold: weekly,
      attentionMonthThreshold: monthly,
      attentionSemesterThreshold: semester,
      rankingTopN: topN,
    );
    _log(
      '统计口径',
      '需关注阈值 一周 $weekly 次 / 一个月 $monthly 次 / 一学期 $semester 次 · 排行 Top $topN',
    );
    _save();
  }

  /// 保存悬浮球不透明度（0.35–1.0）。
  void setBallOpacity(double opacity) {
    final next = opacity
        .clamp(AppSettings.minBallOpacity, AppSettings.maxBallOpacity)
        .toDouble();
    final settings = _appData.settings;
    if (next == settings.ballOpacity) {
      return;
    }
    _appData.settings = settings.copyWith(ballOpacity: next);
    _log('悬浮球外观', '不透明度 ${(next * 100).round()}%');
    _save();
  }

  /// 锁定/解锁悬浮球位置；锁定后左键拖动不会移动球。
  void setBallPositionLocked(bool locked) {
    final settings = _appData.settings;
    if (settings.ballPositionLocked == locked) return;
    _appData.settings = settings.copyWith(ballPositionLocked: locked);
    _log('悬浮球', locked ? '锁定位置' : '解除位置锁定');
    _save();
  }

  /// 是否在顶栏显示天气；关闭后停止请求天气服务。
  void setShowWeather(bool enabled) {
    final settings = _appData.settings;
    if (settings.showWeather == enabled) return;
    _appData.settings = settings.copyWith(showWeather: enabled);
    _log('天气地区', enabled ? '显示顶栏天气' : '隐藏顶栏天气');
    _save();
  }

  /// 是否在主页学生网格上方显示姓名搜索框。
  void setStudentSearchEnabled(bool enabled) {
    final settings = _appData.settings;
    if (settings.studentSearchEnabled == enabled) return;
    _appData.settings = settings.copyWith(studentSearchEnabled: enabled);
    _log('主页学生搜索', enabled ? '显示搜索框' : '隐藏搜索框');
    _save();
  }

  /// 是否在启动时自动检查 GitHub 上的正式发布版本。
  void setCheckUpdateOnStartup(bool enabled) {
    final settings = _appData.settings;
    if (settings.checkUpdateOnStartup == enabled) return;
    _appData.settings = settings.copyWith(checkUpdateOnStartup: enabled);
    _log('启动检查更新', enabled ? '已开启' : '已关闭');
    _save();
  }

  /// 记录用户选择跳过的版本；传空串表示清除。
  void setSkippedUpdateTag(String tag) {
    final settings = _appData.settings;
    final next = tag.trim();
    if (settings.skippedUpdateTag == next) return;
    _appData.settings = settings.copyWith(skippedUpdateTag: next);
    _log('跳过更新', next.isEmpty ? '已清除' : next);
    _save();
  }

  /// 设置/清除顶栏天气地区（名称为空表示清除）。
  void setWeatherLocation({
    required String name,
    String admin = '',
    double latitude = 0,
    double longitude = 0,
  }) {
    final settings = _appData.settings;
    final nextName = name.trim();
    if (nextName.isEmpty) {
      if (settings.weatherCityName.isEmpty) return;
      _appData.settings = settings.copyWith(
        weatherCityName: '',
        weatherCityAdmin: '',
        weatherLatitude: 0,
        weatherLongitude: 0,
      );
      _log('天气地区', '清除天气地区');
      _save();
      return;
    }
    _appData.settings = settings.copyWith(
      weatherCityName: nextName,
      weatherCityAdmin: admin.trim(),
      weatherLatitude: latitude,
      weatherLongitude: longitude,
    );
    _log(
      '天气地区',
      admin.trim().isEmpty ? nextName : '$nextName · ${admin.trim()}',
    );
    _save();
  }

  /// 导出选项：文件名前缀与记录导出列。
  void setExportOptions({
    String? filePrefix,
    List<String>? recordColumns,
  }) {
    // 只接受已知列键：未知 key 会在导出时变成空列/错列，且写入设置后
    // 每次启动才被清理，期间一直影响导出。
    final allowedColumns = {
      ...AppSettings.defaultRecordExportColumns,
      'recordedBy',
    };
    final cleanedColumns = recordColumns == null
        ? null
        : <String>{
            for (final key in recordColumns)
              if (allowedColumns.contains(key)) key,
          }.toList(growable: false);
    _appData.settings = _appData.settings.copyWith(
      exportFilePrefix: filePrefix,
      recordExportColumns: cleanedColumns == null || cleanedColumns.isEmpty
          ? null
          : cleanedColumns,
    );
    _log('导出设置', '更新导出选项（前缀/记录列）');
    _save();
  }

  /// 原因的使用次数（扫一遍全部记录；供"按使用频率排序"使用）。
  Map<String, int> reasonUsageCounts() {
    final counts = <String, int>{};
    for (final records in _appData.recordsByDate.values) {
      for (final record in records) {
        for (final reason in record.reasons.split('、')) {
          final value = reason.trim();
          if (value.isEmpty) continue;
          counts[value] = (counts[value] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

}
