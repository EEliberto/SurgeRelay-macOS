const ui = {
  body: document.body,
  list: document.querySelector('#module-list'),
  summaryList: document.querySelector('#summary-list'),
  navigation: document.querySelector('.module-navigation'),
  detailRoot: document.querySelector('#detail'),
  detail: document.querySelector('#detail-content'),
  search: document.querySelector('#search-input'),
  add: document.querySelector('#add-button'),
  refresh: document.querySelector('#refresh-button'),
  settings: document.querySelector('#settings-button'),
  settingsMenuToggle: document.querySelector('#settings-menu-toggle'),
  back: document.querySelector('#mobile-back'),
  desktopBack: document.querySelector('#desktop-back'),
  desktopForward: document.querySelector('#desktop-forward'),
  mobileTitle: document.querySelector('#mobile-title'),
  mobileTitleIcon: document.querySelector('#mobile-title-icon'),
  mobileActions: document.querySelector('#mobile-detail-actions'),
  desktopTitle: document.querySelector('#desktop-title'),
  desktopActions: document.querySelector('#desktop-detail-actions'),
  status: document.querySelector('#activity-status'),
  percent: document.querySelector('#activity-percent'),
  progressTrack: document.querySelector('#progress-track'),
  progressFill: document.querySelector('#progress-fill'),
  latestUpdate: document.querySelector('#latest-update'),
  moduleDialog: document.querySelector('#module-dialog'),
  moduleDialogMessage: document.querySelector('#module-dialog-message'),
  settingsDialog: document.querySelector('#settings-dialog'),
  settingsContent: document.querySelector('#settings-content'),
  moduleForm: document.querySelector('#module-form'),
  dialogTitle: document.querySelector('#dialog-title'),
  saveModule: document.querySelector('#save-module-button'),
  advancedMaster: document.querySelector('#advanced-master'),
  advancedContent: document.querySelector('#advanced-master-content'),
  advancedOptions: document.querySelector('#advanced-options'),
  nativeNote: document.querySelector('#native-module-note'),
  confirmDialog: document.querySelector('#confirm-dialog'),
  confirmTitle: document.querySelector('#confirm-title'),
  confirmMessage: document.querySelector('#confirm-message'),
  confirmCancel: document.querySelector('#confirm-cancel'),
  confirmAccept: document.querySelector('#confirm-accept'),
  toast: document.querySelector('#toast'),
  iconDialog: document.querySelector('#icon-dialog')
};

const scriptHubDefaults = {
  scriptConversionKeywords: '', convertAllScripts: false,
  responseScriptConversionKeywords: '', convertAllResponseScripts: false,
  compatibilityOnly: false, prependScript: '', scriptEvalOriginal: '',
  scriptEvalConverted: '', scriptEvalOriginalURL: '', scriptEvalConvertedURL: '',
  includeKeywords: '', excludeKeywords: '', syncMITMToForceHTTP: false,
  removeCommentedRewrites: true, keepMapLocalHeaders: false, useJSDelivr: false,
  policy: '', mitmAdd: '', mitmRemove: '', mitmRemoveRegex: '',
  scriptNameTargets: '', scriptNames: '', timeoutTargets: '', timeoutValues: '',
  engineTargets: '', engineValues: '', cronTargets: '', cronExpressions: '',
  argumentTargets: '', argumentValues: '', noResolve: false, sniKeywords: '',
  preMatchingKeywords: '', enableJQ: true, requestHeaders: '', evalOriginal: '',
  evalConverted: '', evalOriginalURL: '', evalConvertedURL: ''
};

const advancedGroups = [
  {
    id: 'script-conversion', title: '启用脚本转换',
    description: '仅在脚本使用了来源 App 独有 API 时启用。启用后，App 会预先转换脚本并将辅助资源发布到 GitHub。',
    fields: [
      textField('scriptConversionKeywords', '脚本转换 1 关键词', '例如：response-body.js+request.js', '多关键词使用 + 分隔。'),
      toggleField('convertAllScripts', '脚本转换 1：全部转换'),
      textField('responseScriptConversionKeywords', '脚本转换 2 关键词', '例如：response.js+parser.js', '转换 2 会为 $done(body) 包装 response。'),
      toggleField('convertAllResponseScripts', '脚本转换 2：全部转换并包装 response'),
      toggleField('compatibilityOnly', '仅进行兼容性转换'),
      textField('prependScript', '在脚本开头添加代码', "例如：console.log(new Date().toLocaleString('zh'))", '代码会添加到被转换脚本的开头。', true),
      headingField('脚本转换高级处理'),
      textField('scriptEvalOriginal', '处理脚本原始内容（代码）', "例如：body = body.replace(/old/g, 'new')", '', true),
      textField('scriptEvalConverted', '处理脚本转换后内容（代码）', "例如：body = body.replace(/old/g, 'new')", '', true),
      textField('scriptEvalOriginalURL', '处理脚本原始内容（代码 URL）', 'https://example.com/process-original.js'),
      textField('scriptEvalConvertedURL', '处理脚本转换后内容（代码 URL）', 'https://example.com/process-converted.js')
    ]
  },
  {
    id: 'rewrites', title: '重写相关', fields: [
      textField('includeKeywords', '保留重写关键词', '例如：login+account', '匹配的已注释重写会被启用。'),
      textField('excludeKeywords', '排除重写关键词', '例如：tracking+analytics', '匹配的重写会被注释。'),
      toggleField('syncMITMToForceHTTP', '将 MitM 主机名同步到 force-http-engine-hosts'),
      toggleField('removeCommentedRewrites', '剔除被注释的重写'),
      toggleField('keepMapLocalHeaders', '保留 Map Local / echo-response 的 Header'),
      toggleField('useJSDelivr', '将 GitHub 脚本地址转换为 jsDelivr')
    ]
  },
  { id: 'policy', title: '指定策略', description: '为未指定策略或使用非 Surge 内置策略的规则指定一个替代策略。', fields: [textField('policy', '策略', '例如：DIRECT、REJECT 或你的策略组名称')] },
  {
    id: 'mitm', title: '修改 MitM 主机名', fields: [
      textField('mitmAdd', '添加主机名', '例如：api.example.com, *.example.com', '多个主机名使用英文逗号分隔。'),
      textField('mitmRemove', '删除主机名', '例如：ads.example.com, track.example.com'),
      textField('mitmRemoveRegex', '按正则删除主机名', '例如：(^|\\.)ads\\.example\\.com$')
    ]
  },
  pairedGroup('script-name', '修改脚本名', 'scriptNameTargets', '关键词锁定脚本 (njsnametarget)', '例如：checkin+account', 'scriptNames', '新的脚本名 (njsname)', '例如：签到任务+账户任务'),
  pairedGroup('timeout', '修改脚本超时', 'timeoutTargets', '关键词锁定脚本 (timeoutt)', '例如：checkin+account', 'timeoutValues', '超时值 (timeoutv)', '例如：10+30'),
  pairedGroup('engine', '修改脚本引擎（Surge）', 'engineTargets', '关键词锁定脚本 (enginet)', '例如：legacy-script', 'engineValues', '引擎 (enginev)', '例如：webview'),
  pairedGroup('cron', '修改定时任务', 'cronTargets', '关键词锁定任务 (cron)', '例如：daily-checkin', 'cronExpressions', 'Cron 表达式 (cronexp)', '例如：0.0.8.*.*.*'),
  pairedGroup('arguments', '修改参数', 'argumentTargets', '关键词锁定脚本 (arg)', '例如：account-script', 'argumentValues', 'Argument 新值 (argv)', '例如：key=value'),
  {
    id: 'rules', title: '规则与请求', fields: [
      toggleField('noResolve', 'IP 规则开启 no-resolve'),
      textField('sniKeywords', 'SNI 扩展匹配关键词', '例如：DOMAIN-SUFFIX+RULE-SET'),
      textField('preMatchingKeywords', 'pre-matching 关键词', '例如：REJECT+tracking'),
      toggleField('enableJQ', '开启 JQ'),
      textField('requestHeaders', '自定义请求 Header', 'User-Agent:script-hub/1.0.0\nAuthorization:token xxx', '每行一个 Header，使用英文冒号分隔名称和值。', true)
    ]
  },
  {
    id: 'content-processing', title: '高级内容处理', fields: [
      textField('evalOriginal', '处理原始内容（代码）', "例如：body = body.replace(/old/g, 'new')", '', true),
      textField('evalConverted', '处理转换后内容（代码）', "例如：body = body.replace(/old/g, 'new')", '', true),
      textField('evalOriginalURL', '处理原始内容（代码 URL）', 'https://example.com/process-original.js'),
      textField('evalConvertedURL', '处理转换后内容（代码 URL）', 'https://example.com/process-converted.js')
    ]
  }
];

let state = null;
let selectedID = 'combined';
let selectedPlatform = 'iOS';
let detailTab = 'info';
let editingID = null;
let previewText = '';
let previewSavedText = '';
let previewSearchQuery = '';
let previewSearchMatches = [];
let previewSearchIndex = -1;
let previewEditorMirrorDirty = false;
let previewSearchDebounceTimer = null;
let settingsPane = 'general';
let settingsDraftStorageMode = null;
let settingsDraftDirty = false;
let settingsMenuOpen = false;
let dialogScrollY = 0;
const SETTINGS_PANES = [
  ['general', '通用', 'gearshape'],
  ['scriptHub', 'Script Hub', 'arrow.trianglehead.branch'],
  ['sync', '同步', 'arrow.trianglehead.2.clockwise.rotate.90'],
  ['diagnostics', '诊断', 'stethoscope'],
  ['about', '关于', 'info.circle']
];
let toastTimer = null;
let confirmResolver = null;
let nameLookupTimer = null;
let nameLookupSequence = 0;
let autoFilledName = '';
let manualNameEdited = false;
let listScrollY = 0;
let stateRecoveryTimer = null;
let stateRecoveryAttempt = 0;
const mobileLayout = window.matchMedia('(max-width: 700px)');

// Dynamic values embedded in templates must still be escaped before use.
function setTemplateHTML(element, html) {
  if (!element) return;
  const template = document.createElement('template');
  template.innerHTML = html;
  element.replaceChildren(template.content.cloneNode(true));
}

initializeHistoryState();

setTemplateHTML(ui.advancedOptions, `<p class="advanced-intro">这些选项由 App 内置的 Script‑Hub 引擎执行，并随当前模块保存。留空即采用上游默认行为。</p>${advancedGroups.map(advancedGroupMarkup).join('')}`);

ui.search.addEventListener('input', renderSidebar);
ui.add.addEventListener('click', () => openEditor());
ui.refresh.addEventListener('click', updateAll);
ui.settings?.addEventListener('click', openWebSettings);
ui.settingsMenuToggle?.addEventListener('click', () => {
  settingsMenuOpen = !settingsMenuOpen;
  ui.settingsContent?.querySelector('.settings-layout')?.classList.toggle('menu-open', settingsMenuOpen);
});
ui.summaryList.addEventListener('click', event => {
  const btn = event.target.closest('.summary-row');
  if (btn) {
    selectedPlatform = btn.dataset.platformId;
    selectItem(`combined-${selectedPlatform}`);
  }
});
  ui.back.addEventListener('click', navigateBackToList);
ui.desktopBack?.addEventListener('click', () => history.back());
ui.desktopForward?.addEventListener('click', () => history.forward());
ui.advancedMaster.addEventListener('click', () => animateAdvancedResize(ui.advancedMaster.getAttribute('aria-expanded') !== 'true'));
ui.advancedOptions.addEventListener('click', event => {
  const summary = event.target.closest('.option-group > summary');
  if (!summary) return;
  event.preventDefault();
  animateOptionGroup(summary.parentElement);
});
ui.moduleForm.elements.sourceURL.addEventListener('input', () => {
  updateNativeModuleState();
  scheduleNameLookup();
});
ui.moduleForm.elements.sourceFormat.addEventListener('change', updateNativeModuleState);
ui.moduleForm.elements.name.addEventListener('input', event => {
  manualNameEdited = event.target.value !== autoFilledName;
  if (!event.target.value) manualNameEdited = false;
});
document.querySelectorAll('.close-module-dialog').forEach(button => button.addEventListener('click', () => closeDialog(ui.moduleDialog)));
document.querySelectorAll('.close-settings-dialog').forEach(button => button.addEventListener('click', () => closeDialog(ui.settingsDialog)));
document.querySelectorAll('.close-icon-dialog').forEach(button => button.addEventListener('click', () => closeDialog(ui.iconDialog)));
document.getElementById('cancel-icon-dialog').addEventListener('click', () => closeDialog(ui.iconDialog));
document.getElementById('done-icon-dialog').addEventListener('click', commitIconDraft);
ui.moduleDialog.addEventListener('click', event => { if (event.target === ui.moduleDialog) closeDialog(ui.moduleDialog); });
ui.iconDialog.addEventListener('click', event => { if (event.target === ui.iconDialog) closeDialog(ui.iconDialog); });
[ui.moduleDialog, ui.settingsDialog, ui.confirmDialog, ui.iconDialog].forEach(dialog => dialog?.addEventListener('close', unlockDialogScrollIfIdle));
ui.moduleForm.addEventListener('submit', saveModule);
ui.confirmCancel.addEventListener('click', () => resolveConfirmation(false));
ui.confirmAccept.addEventListener('click', () => resolveConfirmation(true));
ui.confirmDialog.addEventListener('click', event => { if (event.target === ui.confirmDialog) resolveConfirmation(false); });
ui.list.addEventListener('click', handleListClick);
ui.list.addEventListener('change', handleListChange);
ui.list.addEventListener('keydown', event => {
  const row = event.target.closest('.module-row');
  if (row && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); selectItem(row.dataset.id); }
});
ui.detailRoot.addEventListener('click', handleDetailClick);
ui.detailRoot.addEventListener('input', handleDetailInput);
ui.detailRoot.addEventListener('change', handleDetailChange);
ui.settingsContent?.addEventListener('click', handleSettingsClick);
ui.settingsContent?.addEventListener('input', handleSettingsInput);
ui.settingsContent?.addEventListener('change', handleSettingsChange);
ui.mobileActions.addEventListener('click', handleDetailClick);
window.addEventListener('popstate', handleHistoryNavigation);

// Custom Icon event bindings
document.getElementById('save-custom-icon-button').addEventListener('click', () => {
  const url = document.getElementById('custom-icon-url-input').value.trim();
  if (!url) return;
  pendingIconURL = url;
  hasPendingIconSelection = true;
  updateIconEditorPreview(url);
});
document.getElementById('reset-icon-button').addEventListener('click', resetCustomIcon);
document.getElementById('search-icon-button').addEventListener('click', performIconSearch);
document.getElementById('icon-search-input').addEventListener('keydown', event => {
  if (event.key === 'Enter') {
    event.preventDefault();
    performIconSearch();
  }
});
document.getElementById('icon-search-region-select').addEventListener('change', async event => {
  const newRegion = event.target.value;
  try {
    await api('/api/settings/general', { method: 'PUT', json: { iconSearchRegion: newRegion } });
    if (state && state.settings) {
      state.settings.iconSearchRegion = newRegion;
    }
  } catch (e) {
    console.error('Failed to save search region preference:', e);
  }
  performIconSearch();
});

loadState(true, true).finally(startStateEvents);

function textField(key, label, prompt = '', help = '', multiline = false) { return { type: multiline ? 'textarea' : 'text', key, label, prompt, help }; }
function toggleField(key, label) { return { type: 'toggle', key, label }; }
function headingField(label) { return { type: 'heading', label }; }
function pairedGroup(id, title, firstKey, firstLabel, firstPrompt, secondKey, secondLabel, secondPrompt) {
  return { id, title, description: '多项使用 + 分隔；目标和值需要一一对应。', fields: [textField(firstKey, firstLabel, firstPrompt), textField(secondKey, secondLabel, secondPrompt)] };
}

async function api(path, options = {}) {
  const headers = new Headers(options.headers || {});
  let body = options.body;
  if (options.json !== undefined) { headers.set('Content-Type', 'application/json'); body = JSON.stringify(options.json); }
  let response;
  try {
    response = await fetch(path, { method: options.method || 'GET', headers, body });
  } catch (error) {
    if (error instanceof TypeError && (error.message.toLowerCase().includes('failed to fetch') || error.message.toLowerCase().includes('load failed') || error.message.toLowerCase().includes('network error'))) {
      throw new Error('应用未连接或网络错误');
    }
    throw error;
  }
  if (!response.ok) {
    let message = `请求失败（${response.status}）`;
    try { message = (await response.json()).message || message; } catch (_) {}
    throw new Error(message);
  }
  const contentType = response.headers.get('content-type') || '';
  return contentType.includes('application/json') ? response.json() : response.text();
}

async function loadState(initial = false, renderCurrentDetail = false) {
  try {
    const next = await api('/api/state');
    applyState(next, initial, renderCurrentDetail);
    return true;
  } catch (error) {
    showToast(error.message, true);
    return false;
  }
}

function applyState(next, initial = false, renderCurrentDetail = false) {
    const previous = state;
    state = next;
    if (initial) {
      let requested = new URL(location.href).searchParams.get('module');
      if (requested === 'combined') requested = 'combined-' + selectedPlatform;
      if (requested && (requested.startsWith('combined-') || next.modules.some(module => module.id === requested))) {
        selectedID = requested;
        if (requested.startsWith('combined-')) {
          selectedPlatform = requested.substring(9);
        }
        ui.body.classList.add('has-selection');
      } else if (mobileLayout.matches) {
        selectedID = null;
        ui.body.classList.remove('has-selection', 'preview-mode');
      } else {
        selectedID = defaultDetailSelection();
      }
    }
    if (next.platforms && !next.platforms.find(p => p.id === selectedPlatform && p.isEnabled)) {
      const activePlatform = next.platforms.find(p => p.isEnabled);
      if (activePlatform) selectedPlatform = activePlatform.id;
    }
    if (selectedID && selectedID.startsWith('combined-')) {
      selectedID = 'combined-' + selectedPlatform;
    } else if (selectedID && !next.modules.some(module => module.id === selectedID)) {
      selectedID = 'combined-' + selectedPlatform;
    }
    if (!selectedID && !mobileLayout.matches) selectedID = defaultDetailSelection();
    if (initial || renderCurrentDetail) {
      renderSidebar();
      renderActivity();
      renderDetail(false);
      if (initial && mobileLayout.matches && selectedID) ui.detail.scrollTop = 0;
    } else {
      patchLiveState(previous, next);
      renderActivity();
    }
    updateDesktopNavigationButtons();
}

function defaultDetailSelection() {
  const platform = state?.platforms?.find(item => item.isEnabled) || state?.platforms?.[0];
  if (platform) {
    selectedPlatform = platform.id;
    return `combined-${platform.id}`;
  }
  return state?.modules?.[0]?.id || null;
}

function updateDesktopNavigationButtons() {
  if (!ui.desktopBack || !ui.desktopForward) return;
  const currentIndex = Number(history.state?.relayIndex ?? 0);
  const maximumIndex = Number(history.state?.relayMaxIndex ?? currentIndex);
  ui.desktopBack.disabled = currentIndex <= 0;
  ui.desktopForward.disabled = currentIndex >= maximumIndex;
}

function startStateEvents() {
  if (!('EventSource' in window)) {
    setInterval(() => { if (!document.hidden) loadState(false, false); }, 5000);
    return;
  }
  const events = new EventSource('/api/events');
  events.addEventListener('state', event => {
    clearTimeout(stateRecoveryTimer);
    stateRecoveryTimer = null;
    stateRecoveryAttempt = 0;
    try { applyState(JSON.parse(event.data), false, false); }
    catch (_) { /* The next event contains a complete state snapshot. */ }
  });
  events.onerror = () => {
    if (document.hidden || stateRecoveryTimer) return;
    startStateRecovery();
  };
}

function startStateRecovery() {
  if (document.hidden || stateRecoveryTimer) return;
  const delay = Math.min(30_000, 1_000 * (2 ** stateRecoveryAttempt));
  stateRecoveryAttempt = Math.min(stateRecoveryAttempt + 1, 5);
  stateRecoveryTimer = setTimeout(async () => {
    stateRecoveryTimer = null;
    if (!await loadState(false, false)) startStateRecovery();
  }, delay);
}

function patchLiveState(previous, next) {
  if (!previous) {
    renderSidebar();
    return;
  }

  const previousList = previous.modules.map(module => [module.id, module.name, module.sourceFormatTitle, module.iconURL].join('|')).join('\n');
  const nextList = next.modules.map(module => [module.id, module.name, module.sourceFormatTitle, module.iconURL].join('|')).join('\n');
  if (previousList !== nextList) renderSidebar(); else patchSidebarLive();

  if (detailTab !== 'info') return;
  if (selectedID && selectedID.startsWith('combined-')) {
    const currentPlatform = next.platforms.find(p => p.id === selectedPlatform) || next.platforms[0];
    patchDetailValue('包含来源', `${currentPlatform.enabledModules.length} / ${next.modules.length}`);
    patchDetailValue('最新更新', formatDate(next.combined.lastUpdatedAt, '尚未更新'));
    return;
  }

  const module = next.modules.find(item => item.id === selectedID);
  if (!module) return;
  patchDetailValue('来源格式', module.sourceFormatTitle);
  patchDetailValue('汇总订阅', next.combined.subscriptionURL || '等待发布配置');
  patchDetailValue('上次更新', formatDate(module.lastUpdatedAt, '从未更新'));
}

function patchDetailValue(label, value) {
  const row = [...ui.detail.querySelectorAll('.detail-row')]
    .find(item => item.querySelector('.detail-label span:last-child')?.textContent === label);
  const target = row?.querySelector('.detail-value');
  if (target && target.textContent !== value) target.textContent = value;
}

function renderSummaryList() {
  if (!state || !state.platforms) return;
  const activePlatforms = state.platforms.filter(p => p.isEnabled);
  setTemplateHTML(ui.summaryList, activePlatforms.map(platform => {
    const isSelected = selectedID === `combined-${platform.id}`;
    return `<button class="summary-row ${isSelected ? 'selected' : ''}" data-platform-id="${platform.id}" type="button">
      <span class="module-icon summary-icon"><img src="${escapeAttribute(platform.iconURL || '/summary-icon.png?v=1')}" alt=""></span>
      <span class="module-copy"><strong>Surge Relay 汇总 (${platform.displayName})</strong><small>${platform.enabledModules.length} 个来源</small></span>
      <span class="symbol disclosure" data-symbol="chevron.right"></span>
    </button>`;
  }).join(''));
}

function patchSidebarLive() {
  renderSummaryList();
}

function renderSidebar() {
  if (!state) return;
  const query = ui.search.value.trim().toLocaleLowerCase();
  const modules = state.modules.filter(module => [module.name, module.sourceURL, module.sourceFormatTitle, module.outputFileName].join('\n').toLocaleLowerCase().includes(query));
  renderSummaryList();
  setTemplateHTML(ui.list, modules.length ? modules.map(moduleRow).join('') : `<div class="empty-state"><div><span class="symbol" data-symbol="magnifyingglass"></span><div>${query ? '没有搜索结果' : '还没有模块'}</div></div></div>`);
}

function moduleRow(module) {
  const icon = module.iconURL ? `<img src="${escapeAttribute(module.iconURL)}" alt="" loading="lazy">` : `<span class="symbol" data-symbol="shippingbox"></span>`;
  return `<div class="module-row ${selectedID === module.id ? 'selected' : ''}" data-id="${module.id}" role="button" tabindex="0">
    <span class="module-icon ${module.iconURL ? '' : 'placeholder'}">${icon}</span>
    <span class="module-copy"><strong>${escapeHTML(module.name)}</strong><small>${escapeHTML(module.sourceFormatTitle)}</small></span>
  </div>`;
}

function renderActivity() {
  if (!state) return;
  const activity = state.activity;
  ui.status.textContent = activity.status || '准备就绪';
  ui.refresh.disabled = activity.isWorking;
  if (activity.isWorking && activity.progress !== null) {
    const percent = Math.round(activity.progress * 100);
    ui.percent.textContent = `${percent}%`;
    ui.progressTrack.hidden = false;
    ui.progressFill.style.width = `${percent}%`;
  } else {
    ui.percent.textContent = '';
    ui.progressTrack.hidden = true;
    ui.progressFill.style.width = '0%';
  }
  ui.latestUpdate.textContent = formatDate(state.combined.lastUpdatedAt, '尚未更新');
}

function renderDetail(animate = true) {
  ui.body.classList.toggle('preview-mode', detailTab === 'preview' && Boolean(selectedID));
  if (state && !selectedID && !mobileLayout.matches) selectedID = defaultDetailSelection();
  if (!state || !selectedID) {
    if (ui.mobileTitleIcon) ui.mobileTitleIcon.style.display = 'none';
    setTemplateHTML(ui.desktopActions, '');
    setTemplateHTML(ui.mobileActions, '');
    setDetailHTML('', false);
    return;
  }
  if (selectedID && selectedID.startsWith('combined-')) {
    const currentPlatform = state.platforms?.find(p => p.id === selectedPlatform) || state.platforms?.[0] || { displayName: 'iOS' };
    const name = `Surge Relay 汇总 (${currentPlatform.displayName})`;
    ui.mobileTitle.textContent = name;
    if (ui.mobileTitleIcon) {
      setTemplateHTML(ui.mobileTitleIcon, '<img src="/app-icon.png?v=1" alt="">');
      ui.mobileTitleIcon.style.display = 'block';
    }
    ui.desktopTitle.textContent = name;
    renderCombinedDetail(animate);
  }
  else {
    const module = state.modules.find(item => item.id === selectedID);
    if (module) {
      ui.mobileTitle.textContent = module.name;
      if (ui.mobileTitleIcon) {
        setTemplateHTML(ui.mobileTitleIcon, '<img src="/app-icon.png?v=1" alt="">');
        ui.mobileTitleIcon.style.display = 'block';
      }
      ui.desktopTitle.textContent = module.name;
      renderModuleDetail(module, animate);
    }
  }
}

function setDetailHTML(content, animate = true) {
  setTemplateHTML(ui.detail, `<div class="detail-stage ${animate ? 'page-enter' : ''}">${content}</div>`);
}

function detailToolbar(module = null) {
  const controls = `
    <div class="segmented-control" aria-label="显示方式">
      <button data-action="tab-info" class="${detailTab === 'info' ? 'selected' : ''}"><span class="symbol" data-symbol="info.circle"></span><span>详情</span></button>
      <button data-action="tab-preview" class="${detailTab === 'preview' ? 'selected' : ''}"><span class="symbol" data-symbol="curlybraces"></span><span>预览</span></button>
    </div>
    ${module ? `<button class="button destructive" data-action="delete"><span class="symbol" data-symbol="trash"></span>删除</button>` : ''}`;
  setTemplateHTML(ui.desktopActions, controls);
  setTemplateHTML(ui.mobileActions, controls);
  return '';
}

function renderCombinedDetail(animate = true) {
  const currentPlatform = state.platforms?.find(p => p.id === selectedPlatform) || state.platforms?.[0] || { id: 'iOS', displayName: 'iOS', fileName: 'Surge-Relay.sgmodule', subscriptionURL: null, enabledModules: [] };
  if (detailTab === 'preview') {
    setDetailHTML(detailToolbar() + previewShell(currentPlatform.fileName, false), animate);
    loadPreview(`/api/combined/preview?platform=${selectedPlatform}`, false);
    return;
  }

  const subscription = state.storageMode === 'local'
    ? `<section class="form-section-view"><h3 class="section-heading">iCloud 云盘</h3><div class="group-box"><div class="icloud-sync-card"><img src="/icloud-icon.png?v=1" alt=""><div class="icloud-sync-copy"><strong>通过 iCloud 保持 Surge Relay 同步</strong><span>iCloud/Surge/${escapeHTML(currentPlatform.fileName)}</span></div></div></div></section>`
    : (currentPlatform.subscriptionURL ? `<section class="form-section-view"><h3 class="section-heading">GitHub 私有仓库</h3><div class="group-box"><div class="icloud-sync-card"><img src="/github-icon.png?v=1" alt=""><div class="icloud-sync-copy"><strong>通过 GitHub 保持 Surge Relay 同步</strong><span>经 Cloudflare Worker 分发稳定订阅</span></div></div><div class="detail-row action-row"><div class="detail-value monospaced">${escapeHTML(currentPlatform.subscriptionURL)}</div><div><button class="button" data-action="copy" data-value="${escapeAttribute(currentPlatform.subscriptionURL)}"><span class="symbol" data-symbol="copy"></span>拷贝地址</button></div></div></div></section>` : '');

  const sourceModulesList = state.modules.map(module => {
    const isModuleEnabled = currentPlatform.enabledModules.includes(module.id);
    const icon = module.iconURL
      ? `<img src="${escapeAttribute(module.iconURL)}" alt="" loading="lazy">`
      : `<span class="symbol" data-symbol="shippingbox"></span>`;
    return `
      <div class="detail-row individual-output-row" style="min-height: 48px; padding: 10px 14px;">
        <div class="detail-label" style="min-width: 0; display: flex; align-items: center; gap: 10px;">
          <span class="module-icon ${module.iconURL ? '' : 'placeholder'}" style="width: 28px; height: 28px; border-radius: 7px; overflow: hidden; flex-shrink: 0; display: inline-flex; align-items: center; justify-content: center;">
            ${icon}
          </span>
          <span style="font-size: 14px; font-weight: 500; color: var(--label); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
            ${escapeHTML(module.name)}
          </span>
        </div>
        <label class="module-toggle">
          <input type="checkbox" data-platform-module-toggle="${module.id}" data-platform-id="${currentPlatform.id}" ${isModuleEnabled ? 'checked' : ''}>
          <span class="toggle-track" aria-hidden="true"></span>
        </label>
      </div>
    `;
  }).join('');

  const allEnabled = state.modules.length > 0 && state.modules.every(m => currentPlatform.enabledModules.includes(m.id));
  const modulesSection = `
    <section class="form-section-view">
      <div class="section-heading-row"><h3 class="section-heading">来源模块选择</h3><button class="section-action" data-action="toggle-all-modules" data-platform-id="${currentPlatform.id}" type="button">${allEnabled ? '全部停用' : '全部启用'}</button></div>
      <div class="group-box" style="padding:0;overflow:hidden;">
        ${sourceModulesList}
      </div>
    </section>
  `;

  const combinedHeader = `
    <section class="form-section-view module-detail-header-section">
      <div class="group-box module-detail-header-card">
        <div class="module-detail-icon-clickable summary-module-icon">
          <img src="${escapeAttribute(currentPlatform.iconURL || '/summary-icon.png?v=1')}" alt="">
        </div>
        <div class="module-detail-copy">
          <h2>Surge Relay 汇总 (${escapeHTML(currentPlatform.displayName)})</h2>
        </div>
      </div>
    </section>
  `;
  setDetailHTML(`${detailToolbar()}
    ${combinedHeader}
    <section class="form-section-view"><h3 class="section-heading">汇总模块</h3><div class="group-box">
      ${detailRow('square.stack.3d.up.fill', '名称', `Surge Relay 汇总 (${currentPlatform.displayName})`)}
      ${detailRow('shippingbox', '包含来源', `${currentPlatform.enabledModules.length} / ${state.modules.length}`)}
      ${detailRow('clock', '最新更新', formatDate(state.combined.lastUpdatedAt, '尚未更新'))}
    </div></section>${subscription}${modulesSection}`, animate);
}

function renderModuleDetail(module, animate = true) {
  if (detailTab === 'preview') {
    setDetailHTML(detailToolbar(module) + previewShell(module.outputFileName, true), animate);
    loadPreview(`/api/modules/${module.id}/preview`, true);
    return;
  }
  const iconHtml = module.iconURL
    ? `<img src="${escapeAttribute(module.iconURL)}" alt="" style="width: 100%; height: 100%; object-fit: cover;">`
    : `<span class="symbol" data-symbol="shippingbox" style="width: 24px; height: 24px; color: var(--secondary-label);"></span>`;
  const headerSection = `
    <section class="form-section-view module-detail-header-section">
      <div class="group-box module-detail-header-card">
        <div class="module-detail-icon-clickable" data-action="edit-icon" title="点击修改图标">
          ${iconHtml}
        </div>
        <div class="module-detail-copy">
          <h2>${escapeHTML(module.name)}</h2>
          <div class="module-detail-actions">
            <button class="link-button" data-action="edit-icon" type="button">修改图标</button>
            <button class="link-button" data-action="edit" type="button">编辑模块</button>
          </div>
        </div>
      </div>
    </section>
  `;
  const advanced = module.advancedSummary ? `<section class="form-section-view"><h3 class="section-heading">高级设置</h3><div class="group-box"><div class="detail-row"><div class="detail-label"><span class="symbol" data-symbol="slider.horizontal.3"></span><span>已应用</span></div><div class="detail-value advanced-summary">${escapeHTML(module.advancedSummary)}</div></div></div></section>` : '';
  const published = state.storageMode === 'gitHub' ? `<section class="form-section-view"><h3 class="section-heading">GitHub 私有仓库</h3><div class="group-box">
    <div class="icloud-sync-card"><img src="/github-icon.png?v=2" alt=""><div class="icloud-sync-copy"><strong>通过 GitHub 同步独立模块</strong><span>经 Cloudflare Worker 分发稳定订阅</span></div></div>
    ${module.publishedURL ? `<div class="detail-row action-row"><div class="detail-value monospaced">${escapeHTML(module.publishedURL)}</div><div><button class="button" data-action="copy" data-value="${escapeAttribute(module.publishedURL)}"><span class="symbol" data-symbol="copy"></span>拷贝地址</button></div></div>` : '<div class="detail-row action-row"><div class="detail-value">完成发布配置后，这里会出现该模块自己的稳定地址。</div></div>'}
    <div class="detail-note">
      <span class="symbol" data-symbol="info.circle"></span>
      <span>提示：若要自行修改模块内容，请通过上方“预览”标签页进行编辑。直接修改 GitHub 里的生成模块将在下次发布时被覆盖。</span>
    </div>
  </div></section>` : '';
  const error = module.lastError ? `<section class="form-section-view"><h3 class="section-heading">最近一次更新失败</h3><div class="group-box"><div class="detail-row action-row error-box"><strong>更新失败</strong><div>${escapeHTML(module.lastError)}</div><small>如果该来源有缓存，总模块会继续沿用它上一次成功版本。</small></div></div></section>` : '';
  const conflict = module.hasOverrideConflict ? `<section class="form-section-view"><h3 class="section-heading">本地编辑冲突</h3><div class="group-box"><div class="detail-row action-row error-box"><strong>上游内容已经变化</strong><div>当前仍在使用本地编辑。可在预览中比较内容后保留或恢复。</div><div><button class="button" data-action="accept-override">保留本地编辑</button><button class="button" data-action="tab-preview">前往预览</button></div></div></div></section>` : '';
  const individualOutput = state.storageMode === 'local' ? `<section class="form-section-view"><h3 class="section-heading">iCloud 云盘</h3><div class="group-box">
    <div class="icloud-sync-card individual-sync-card"><img src="/icloud-icon.png?v=2" alt=""><div class="icloud-sync-copy"><strong>输出独立模块至 iCloud 云盘</strong><span>iCloud/Surge/${escapeHTML(individualRelayFileName(module.outputFileName))}</span></div><label class="module-toggle" aria-label="输出独立模块至 iCloud 云盘"><input type="checkbox" data-individual-icloud-export ${module.exportsIndividualModuleToICloud ? 'checked' : ''}><span class="toggle-track" aria-hidden="true"></span></label></div>
    <div class="arguments-footer"><small>开启后在 Surge 文件夹生成该模块的独立文件；关闭后自动删除。汇总模块不受影响。</small></div>
    <div class="detail-note">
      <span class="symbol" data-symbol="info.circle"></span>
      <span>提示：若要自行修改模块内容，请通过上方“预览”标签页进行编辑。直接修改 iCloud 生成的同步文件将在下一次同步时被覆盖。</span>
    </div>
  </div></section>` : '';
  setDetailHTML(`${detailToolbar(module)}
    ${headerSection}
    <section class="form-section-view"><h3 class="section-heading">模块信息</h3><div class="group-box">
      ${detailRow('link', '原始地址', `<a href="${escapeAttribute(module.sourceURL)}" target="_blank" rel="noreferrer">${escapeHTML(module.sourceURL)}</a>`, true)}
      ${detailRow('doc.text', '来源格式', module.sourceFormatTitle)}
      ${detailRow('clock', '上次更新', formatDate(module.lastUpdatedAt, '从未更新'))}
    </div></section>
    ${individualOutput}${advanced}${conflict}${published}${error}`, animate);
}

function detailRow(icon, label, value, raw = false) {
  return `<div class="detail-row"><div class="detail-label"><span class="symbol" data-symbol="${icon}"></span><span>${escapeHTML(label)}</span></div><div class="detail-value">${raw ? value : escapeHTML(String(value ?? '—'))}</div></div>`;
}

function individualRelayFileName(value) {
  const trimmed = String(value || '').trim();
  const withoutExtension = trimmed.toLowerCase().endsWith('.sgmodule') ? trimmed.slice(0, -'.sgmodule'.length) : trimmed;
  const base = withoutExtension
    .replace(/[\/\\:*?"<>|]/g, '-')
    .replace(/\s+/g, '-')
    .replace(/^[.\-\s]+|[.\-\s]+$/g, '');
  const normalized = base || 'Untitled';
  return normalized.toLowerCase().endsWith('-surgerelay')
    ? `${normalized}.sgmodule`
    : `${normalized}-SurgeRelay.sgmodule`;
}

function previewShell(label, editable) {
  clearTimeout(previewSearchDebounceTimer);
  previewSearchDebounceTimer = null;
  previewSearchQuery = '';
  previewSearchMatches = [];
  previewSearchIndex = -1;
  previewEditorMirrorDirty = false;
  return `<section class="preview-shell">
    <div class="preview-toolbar"><span class="preview-label">${escapeHTML(label)}</span><button class="button copy-button" data-action="copy-preview"><span class="symbol" data-symbol="copy"></span>拷贝全部</button>${editable ? `<button class="button" data-action="restore-preview"><span class="symbol" data-symbol="arrow.uturn.backward"></span>恢复</button><button class="button primary" data-action="save-preview" disabled>写入</button>` : ''}</div>
    <div class="preview-code-stage">
      <div class="preview-search-wrap">
        <div class="preview-search-field">
          <span class="symbol" data-symbol="magnifyingglass"></span>
          <input id="preview-search-input" type="search" placeholder="搜索" autocomplete="off" aria-label="搜索预览内容">
          <span class="preview-search-count" id="preview-search-count" aria-live="polite"></span>
        </div>
        <div class="preview-search-navigation" aria-label="搜索结果导航">
          <button class="preview-search-button previous" data-action="preview-search-previous" type="button" aria-label="上一个结果" disabled><span class="symbol" data-symbol="chevron.left"></span></button>
          <button class="preview-search-button next" data-action="preview-search-next" type="button" aria-label="下一个结果" disabled><span class="symbol" data-symbol="chevron.right"></span></button>
        </div>
      </div>
      ${editable ? '<div class="code-editor-stack"><pre class="code-editor-highlight-layer" id="code-editor-highlight-layer" aria-hidden="true"></pre><textarea class="code-editor" id="code-editor" spellcheck="false" aria-label="模块内容">正在载入…</textarea></div>' : '<pre class="code-view" id="code-view">正在载入…</pre>'}
    </div>
  </section>`;
}

async function loadPreview(path, editable) {
  try {
    const text = await api(path);
    if (editable) {
      const editor = document.querySelector('#code-editor');
      if (!editor) return;
      previewText = text; previewSavedText = text; editor.value = text;
      previewEditorMirrorDirty = true;
      rebuildPreviewEditorMirror();
      editor.addEventListener('input', () => { previewText = editor.value; previewEditorMirrorDirty = true; const save = document.querySelector('[data-action="save-preview"]'); if (save) save.disabled = previewText === previewSavedText; refreshPreviewSearch(false); });
      editor.addEventListener('scroll', syncPreviewEditorHighlightScroll, { passive: true });
    } else {
      const view = document.querySelector('#code-view');
      if (view) setTemplateHTML(view, highlightCode(text));
      previewText = text; previewSavedText = text;
    }
    refreshPreviewSearch(false);
  } catch (error) { showToast(error.message, true); }
}


function advancedGroupMarkup(group) {
  return `<details class="option-group" data-option-group="${group.id}"><summary><span class="symbol" data-symbol="chevron.right"></span>${escapeHTML(group.title)}</summary><div class="option-content">${group.description ? `<p class="option-description">${escapeHTML(group.description)}</p>` : ''}${group.fields.map(optionFieldMarkup).join('')}</div></details>`;
}

function optionFieldMarkup(field) {
  if (field.type === 'heading') return `<div class="option-row"><strong>${escapeHTML(field.label)}</strong></div>`;
  if (field.type === 'toggle') return `<label class="option-row option-toggle"><span>${escapeHTML(field.label)}</span><input name="option_${field.key}" type="checkbox" role="switch"><span class="toggle-track" aria-hidden="true"></span></label>`;
  const input = field.type === 'textarea'
    ? `<textarea name="option_${field.key}" rows="2" placeholder="${escapeAttribute(field.prompt)}"></textarea>`
    : `<input name="option_${field.key}" type="text" placeholder="${escapeAttribute(field.prompt)}">`;
  return `<div class="option-row"><label for="option_${field.key}">${escapeHTML(field.label)}</label>${input}${field.help ? `<p class="option-help">${escapeHTML(field.help)}</p>` : ''}</div>`;
}

function setAdvancedExpanded(expanded) {
  ui.advancedMaster.setAttribute('aria-expanded', String(expanded));
  ui.advancedContent.setAttribute('aria-hidden', String(!expanded));
  ui.advancedContent.classList.toggle('expanded', expanded);
}

async function animateAdvancedResize(expanded) {
  const dialog = ui.moduleDialog;
  if (!dialog.open || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    setAdvancedExpanded(expanded);
    return;
  }

  const beforeHeight = dialog.getBoundingClientRect().height;
  const previousTransition = ui.advancedContent.style.transition;
  ui.advancedContent.style.transition = 'none';
  setAdvancedExpanded(expanded);
  void ui.advancedContent.offsetHeight;
  const afterHeight = dialog.getBoundingClientRect().height;
  ui.advancedContent.style.transition = previousTransition;

  if (Math.abs(afterHeight - beforeHeight) < 1) return;
  dialog.style.height = `${beforeHeight}px`;
  const animation = dialog.animate(
    [{ height: `${beforeHeight}px` }, { height: `${afterHeight}px` }],
    { duration: 280, easing: 'cubic-bezier(.2,.8,.2,1)' }
  );
  try { await animation.finished; } catch (_) {}
  dialog.style.height = '';
}

async function animateOptionGroup(group) {
  if (!group || group.dataset.animating === 'true') return;
  const content = group.querySelector('.option-content');
  if (!content) return;
  group.dataset.animating = 'true';
  const opening = !group.open;
  if (opening) {
    content.style.height = '0px';
    content.style.opacity = '0';
    group.open = true;
  }
  const fullHeight = content.scrollHeight;
  const animation = content.animate(
    opening
      ? [{ height: '0px', opacity: 0 }, { height: `${fullHeight}px`, opacity: 1 }]
      : [{ height: `${fullHeight}px`, opacity: 1 }, { height: '0px', opacity: 0 }],
    { duration: 220, easing: 'cubic-bezier(.2,.8,.2,1)' }
  );
  try { await animation.finished; } catch (_) {}
  if (!opening) group.open = false;
  content.style.height = '';
  content.style.opacity = '';
  delete group.dataset.animating;
}

function updateNativeModuleState() {
  const form = ui.moduleForm.elements;
  const url = form.sourceURL.value.trim().toLowerCase();
  const native = form.sourceFormat.value === 'surge' || (form.sourceFormat.value === 'automatic' && (url.endsWith('.sgmodule') || url.includes('/surge/')));
  ui.nativeNote.hidden = !native;
  ui.advancedOptions.hidden = native;
}

function scheduleNameLookup() {
  clearTimeout(nameLookupTimer);
  const form = ui.moduleForm.elements;
  const sourceURL = form.sourceURL.value.trim();
  if (!/^https?:\/\//i.test(sourceURL) || manualNameEdited) return;
  const sequence = ++nameLookupSequence;
  nameLookupTimer = setTimeout(async () => {
    try {
      const payload = await api('/api/source/name', { method: 'POST', json: { url: sourceURL } });
      if (sequence !== nameLookupSequence || form.sourceURL.value.trim() !== sourceURL || manualNameEdited) return;
      autoFilledName = payload.name || '';
      form.name.value = autoFilledName;
    } catch (_) {}
  }, 500);
}

function collectScriptHubOptions() {
  const options = { ...scriptHubDefaults };
  Object.keys(options).forEach(key => {
    const field = ui.moduleForm.elements[`option_${key}`];
    if (!field) return;
    options[key] = typeof options[key] === 'boolean' ? field.checked : field.value;
  });
  return options;
}

function populateScriptHubOptions(values = scriptHubDefaults) {
  const options = { ...scriptHubDefaults, ...(values || {}) };
  Object.keys(options).forEach(key => {
    const field = ui.moduleForm.elements[`option_${key}`];
    if (!field) return;
    if (typeof options[key] === 'boolean') field.checked = options[key]; else field.value = options[key] || '';
  });
  advancedGroups.forEach(group => {
    const configured = group.fields.some(field => field.key && options[field.key] !== scriptHubDefaults[field.key]);
    const element = ui.advancedOptions.querySelector(`[data-option-group="${group.id}"]`);
    if (element) element.open = configured;
  });
}

function hasAdvancedValues(values) { return Object.keys(scriptHubDefaults).some(key => (values?.[key] ?? scriptHubDefaults[key]) !== scriptHubDefaults[key]); }

function handleListClick(event) {
  if (event.target.closest('.module-toggle')) return;
  const row = event.target.closest('.module-row');
  if (row) selectItem(row.dataset.id);
}

async function handleListChange(event) {
  const input = event.target.closest('[data-module-toggle]');
  if (!input) return;
  try { await api(`/api/modules/${input.dataset.moduleToggle}/enabled`, { method: 'POST', json: { enabled: input.checked } }); await loadState(false, true); }
  catch (error) { input.checked = !input.checked; showToast(error.message, true); }
}

async function handleDetailClick(event) {
  const platformBtn = event.target.closest('#platform-segmented-control button');
  if (platformBtn) {
    selectedPlatform = platformBtn.dataset.platform;
    renderDetail(false);
    return;
  }
  const source = event.target.closest('[data-action]');
  const action = source?.dataset.action;
  if (!action) return;
  const module = state.modules.find(item => item.id === selectedID);
  switch (action) {
  case 'toggle-all-modules':
    if (source) {
      const platformId = source.dataset.platformId;
      const allEnabled = source.textContent.trim() === '全部停用';
      try {
        const result = await api(`/api/combined/platforms/${platformId}/modules/enabled`, {
          method: 'POST', json: { enabled: !allEnabled }
        });
        showToast(result.message);
        await loadState(false, true);
      } catch (error) {
        showToast(error.message, true);
      }
    }
    break;
  case 'tab-info': detailTab = 'info'; renderDetail(false); break;
  case 'tab-preview': detailTab = 'preview'; renderDetail(false); break;
  case 'edit-icon': if (module) openIconEditor(module); break;
  case 'edit-combined-icon': {
    const platform = state.platforms?.find(item => item.id === source.dataset.platformId);
    if (platform) openIconEditor({
      id: platform.id,
      name: `Surge Relay 汇总 (${platform.displayName})`,
      iconURL: platform.iconURL,
      customIconURL: platform.customIconURL,
      defaultIconURL: '/summary-icon.png?v=1',
      iconTarget: 'platform'
    });
    break;
  }
  case 'edit': if (module) openEditor(module); break;
  case 'delete': if (module) await deleteModule(module); break;
  case 'copy': await copyText(source.dataset.value, source); break;
  case 'copy-preview': await copyText(previewText, source); break;
  case 'save-preview': if (module) await savePreview(module); break;
  case 'restore-preview': if (module) await restorePreview(module); break;
  case 'preview-search-previous': movePreviewSearch(-1); break;
  case 'preview-search-next': movePreviewSearch(1); break;

  case 'accept-override': if (module) await acceptOverride(module); break;
  }
}

async function acceptOverride(module) {
  try {
    const result = await api(`/api/modules/${module.id}/override-conflict`, { method: 'POST' });
    showToast(result.message);
    await loadState(false, true);
  } catch (error) { showToast(error.message, true); }
}

async function handleDetailChange(event) {
  const platformToggle = event.target.closest('[data-platform-module-toggle]');
  if (platformToggle) {
    const platformId = platformToggle.dataset.platformId;
    const moduleId = platformToggle.dataset.platformModuleToggle;
    try {
      const result = await api(`/api/combined/platforms/${platformId}/modules/${moduleId}/enabled`, {
        method: 'POST', json: { enabled: platformToggle.checked }
      });
      showToast(result.message);
      await loadState(false, true);
    } catch (error) {
      platformToggle.checked = !platformToggle.checked;
      showToast(error.message, true);
    }
    return;
  }
  const individualExport = event.target.closest('[data-individual-icloud-export]');
  if (individualExport && selectedID !== 'combined') {
    try {
      const result = await api(`/api/modules/${selectedID}/individual-icloud-export`, {
        method: 'POST', json: { enabled: individualExport.checked }
      });
      showToast(result.message);
      await loadState(false, true);
    } catch (error) {
      individualExport.checked = !individualExport.checked;
      showToast(error.message, true);
    }
    return;
  }
  const input = event.target.closest('[data-argument-key]');
  if (!input || selectedID === 'combined') return;
  refreshArgumentActions();
}

function handleDetailInput(event) {
  if (event.target.matches('#preview-search-input')) {
    previewSearchQuery = event.target.value;
    clearTimeout(previewSearchDebounceTimer);
    if (event.isComposing) {
      previewSearchDebounceTimer = null;
      return;
    }
    previewSearchDebounceTimer = setTimeout(() => {
      previewSearchDebounceTimer = null;
      refreshPreviewSearch(true);
    }, 150);
    return;
  }
  if (!event.target.closest('[data-argument-key]')) return;
  refreshArgumentActions();
}

function refreshPreviewSearch(resetSelection = false) {
  const preserveSearchFocus = document.activeElement?.matches?.('#preview-search-input') ?? false;
  const needle = previewSearchQuery.trim();
  previewSearchMatches = [];
  if (needle.length >= 2) {
    const haystack = previewText.toLocaleLowerCase();
    const normalizedNeedle = needle.toLocaleLowerCase();
    let offset = 0;
    while ((offset = haystack.indexOf(normalizedNeedle, offset)) !== -1) {
      previewSearchMatches.push({ start: offset, end: offset + normalizedNeedle.length });
      offset += Math.max(normalizedNeedle.length, 1);
    }
  }
  if (!previewSearchMatches.length) previewSearchIndex = -1;
  else if (resetSelection || previewSearchIndex < 0 || previewSearchIndex >= previewSearchMatches.length) previewSearchIndex = 0;
  updatePreviewSearchUI();
  paintPreviewSearchMatches();
  if (previewSearchIndex >= 0) revealPreviewSearchMatch(preserveSearchFocus);
}

function movePreviewSearch(direction) {
  if (!previewSearchMatches.length) return;
  previewSearchIndex = (previewSearchIndex + direction + previewSearchMatches.length) % previewSearchMatches.length;
  updatePreviewSearchUI();
  paintPreviewSearchMatches();
  revealPreviewSearchMatch();
}

function updatePreviewSearchUI() {
  const count = document.querySelector('#preview-search-count');
  if (count) {
    const query = previewSearchQuery.trim();
    count.textContent = query.length < 2 ? '' : (previewSearchMatches.length ? `${previewSearchIndex + 1} / ${previewSearchMatches.length}` : '无结果');
  }
  document.querySelectorAll('[data-action="preview-search-previous"], [data-action="preview-search-next"]').forEach(button => { button.disabled = !previewSearchMatches.length; });
}

function paintPreviewSearchMatches() {
  const view = document.querySelector('#code-view');
  if (view) {
    // Keep the syntax DOM created at preview load. Replacing the whole tree on
    // every keystroke is visibly slow for large modules.
    unwrapPreviewSearchMatches(view);
    wrapPreviewSearchMatches(view);
  }

  const editor = document.querySelector('#code-editor');
  const layer = document.querySelector('#code-editor-highlight-layer');
  if (!editor || !layer) return;
  if (previewEditorMirrorDirty) rebuildPreviewEditorMirror();
  else unwrapPreviewSearchMatches(layer);
  const hasMatches = previewSearchMatches.length > 0;
  editor.classList.toggle('search-highlighting', hasMatches);
  layer.hidden = !hasMatches;
  if (!hasMatches) {
    return;
  }
  wrapPreviewSearchMatches(layer);
  syncPreviewEditorHighlightScroll();
}

function rebuildPreviewEditorMirror() {
  const layer = document.querySelector('#code-editor-highlight-layer');
  if (!layer) return;
  setTemplateHTML(layer, highlightCode(previewText));
  previewEditorMirrorDirty = false;
}

function unwrapPreviewSearchMatches(root) {
  const parents = new Set();
  root.querySelectorAll('.preview-search-match').forEach(mark => {
    if (mark.parentNode) parents.add(mark.parentNode);
    mark.replaceWith(...mark.childNodes);
  });
  // Rejoin adjacent text nodes so subsequent offset lookups remain cheap even
  // after many searches.
  parents.forEach(parent => parent.normalize());
}

function wrapPreviewSearchMatches(root) {
  if (!previewSearchMatches.length || previewSearchIndex < 0) return;
  const lines = [...root.querySelectorAll('.code-line')];
  const match = previewSearchMatches[previewSearchIndex];
  const line = lines.find(candidate => {
    const start = Number(candidate.dataset.sourceStart);
    const length = Number(candidate.dataset.sourceLength);
    return Number.isFinite(start) && Number.isFinite(length) && match.start >= start && match.end <= start + length;
  });
  if (!line) return;
  const lineStart = Number(line.dataset.sourceStart);
  const startBoundary = textBoundaryAtOffset(line, match.start - lineStart);
  const endBoundary = textBoundaryAtOffset(line, match.end - lineStart);
  if (!startBoundary || !endBoundary) return;
  const range = document.createRange();
  range.setStart(startBoundary.node, startBoundary.offset);
  range.setEnd(endBoundary.node, endBoundary.offset);
  if (range.collapsed) return;
  const mark = document.createElement('mark');
  mark.className = 'preview-search-match current';
  mark.dataset.searchIndex = String(previewSearchIndex);
  mark.append(range.extractContents());
  range.insertNode(mark);
}

function syncPreviewEditorHighlightScroll() {
  const editor = document.querySelector('#code-editor');
  const layer = document.querySelector('#code-editor-highlight-layer');
  if (!editor || !layer) return;
  layer.scrollTop = editor.scrollTop;
  layer.scrollLeft = editor.scrollLeft;
}

function textRangeForOffsets(root, start, end) {
  if (root.matches?.('#code-view, #code-editor-highlight-layer')) {
    const lines = [...root.querySelectorAll('.code-line')];
    for (const line of lines) {
      const lineStart = Number(line.dataset.sourceStart);
      const lineLength = Number(line.dataset.sourceLength);
      if (!Number.isFinite(lineStart) || !Number.isFinite(lineLength)) continue;
      const lineEnd = lineStart + lineLength;
      if (start < lineStart || end > lineEnd) continue;
      const startBoundary = textBoundaryAtOffset(line, start - lineStart);
      const endBoundary = textBoundaryAtOffset(line, end - lineStart);
      if (!startBoundary || !endBoundary) return null;
      const range = document.createRange();
      range.setStart(startBoundary.node, startBoundary.offset);
      range.setEnd(endBoundary.node, endBoundary.offset);
      return range;
    }
    return null;
  }
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let node;
  let offset = 0;
  let startNode = null;
  let startOffset = 0;
  while ((node = walker.nextNode())) {
    const nextOffset = offset + node.data.length;
    if (!startNode && start >= offset && start <= nextOffset) {
      startNode = node;
      startOffset = start - offset;
    }
    if (startNode && end >= offset && end <= nextOffset) {
      const range = document.createRange();
      range.setStart(startNode, startOffset);
      range.setEnd(node, end - offset);
      return range;
    }
    offset = nextOffset;
  }
  return null;
}

function textBoundaryAtOffset(root, targetOffset) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let node;
  let offset = 0;
  let lastNode = null;
  while ((node = walker.nextNode())) {
    lastNode = node;
    if (targetOffset <= offset + node.data.length) return { node, offset: targetOffset - offset };
    offset += node.data.length;
  }
  return lastNode ? { node: lastNode, offset: lastNode.data.length } : null;
}

function revealPreviewSearchMatch(preserveSearchFocus = false) {
  const match = previewSearchMatches[previewSearchIndex];
  if (!match) return;
  const editor = document.querySelector('#code-editor');
  if (editor) {
    const searchInput = preserveSearchFocus ? document.querySelector('#preview-search-input') : null;
    editor.focus({ preventScroll: true });
    editor.setSelectionRange(match.start, match.end);
    const before = editor.value.slice(0, match.start);
    const line = before.split('\n').length - 1;
    const lineHeight = parseFloat(getComputedStyle(editor).lineHeight) || 19;
    editor.scrollTop = Math.max(0, line * lineHeight - editor.clientHeight * .42);
    if (searchInput) searchInput.focus({ preventScroll: true });
    return;
  }
  const view = document.querySelector('#code-view');
  if (!view) return;
  const currentMark = view.querySelector(`.preview-search-match[data-search-index="${previewSearchIndex}"]`);
  const range = currentMark ? null : textRangeForOffsets(view, match.start, match.end);
  const rect = currentMark?.getBoundingClientRect() ?? range?.getBoundingClientRect();
  const viewRect = view.getBoundingClientRect();
  if (rect) view.scrollTop += rect.top - viewRect.top - view.clientHeight * .42;
}

function selectItem(id, pushHistory = true) {
  if (!state) return;
  if (id.startsWith('combined-')) {
    selectedPlatform = id.substring(9);
  } else if (!state.modules.some(module => module.id === id)) {
    id = 'combined-' + selectedPlatform;
  }
  const cameFromList = mobileLayout.matches && !ui.body.classList.contains('has-selection');
  if (cameFromList) listScrollY = ui.navigation?.scrollTop || 0;
  selectedID = id; detailTab = 'info'; ui.body.classList.add('has-selection');
  if (pushHistory) {
    const url = new URL(location.href);
    url.searchParams.set('module', id);
    const relayIndex = Number(history.state?.relayIndex ?? 0) + 1;
    history.pushState({ surgeRelay: true, view: 'detail', module: id, cameFromList, relayIndex, relayMaxIndex: relayIndex }, '', url);
  }
  renderSidebar(); renderDetail(false);
  updateDesktopNavigationButtons();
  if (mobileLayout.matches) ui.detail.scrollTop = 0;
}

function initializeHistoryState() {
  const module = new URL(location.href).searchParams.get('module');
  if (history.state?.surgeRelay) return;
  if (module) {
    const detailURL = new URL(location.href);
    const listURL = new URL(location.href);
    listURL.searchParams.delete('module');
    history.replaceState({ surgeRelay: true, view: 'list', module: null, relayIndex: 0, relayMaxIndex: 1 }, '', listURL);
    history.pushState({ surgeRelay: true, view: 'detail', module, cameFromList: true, relayIndex: 1, relayMaxIndex: 1 }, '', detailURL);
  } else {
    history.replaceState({ surgeRelay: true, view: 'list', module: null, relayIndex: 0, relayMaxIndex: 0 }, '', location.href);
  }
  updateDesktopNavigationButtons();
}

function showModuleList(replaceHistory = false) {
  selectedID = null;
  detailTab = 'info';
  ui.body.classList.remove('has-selection', 'preview-mode');
  const url = new URL(location.href);
  url.searchParams.delete('module');
  if (replaceHistory) history.replaceState({ surgeRelay: true, view: 'list', module: null, relayIndex: 0, relayMaxIndex: 0 }, '', url);
  renderSidebar();
  renderDetail(false);
  updateDesktopNavigationButtons();
  if (mobileLayout.matches) requestAnimationFrame(() => { if (ui.navigation) ui.navigation.scrollTop = listScrollY; });
}

function navigateBackToList() {
  if (!mobileLayout.matches) return;
  if (history.state?.surgeRelay && history.state?.cameFromList) history.back();
  else showModuleList(true);
}

function handleHistoryNavigation(event) {
  const module = new URL(location.href).searchParams.get('module');
  if (!module || event.state?.view === 'list') {
    showModuleList(false);
    updateDesktopNavigationButtons();
    return;
  }
  selectItem(module || 'combined', false);
  updateDesktopNavigationButtons();
}

function cleanSearchQuery(query) {
  if (!query) return '';
  let cleaned = query;
  // Remove parentheses and content: (...) and （...）
  cleaned = cleaned.replace(/\([^)]*\)/g, '');
  cleaned = cleaned.replace(/（[^）]*）/g, '');
  cleaned = cleaned.replace(/去广告/g, '');
  cleaned = cleaned.replace(/净化/g, '');
  return cleaned.trim();
}

let currentIconEditingModule = null;
let pendingIconURL = null;
let hasPendingIconSelection = false;

function updateIconEditorPreview(url) {
  const preview = document.getElementById('icon-editor-preview');
  if (!preview) return;
  setTemplateHTML(preview, url ? `<img src="${escapeAttribute(url)}" alt="">` : '');
}

function openIconEditor(module) {
  currentIconEditingModule = module;
  
  const customInput = document.getElementById('custom-icon-url-input');
  const searchInput = document.getElementById('icon-search-input');
  const resultsContainer = document.getElementById('icon-search-results');
  const resetContainer = document.getElementById('reset-icon-container');
  const regionSelect = document.getElementById('icon-search-region-select');
  
  pendingIconURL = module.customIconURL || null;
  hasPendingIconSelection = false;
  customInput.value = module.customIconURL || '';
  resetContainer.hidden = !module.customIconURL;
  searchInput.value = cleanSearchQuery(module.name);
  if (regionSelect) {
    regionSelect.value = state.settings?.iconSearchRegion || 'cn';
  }
  updateIconEditorPreview(module.iconURL || module.customIconURL || '');
  setTemplateHTML(resultsContainer, '<div class="icon-search-empty">请输入关键字进行搜索</div>');
  
  openDialog(ui.iconDialog);
  requestAnimationFrame(() => performIconSearch());
}

async function performIconSearch() {
  const searchInput = document.getElementById('icon-search-input');
  const resultsContainer = document.getElementById('icon-search-results');
  const regionSelect = document.getElementById('icon-search-region-select');
  
  const rawQuery = searchInput.value;
  const query = cleanSearchQuery(rawQuery);
  searchInput.value = query;
  
  const region = regionSelect ? regionSelect.value : 'cn';
  
  if (!query) {
    setTemplateHTML(resultsContainer, '<div class="icon-search-empty">请输入关键字进行搜索</div>');
    return;
  }
  
  setTemplateHTML(resultsContainer, '<div class="icon-search-empty icon-search-loading"><span class="loading-spinner"></span><span>正在搜索…</span></div>');
  
  try {
    const results = await api(`/api/appstore/search?q=${encodeURIComponent(query)}&region=${encodeURIComponent(region)}`);
    if (!results || results.length === 0) {
      setTemplateHTML(resultsContainer, '<div class="icon-search-empty">未找到相关图标</div>');
      return;
    }
    
    setTemplateHTML(resultsContainer, results.map(result => `
      <button class="icon-search-item${result.url === pendingIconURL ? ' selected' : ''}" data-url="${escapeAttribute(result.url)}" type="button" title="${escapeAttribute(result.name || '')}" aria-label="${escapeAttribute(result.name || '选择图标')}" aria-pressed="${result.url === pendingIconURL ? 'true' : 'false'}">
        <img src="${escapeAttribute(result.url)}" alt="" loading="lazy">
      </button>
    `).join(''));
    
    resultsContainer.querySelectorAll('.icon-search-item').forEach(item => {
      item.addEventListener('click', () => {
        pendingIconURL = item.dataset.url;
        hasPendingIconSelection = true;
        document.getElementById('custom-icon-url-input').value = '';
        document.getElementById('reset-icon-container').hidden = false;
        resultsContainer.querySelectorAll('.icon-search-item').forEach(candidate => {
          const selected = candidate === item;
          candidate.classList.toggle('selected', selected);
          candidate.setAttribute('aria-pressed', selected ? 'true' : 'false');
        });
        updateIconEditorPreview(pendingIconURL);
      });
    });
  } catch (error) {
    setTemplateHTML(resultsContainer, `<div class="icon-search-empty icon-search-error">搜索失败：${escapeHTML(error.message)}</div>`);
  }
}

async function applyCustomIcon(url) {
  if (!currentIconEditingModule) return;
  const targetPath = currentIconEditingModule.iconTarget === 'platform'
    ? `/api/combined/platforms/${currentIconEditingModule.id}/custom-icon`
    : `/api/modules/${currentIconEditingModule.id}/custom-icon`;
  try {
    const result = await api(targetPath, {
      method: 'PUT',
      json: { url }
    });
    showToast(result.message);
    closeDialog(ui.iconDialog);
    await loadState(false, true);
  } catch (error) {
    showToast(error.message, true);
  }
}

async function commitIconDraft() {
  if (!currentIconEditingModule) return;
  if (!hasPendingIconSelection) {
    closeDialog(ui.iconDialog);
    return;
  }
  try {
    const targetPath = currentIconEditingModule.iconTarget === 'platform'
      ? `/api/combined/platforms/${currentIconEditingModule.id}/custom-icon`
      : `/api/modules/${currentIconEditingModule.id}/custom-icon`;
    const result = pendingIconURL
      ? await api(targetPath, { method: 'PUT', json: { url: pendingIconURL } })
      : await api(targetPath, { method: 'DELETE' });
    showToast(result.message);
    closeDialog(ui.iconDialog);
    await loadState(false, true);
  } catch (error) {
    showToast(error.message, true);
  }
}

async function resetCustomIcon() {
  if (!currentIconEditingModule) return;
  pendingIconURL = null;
  hasPendingIconSelection = true;
  document.getElementById('custom-icon-url-input').value = '';
  document.getElementById('reset-icon-container').hidden = true;
  const resultsContainer = document.getElementById('icon-search-results');
  resultsContainer.querySelectorAll('.icon-search-item').forEach(item => item.classList.remove('selected'));
  updateIconEditorPreview(currentIconEditingModule.defaultIconURL || '');
}

function openEditor(module = null) {
  clearTimeout(nameLookupTimer);
  nameLookupSequence += 1;
  editingID = module?.id || null;
  ui.moduleDialogMessage.hidden = true;
  ui.moduleDialogMessage.textContent = '';
  ui.dialogTitle.textContent = module ? '编辑模块' : '添加模块';
  ui.saveModule.textContent = module ? '保存' : '添加';
  const form = ui.moduleForm.elements;
  form.name.value = module?.name || '';
  autoFilledName = module?.name || '';
  manualNameEdited = Boolean(module);
  form.sourceURL.value = module?.sourceURL || '';
  form.sourceFormat.value = module?.sourceFormat || 'automatic';
  form.isEnabled.checked = module?.isEnabled ?? true;
  populateScriptHubOptions(module?.scriptHubOptions || scriptHubDefaults);
  setAdvancedExpanded(Boolean(module?.advancedSummary || hasAdvancedValues(module?.scriptHubOptions)));
  updateNativeModuleState();
  openDialog(ui.moduleDialog);
  const formContent = ui.moduleDialog.querySelector('.form-content');
  if (formContent) formContent.scrollTop = 0;
  setTimeout(() => (module ? form.name : form.sourceURL).focus(), 180);
}

async function saveModule(event) {
  event.preventDefault();
  const form = ui.moduleForm.elements;
  const payload = { name: form.name.value.trim(), sourceURL: form.sourceURL.value.trim(), sourceFormat: form.sourceFormat.value, isEnabled: form.isEnabled.checked, scriptHubOptions: collectScriptHubOptions() };
  ui.saveModule.disabled = true;
  try {
    const path = editingID ? `/api/modules/${editingID}` : '/api/modules';
    const result = await api(path, { method: editingID ? 'PUT' : 'POST', json: payload });
    await closeDialog(ui.moduleDialog);
    showToast(result.message);
    await loadState(false, true);
  } catch (error) {
    ui.moduleDialogMessage.textContent = error.message;
    ui.moduleDialogMessage.hidden = false;
  }
  finally { ui.saveModule.disabled = false; }
}

async function updateAll() {
  try { const result = await api('/api/update-all', { method: 'POST' }); showToast(result.message); await loadState(false, false); }
  catch (error) { showToast(error.message, true); }
}

function openWebSettings() {
  settingsPane = 'general';
  settingsMenuOpen = false;
  settingsDraftStorageMode = null;
  settingsDraftDirty = false;
  renderWebSettings();
  openDialog(ui.settingsDialog);
}

function renderWebSettings(animateResize = false) {
  const settings = state?.settings;
  if (!settings) {
    setTemplateHTML(ui.settingsContent, '<div class="empty-state"><p>设置尚未载入。</p></div>');
    return;
  }
  const beforeHeight = animateResize && ui.settingsDialog?.open ? ui.settingsDialog.getBoundingClientRect().height : null;
  if (!SETTINGS_PANES.some(([id]) => id === settingsPane)) settingsPane = 'general';
  setTemplateHTML(ui.settingsContent, `
    <div class="settings-layout ${settingsMenuOpen ? 'menu-open' : ''}">
      <div class="settings-nav-backdrop" data-settings-action="close-settings-menu"></div>
      <nav class="settings-nav" aria-label="设置分类">
        ${SETTINGS_PANES.map(([id, title, icon]) => `<button type="button" data-settings-pane="${id}" class="${settingsPane === id ? 'selected' : ''}"><span class="symbol" data-symbol="${icon}"></span>${title}</button>`).join('')}
      </nav>
      <div class="settings-pane">${settingsPaneMarkup(settings)}</div>
    </div>`);
  if (beforeHeight) animateSettingsDialogResize(beforeHeight);
}

function animateSettingsDialogResize(beforeHeight) {
  const dialog = ui.settingsDialog;
  if (!dialog || !dialog.open || !matchMedia('(max-width: 700px)').matches) return;
  requestAnimationFrame(() => {
    const afterHeight = dialog.getBoundingClientRect().height;
    if (Math.abs(afterHeight - beforeHeight) < 2) return;
    dialog.animate(
      [{ height: `${beforeHeight}px` }, { height: `${afterHeight}px` }],
      { duration: 220, easing: 'cubic-bezier(.2,.8,.2,1)' }
    );
  });
}

function settingsPaneMarkup(settings) {
  switch (settingsPane) {
  case 'scriptHub': return scriptHubSettingsMarkup(settings);
  case 'sync': return syncSettingsMarkup(settings);
  case 'diagnostics': return diagnosticsSettingsMarkup(settings);
  case 'about': return aboutSettingsMarkup(settings);
  case 'general':
  default: return generalSettingsMarkup(settings);
  }
}

function generalSettingsMarkup(settings) {
  return `
    <section class="editor-section"><h3>配置目录</h3><div class="editor-group">
      <div class="settings-info-row"><strong>配置与同步目录</strong><span>iCloud/Surge/Surge Relay</span><small>Surge Relay 的配置与同步状态保存在 iCloud 云盘中。</small></div>
    </div></section>
    <section class="editor-section"><h3>自动化</h3><div class="editor-group">
      <label class="form-row compact-control-row"><span>刷新间隔</span><select data-settings-control="refreshIntervalMinutes">
        ${[[0,'手动'],[15,'每 15 分钟'],[60,'每小时'],[360,'每 6 小时'],[720,'每 12 小时']].map(([value,label]) => `<option value="${value}" ${settings.refreshIntervalMinutes === value ? 'selected' : ''}>${label}</option>`).join('')}
      </select></label>
      ${settingsSwitchRow('登录时启动 Surge Relay', 'launchAtLogin', settings.launchAtLogin)}
      ${settingsSwitchRow('自动同步', 'automaticallyPublish', settings.automaticallyPublish)}
    </div></section>
    <section class="editor-section"><h3>汇总平台</h3><div class="editor-group">
      ${settingsSwitchRow('生成 Surge Relay 汇总 (iOS)', 'platform-iOS', settings.platforms?.iOS)}
      ${settingsSwitchRow('生成 Surge Relay 汇总 (macOS)', 'platform-macOS', settings.platforms?.macOS)}
      ${settingsSwitchRow('生成 Surge Relay 汇总 (tvOS)', 'platform-tvOS', settings.platforms?.tvOS)}
      ${settingsSwitchRow('生成 Surge Relay 汇总 (visionOS)', 'platform-visionOS', settings.platforms?.visionOS)}
    </div></section>`;
}

function scriptHubSettingsMarkup(settings) {
  return `
    <section class="editor-section"><h3>上游引擎</h3><div class="editor-group">
      <div class="settings-info-row"><strong>版本</strong><span>${escapeHTML(settings.scriptHubRevision ? settings.scriptHubRevision.slice(0, 7) : '—')}</span><small>上次检查：${escapeHTML(formatDate(settings.scriptHubLastCheckedAt, '尚未检查'))}</small></div>
      <label class="form-row"><span>上游模块</span><input type="url" data-settings-control="scriptHubModuleURL" value="${escapeAttribute(settings.scriptHubModuleURL)}"></label>
      ${settingsSwitchRow('自动更新', 'automaticallyUpdateScriptHub', settings.automaticallyUpdateScriptHub)}
      ${settings.scriptHubLastError ? `<div class="dialog-message settings-inline-message">${escapeHTML(settings.scriptHubLastError)}</div>` : ''}
      <div class="settings-inline-actions"><button class="button" data-settings-action="refresh-script-hub"><span class="symbol" data-symbol="refresh"></span>检查更新</button></div>
    </div></section>`;
}

function syncSettingsMarkup(settings) {
  const selectedMode = settingsDraftStorageMode || settings.storageMode || 'local';
  const tokenPlaceholder = settings.githubTokenConfigured ? '已保存，留空则保持不变' : 'GitHub Token';
  return `
    <section class="editor-section"><div class="editor-group">
      <div class="settings-sync-mode-row">
        <strong>同步方式</strong>
        <div class="settings-segmented" role="radiogroup" aria-label="同步方式">
          <button type="button" data-settings-mode="local" class="${selectedMode === 'local' ? 'selected' : ''}">iCloud 云盘</button>
          <button type="button" data-settings-mode="gitHub" class="${selectedMode === 'gitHub' ? 'selected' : ''}">GitHub 私有仓库</button>
        </div>
      </div>
    </div></section>
    ${selectedMode === 'local' ? iCloudSyncSettingsMarkup(settings) : githubSyncSettingsMarkup(settings, tokenPlaceholder)}`;
}

function iCloudSyncSettingsMarkup(settings) {
  return `
    <section class="editor-section settings-sync-section"><h3>iCloud 云盘</h3><div class="group-box settings-sync-box">
      <div class="icloud-sync-card"><img src="/icloud-icon.png?v=2" alt=""><div class="icloud-sync-copy"><strong>通过 iCloud 保持 Surge Relay 同步</strong><span>汇总模块保存在 iCloud 云盘的 Surge 文件夹中。</span></div></div>
      ${settings.storageMode === 'local' ? '<div class="settings-success">当前通过 iCloud 云盘同步，汇总模块已在 Surge 文件夹中生成，请在 Surge 中勾选 Surge Relay 模块。</div>' : ''}
    </div>${settings.storageMode !== 'local' ? '<div class="settings-actions settings-actions-footer settings-sync-footer"><button class="button primary" data-settings-action="switch-storage" data-mode="local">切换到 iCloud 云盘</button></div>' : ''}</section>`;
}

function githubSyncSettingsMarkup(settings, tokenPlaceholder) {
  const selectedMode = settingsDraftStorageMode || settings.storageMode || 'local';
  const isStoredGitHub = settings.storageMode === 'gitHub';
  const isVerified = isStoredGitHub && settings.githubRepositoryIsPrivate === true && Boolean(settings.githubPublicBaseURL);
  const showsTestButton = isStoredGitHub && (settingsDraftDirty || !isVerified);
  const showsSwitchButton = selectedMode === 'gitHub' && !isStoredGitHub;
  const actions = [
    showsTestButton ? '<button class="button" data-settings-action="test-github">验证并保存配置</button>' : '',
    showsSwitchButton ? '<button class="button primary" data-settings-action="switch-storage" data-mode="gitHub">验证并切换到 GitHub</button>' : ''
  ].filter(Boolean).join('');
  return `
    <section class="editor-section settings-sync-section"><h3>GitHub 私有仓库</h3><div class="group-box settings-sync-box">
      <div class="icloud-sync-card"><img src="/github-icon.png?v=2" alt=""><div class="icloud-sync-copy"><strong>通过私有仓库同步</strong><span>Surge Relay 会验证仓库权限，并通过 Cloudflare 提供设备可访问的稳定订阅。</span></div></div>
      <div class="settings-field-stack">
        <label><span>仓库地址</span><input type="url" data-settings-control="githubRepository" value="${escapeAttribute(settings.githubRepository)}"></label>
        <label><span>GitHub Token</span><input type="password" data-settings-control="githubToken" placeholder="${escapeAttribute(tokenPlaceholder)}"></label>
        <label><span>公共地址</span><input type="url" data-settings-control="githubPublicBaseURL" value="${escapeAttribute(settings.githubPublicBaseURL)}"></label>
      </div>
      <div class="settings-info-row"><small>公共地址用于生成可在 Surge 中长期使用的稳定订阅地址。</small></div>
      ${settings.storageMode === 'gitHub' && settings.githubRepositoryIsPrivate === true ? '<div class="settings-success">GitHub 与 Cloudflare 已验证，汇总模块将通过 GitHub 私有仓库同步并通过 Cloudflare Worker 分发。</div>' : ''}
    </div>${actions ? `<div class="settings-actions settings-actions-footer settings-sync-footer">${actions}</div>` : ''}</section>`;
}

function diagnosticsSettingsMarkup(settings) {
  const rows = settings.updateHistory?.length
    ? settings.updateHistory.map(entry => `<div class="settings-history-row"><div><strong>${escapeHTML(entry.moduleName || '—')}</strong><small>${escapeHTML(entry.message || localizedOutcome(entry.outcome) || '')}</small></div><span>${escapeHTML(localizedOutcome(entry.outcome))}</span></div>`).join('')
    : '<div class="settings-info-row"><strong>暂无更新记录</strong><small>完成一次同步后，结果会显示在这里。</small></div>';
  return `<section class="editor-section"><h3>最近更新</h3><div class="editor-group">${rows}</div><div class="editor-group settings-action-group"><button class="button" data-settings-action="export-diagnostics"><span class="symbol" data-symbol="square.and.arrow.up"></span>导出诊断</button><button class="button destructive" data-settings-action="clear-diagnostics">清除历史</button></div></section>`;
}

function aboutSettingsMarkup(settings) {
  return `
    <section class="editor-section"><div class="settings-about-hero"><img src="/app-icon.png?v=3" alt=""><strong>Surge Relay</strong><span>版本 ${escapeHTML(settings.appVersion || '—')}</span></div></section>
    <section class="editor-section"><h3>项目</h3><div class="editor-group">
      ${settingsLinkRow('/github-icon.png?v=2', 'Surge Relay', 'EEliberto/SurgeRelay-macOS', 'https://github.com/EEliberto/SurgeRelay-macOS')}
      ${settingsLinkRow('/script-hub-icon.png?v=2', 'Script Hub', 'github.com/Script-Hub-Org', 'https://github.com/Script-Hub-Org')}
      ${settingsLinkRow('/surge-icon.png?v=2', 'Surge', 'nssurge.com', 'https://nssurge.com')}
    </div></section>`;
}

function settingsLinkRow(icon, title, detail, url) {
  return `<a class="settings-link-row" href="${escapeAttribute(url)}" target="_blank" rel="noreferrer"><img src="${icon}" alt=""><span><strong>${escapeHTML(title)}</strong><small>${escapeHTML(detail)}</small></span><span class="symbol disclosure" data-symbol="chevron.right"></span></a>`;
}

function settingsSwitchRow(label, key, checked) {
  return `<div class="form-row switch-row"><span>${escapeHTML(label)}</span><label class="switch-control" aria-label="${escapeAttribute(label)}"><input type="checkbox" data-settings-control="${escapeAttribute(key)}" ${checked ? 'checked' : ''}><span class="toggle-track" aria-hidden="true"></span></label></div>`;
}

function readSettingsControl(key) {
  return ui.settingsContent.querySelector(`[data-settings-control="${key}"]`);
}

function githubSettingsPayload(mode = null) {
  const payload = {
    githubRepository: readSettingsControl('githubRepository')?.value?.trim(),
    githubPublicBaseURL: readSettingsControl('githubPublicBaseURL')?.value?.trim()
  };
  const token = readSettingsControl('githubToken')?.value?.trim();
  if (token) payload.githubToken = token;
  if (mode) payload.storageMode = mode;
  return payload;
}

async function handleSettingsClick(event) {
  const paneButton = event.target.closest('[data-settings-pane]');
  if (paneButton) {
    settingsPane = paneButton.dataset.settingsPane;
    settingsMenuOpen = false;
    settingsDraftDirty = false;
    renderWebSettings(true);
    return;
  }
  const modeButton = event.target.closest('[data-settings-mode]');
  if (modeButton) {
    settingsDraftStorageMode = modeButton.dataset.settingsMode;
    settingsDraftDirty = false;
    renderWebSettings(true);
    return;
  }
  const action = event.target.closest('[data-settings-action]');
  if (!action) return;
  const shouldShowLoading = ['refresh-script-hub', 'test-github', 'switch-storage', 'clear-diagnostics'].includes(action.dataset.settingsAction);
  if (shouldShowLoading) {
    action.disabled = true;
    action.classList.add('loading');
  }
  try {
    if (action.dataset.settingsAction === 'close-settings-menu') {
      settingsMenuOpen = false;
      ui.settingsContent?.querySelector('.settings-layout')?.classList.remove('menu-open');
      return;
    }
    if (action.dataset.settingsAction === 'copy-settings-url') {
      await copyText(action.dataset.value || '', action);
      return;
    }
    if (action.dataset.settingsAction === 'refresh-script-hub') {
      await api('/api/settings/script-hub/refresh', { method: 'POST' });
    } else if (action.dataset.settingsAction === 'test-github') {
      await api('/api/settings/sync/test', { method: 'POST', json: githubSettingsPayload() });
    } else if (action.dataset.settingsAction === 'switch-storage') {
      const mode = action.dataset.mode;
      const payload = mode === 'gitHub' ? githubSettingsPayload(mode) : { storageMode: mode };
      if (mode === 'gitHub') await api('/api/settings/sync/test', { method: 'POST', json: payload });
      await api('/api/settings/sync', { method: 'PUT', json: payload });
    } else if (action.dataset.settingsAction === 'clear-diagnostics') {
      await api('/api/settings/diagnostics/clear', { method: 'POST' });
    } else if (action.dataset.settingsAction === 'export-diagnostics') {
      location.href = '/api/settings/diagnostics/export';
      return;
    }
    await loadState(false, true);
    settingsDraftStorageMode = null;
    settingsDraftDirty = false;
    renderWebSettings();
  } catch (error) {
    action.disabled = false;
    action.classList.remove('loading');
    showToast(error.message, true);
  }
}

function handleSettingsInput(event) {
  const control = event.target.closest('[data-settings-control]');
  if (!control) return;
  if (['githubRepository', 'githubToken', 'githubPublicBaseURL'].includes(control.dataset.settingsControl)) {
    settingsDraftDirty = true;
    const testButton = ui.settingsContent.querySelector('[data-settings-action="test-github"]');
    if (testButton && state?.settings?.storageMode === 'gitHub') testButton.hidden = false;
  }
}

async function handleSettingsChange(event) {
  const control = event.target.closest('[data-settings-control]');
  if (!control) return;
  const key = control.dataset.settingsControl;
  try {
    if (['refreshIntervalMinutes', 'launchAtLogin', 'automaticallyPublish', 'iconSearchRegion'].includes(key)) {
      const payload = {};
      if (key === 'refreshIntervalMinutes') payload.refreshIntervalMinutes = Number(control.value);
      else if (key === 'iconSearchRegion') payload.iconSearchRegion = control.value;
      else payload[key] = control.checked;
      await api('/api/settings/general', { method: 'PUT', json: payload });
      await loadState(false, false);
    } else if (key.startsWith('platform-')) {
      const platformName = key.substring(9);
      const payload = { platforms: {} };
      payload.platforms[platformName] = control.checked;
      await api('/api/settings/general', { method: 'PUT', json: payload });
      await loadState(false, true);
      renderWebSettings();
    } else if (['webServerEnabled', 'webServerPort'].includes(key)) {
      await api('/api/settings/web', { method: 'PUT', json: { webServerEnabled: readSettingsControl('webServerEnabled')?.checked, webServerPort: Number(readSettingsControl('webServerPort')?.value || 0) } });
      await loadState(false, false);
      renderWebSettings();
    } else if (['scriptHubModuleURL', 'automaticallyUpdateScriptHub'].includes(key)) {
      await api('/api/settings/script-hub', { method: 'PUT', json: { scriptHubModuleURL: readSettingsControl('scriptHubModuleURL')?.value?.trim(), automaticallyUpdateScriptHub: readSettingsControl('automaticallyUpdateScriptHub')?.checked } });
      await loadState(false, false);
    }
  } catch (error) {
    showToast(error.message, true);
    await loadState(false, false);
    renderWebSettings();
  }
}

function localizedOutcome(outcome) {
  switch (outcome) {
  case 'updated': return '已更新';
  case 'unchanged': return '没有变化';
  case 'failed': return '失败';
  case 'skipped': return '已跳过';
  default: return outcome || '';
  }
}


async function deleteModule(module) {
  const accepted = await askConfirmation('删除模块？', `“${module.name}”会从 Surge Relay 和总模块中移除。`, '删除');
  if (!accepted) return;
  try { const result = await api(`/api/modules/${module.id}`, { method: 'DELETE' }); selectedID = 'combined'; showToast(result.message); await loadState(false, true); }
  catch (error) { showToast(error.message, true); }
}

async function savePreview(module) {
  try { const result = await api(`/api/modules/${module.id}/preview`, { method: 'PUT', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: previewText }); previewSavedText = previewText; document.querySelector('[data-action="save-preview"]').disabled = true; showToast(result.message); }
  catch (error) { showToast(error.message, true); }
}

async function restorePreview(module) {
  if (!await askConfirmation('恢复转换结果？', `“${module.name}”的手动修改会被丢弃。`, '恢复')) return;
  try { const text = await api(`/api/modules/${module.id}/preview`, { method: 'DELETE' }); const editor = document.querySelector('#code-editor'); if (editor) editor.value = text; previewText = text; previewSavedText = text; previewEditorMirrorDirty = true; document.querySelector('[data-action="save-preview"]').disabled = true; refreshPreviewSearch(false); showToast('已恢复转换结果'); }
  catch (error) { showToast(error.message, true); }
}



function openDialog(dialog) {
  dialog.classList.remove('is-closing');
  lockDialogScroll();
  dialog.showModal();
}
function closeDialog(dialog) {
  return new Promise(resolve => {
    if (!dialog.open) return resolve();
    dialog.classList.add('is-closing');
    setTimeout(() => {
      dialog.close();
      dialog.classList.remove('is-closing');
      unlockDialogScrollIfIdle();
      resolve();
    }, 165);
  });
}

function lockDialogScroll() {
  if (document.body.classList.contains('dialog-open')) return;
  dialogScrollY = window.scrollY || document.documentElement.scrollTop || 0;
  document.body.classList.add('dialog-open');
  document.body.style.position = 'fixed';
  document.body.style.top = `-${dialogScrollY}px`;
  document.body.style.left = '0';
  document.body.style.right = '0';
  document.body.style.width = '100%';
}

function unlockDialogScrollIfIdle() {
  if ([ui.moduleDialog, ui.settingsDialog, ui.confirmDialog, ui.iconDialog].some(item => item?.open)) return;
  if (!document.body.classList.contains('dialog-open')) return;
  document.body.classList.remove('dialog-open');
  document.body.style.position = '';
  document.body.style.top = '';
  document.body.style.left = '';
  document.body.style.right = '';
  document.body.style.width = '';
  window.scrollTo(0, dialogScrollY);
}

function askConfirmation(title, message, acceptLabel = '确认') { ui.confirmTitle.textContent = title; ui.confirmMessage.textContent = message; ui.confirmAccept.textContent = acceptLabel; openDialog(ui.confirmDialog); return new Promise(resolve => { confirmResolver = resolve; }); }
async function resolveConfirmation(value) { const resolver = confirmResolver; confirmResolver = null; await closeDialog(ui.confirmDialog); resolver?.(value); }

async function copyText(text, button = null) {
  try {
    const value = text || '';
    let copied = false;
    if (window.isSecureContext && navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(value);
        copied = true;
      } catch (_) {
        copied = copyTextWithoutFocus(value);
      }
    } else {
      copied = copyTextWithoutFocus(value);
    }
    if (!copied) throw new Error('copy failed');
    showCopySuccess(button);
  } catch (_) {
    showToast('拷贝失败', true);
  }
}

function copyTextWithoutFocus(text) {
  const selection = window.getSelection();
  if (!selection) return false;
  const previousRanges = [];
  for (let index = 0; index < selection.rangeCount; index += 1) previousRanges.push(selection.getRangeAt(index).cloneRange());

  const target = document.createElement('span');
  target.textContent = text;
  target.setAttribute('aria-hidden', 'true');
  Object.assign(target.style, {
    position: 'fixed', top: '0', left: '0', opacity: '0', pointerEvents: 'none',
    whiteSpace: 'pre', userSelect: 'text', webkitUserSelect: 'text'
  });
  document.body.append(target);

  let copied = false;
  try {
    const range = document.createRange();
    range.selectNodeContents(target);
    selection.removeAllRanges();
    selection.addRange(range);
    copied = document.execCommand('copy');
  } finally {
    selection.removeAllRanges();
    previousRanges.forEach(range => selection.addRange(range));
    target.remove();
  }
  return copied;
}

function showCopySuccess(button) {
  if (!button) return;
  if (!button.hasAttribute('data-copy-label')) button.dataset.copyLabel = button.innerHTML;
  clearTimeout(Number(button.dataset.copyTimer || 0));
  button.classList.remove('copy-success');
  void button.offsetWidth;
  setTemplateHTML(button, '<span class="symbol" data-symbol="checkmark"></span>拷贝成功');
  button.classList.add('copy-success');
  const timer = setTimeout(() => {
    if (!button.isConnected) return;
    setTemplateHTML(button, button.dataset.copyLabel);
    button.classList.remove('copy-success');
    delete button.dataset.copyLabel;
    delete button.dataset.copyTimer;
  }, 1600);
  button.dataset.copyTimer = String(timer);
}

function highlightCode(text) {
  let sourceOffset = 0;
  return text.split('\n').map(line => {
    const lineStart = sourceOffset;
    sourceOffset += line.length + 1;
    const sourceAttributes = ` data-source-start="${lineStart}" data-source-length="${line.length}"`;
    const trimmed = line.trim();
    if (/^\[[^\]]+\]$/.test(trimmed)) return `<span class="code-line code-section"${sourceAttributes}>${escapeHTML(line)}</span>`;
    if (/^(#|\/\/|;)/.test(trimmed)) return `<span class="code-line code-comment"${sourceAttributes}>${escapeHTML(line)}</span>`;
    const value = highlightInlineCode(line);
    return `<span class="code-line"${sourceAttributes}>${value || '<br>'}</span>`;
  }).join('');
}

function highlightInlineCode(line) {
  let output = '';
  let cursor = 0;
  const keyMatch = line.match(/^([A-Za-z][A-Za-z0-9_-]*)(\s*=)/);
  if (keyMatch) {
    output += `<span class="code-key">${escapeHTML(keyMatch[1])}</span>${escapeHTML(keyMatch[2])}`;
    cursor = keyMatch[0].length;
  }

  const tokenPattern = /(https?:\/\/[^\s,<>&]+)|\b(\d+(?:\.\d+)?)\b/g;
  tokenPattern.lastIndex = cursor;
  let match;
  while ((match = tokenPattern.exec(line)) !== null) {
    output += escapeHTML(line.slice(cursor, match.index));
    output += match[1]
      ? `<span class="code-url">${escapeHTML(match[0])}</span>`
      : `<span class="code-number">${escapeHTML(match[0])}</span>`;
    cursor = match.index + match[0].length;
  }
  output += escapeHTML(line.slice(cursor));
  return output;
}

function showToast(message, isError = false) {
  clearTimeout(toastTimer);
  const topDialog = [ui.confirmDialog, ui.iconDialog, ui.moduleDialog, ui.settingsDialog].find(dialog => dialog?.open);
  if (topDialog && ui.toast.parentElement !== topDialog) topDialog.appendChild(ui.toast);
  if (!topDialog && ui.toast.parentElement !== document.body) document.body.appendChild(ui.toast);
  ui.toast.textContent = message;
  ui.toast.classList.toggle('error', isError);
  ui.toast.classList.add('visible');
  toastTimer = setTimeout(() => {
    ui.toast.classList.remove('visible');
    if (ui.toast.parentElement !== document.body) document.body.appendChild(ui.toast);
  }, 2600);
}
function formatDate(value, fallback = '—') { if (!value) return fallback; const date = new Date(value); if (Number.isNaN(date.valueOf())) return fallback; return new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeStyle: 'medium' }).format(date); }
function escapeHTML(value) { return String(value ?? '').replace(/[&<>'"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character]); }
function escapeAttribute(value) { return escapeHTML(value); }
