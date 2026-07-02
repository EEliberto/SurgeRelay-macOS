const ui = {
  body: document.body,
  list: document.querySelector('#module-list'),
  summaryRow: document.querySelector('#summary-row'),
  summarySubtitle: document.querySelector('#summary-subtitle'),
  detailRoot: document.querySelector('#detail'),
  detail: document.querySelector('#detail-content'),
  search: document.querySelector('#search-input'),
  add: document.querySelector('#add-button'),
  refresh: document.querySelector('#refresh-button'),
  back: document.querySelector('#mobile-back'),
  mobileTitle: document.querySelector('#mobile-title'),
  desktopTitle: document.querySelector('#desktop-title'),
  desktopActions: document.querySelector('#desktop-detail-actions'),
  status: document.querySelector('#activity-status'),
  percent: document.querySelector('#activity-percent'),
  progressTrack: document.querySelector('#progress-track'),
  progressFill: document.querySelector('#progress-fill'),
  latestUpdate: document.querySelector('#latest-update'),
  moduleDialog: document.querySelector('#module-dialog'),
  moduleDialogMessage: document.querySelector('#module-dialog-message'),
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
  toast: document.querySelector('#toast')
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
let detailTab = 'info';
let editingID = null;
let previewText = '';
let previewSavedText = '';
let toastTimer = null;
let confirmResolver = null;
let nameLookupTimer = null;
let nameLookupSequence = 0;
let autoFilledName = '';
let manualNameEdited = false;
let listScrollY = 0;
const mobileLayout = window.matchMedia('(max-width: 700px)');

initializeHistoryState();

ui.advancedOptions.innerHTML = `<p class="advanced-intro">这些选项由 App 内置的 Script‑Hub 引擎执行，并随当前模块保存。留空即采用上游默认行为。</p>${advancedGroups.map(advancedGroupMarkup).join('')}`;

ui.search.addEventListener('input', renderSidebar);
ui.add.addEventListener('click', () => openEditor());
ui.refresh.addEventListener('click', updateAll);
ui.summaryRow.addEventListener('click', () => selectItem('combined'));
ui.back.addEventListener('click', navigateBackToList);
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
ui.moduleDialog.addEventListener('click', event => { if (event.target === ui.moduleDialog) closeDialog(ui.moduleDialog); });
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
ui.detailRoot.addEventListener('change', handleDetailChange);
window.addEventListener('popstate', handleHistoryNavigation);

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
  const response = await fetch(path, { method: options.method || 'GET', headers, body });
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
  } catch (error) { showToast(error.message, true); }
}

function applyState(next, initial = false, renderCurrentDetail = false) {
    const previous = state;
    state = next;
    if (initial) {
      const requested = new URL(location.href).searchParams.get('module');
      if (requested === 'combined' || (requested && next.modules.some(module => module.id === requested))) {
        selectedID = requested;
        ui.body.classList.add('has-selection');
      } else if (mobileLayout.matches) {
        selectedID = null;
        ui.body.classList.remove('has-selection');
      }
    }
    if (selectedID && selectedID !== 'combined' && !next.modules.some(module => module.id === selectedID)) selectedID = 'combined';
    if (initial || renderCurrentDetail) {
      renderSidebar();
      renderActivity();
      renderDetail(false);
      if (initial && mobileLayout.matches && selectedID) window.scrollTo(0, 0);
    } else {
      patchLiveState(previous, next);
      renderActivity();
    }
}

function startStateEvents() {
  if (!('EventSource' in window)) {
    setInterval(() => { if (!document.hidden) loadState(false, false); }, 5000);
    return;
  }
  const events = new EventSource('/api/events');
  events.addEventListener('state', event => {
    try { applyState(JSON.parse(event.data), false, false); }
    catch (_) { /* The next event contains a complete state snapshot. */ }
  });
  events.onerror = () => {
    if (!document.hidden) loadState(false, false);
  };
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
  if (selectedID === 'combined') {
    patchDetailValue('包含来源', `${next.combined.enabledCount} / ${next.combined.sourceCount}`);
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

function patchSidebarLive() {
  ui.summarySubtitle.textContent = `${state.combined.enabledCount} 个来源 · 总模块订阅`;
  state.modules.forEach(module => {
    const row = ui.list.querySelector(`.module-row[data-id="${module.id}"]`);
    if (!row) return;
    row.classList.toggle('disabled', !module.isEnabled);
    const toggle = row.querySelector('[data-module-toggle]');
    if (toggle && toggle.checked !== module.isEnabled) toggle.checked = module.isEnabled;
  });
}

function renderSidebar() {
  if (!state) return;
  const query = ui.search.value.trim().toLocaleLowerCase();
  const modules = state.modules.filter(module => [module.name, module.sourceURL, module.sourceFormatTitle, module.outputFileName].join('\n').toLocaleLowerCase().includes(query));
  ui.summarySubtitle.textContent = `${state.combined.enabledCount} 个来源 · 总模块订阅`;
  ui.summaryRow.classList.toggle('selected', selectedID === 'combined');
  ui.list.innerHTML = modules.length ? modules.map(moduleRow).join('') : `<div class="empty-state"><div><span class="symbol" data-symbol="magnifyingglass"></span><div>${query ? '没有搜索结果' : '还没有模块'}</div></div></div>`;
}

function moduleRow(module) {
  const icon = module.iconURL ? `<img src="${escapeAttribute(module.iconURL)}" alt="" loading="lazy">` : `<span class="symbol" data-symbol="shippingbox"></span>`;
  return `<div class="module-row ${selectedID === module.id ? 'selected' : ''} ${module.isEnabled ? '' : 'disabled'}" data-id="${module.id}" role="button" tabindex="0">
    <span class="module-icon ${module.iconURL ? '' : 'placeholder'}">${icon}</span>
    <span class="module-copy"><strong>${escapeHTML(module.name)}</strong><small>${escapeHTML(module.sourceFormatTitle)}</small></span>
    <label class="module-toggle" title="${module.isEnabled ? '从总模块中停用' : '包含在总模块中'}"><input type="checkbox" data-module-toggle="${module.id}" ${module.isEnabled ? 'checked' : ''} aria-label="包含 ${escapeAttribute(module.name)}"><span class="toggle-track" aria-hidden="true"></span></label>
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
  if (!state || !selectedID) {
    ui.desktopActions.innerHTML = '';
    setDetailHTML(`<div class="empty-state"><div><span class="symbol" data-symbol="sidebar.left"></span><div>选择一个模块</div></div></div>`, animate);
    return;
  }
  if (selectedID === 'combined') {
    ui.mobileTitle.textContent = state.combined.name;
    ui.desktopTitle.textContent = state.combined.name;
    renderCombinedDetail(animate);
  }
  else {
    const module = state.modules.find(item => item.id === selectedID);
    if (module) {
      ui.mobileTitle.textContent = module.name;
      ui.desktopTitle.textContent = module.name;
      renderModuleDetail(module, animate);
    }
  }
}

function setDetailHTML(content, animate = true) {
  ui.detail.innerHTML = `<div class="detail-stage ${animate ? 'page-enter' : ''}">${content}</div>`;
}

function detailToolbar(module = null) {
  const controls = `
    <div class="segmented-control" aria-label="显示方式">
      <button data-action="tab-info" class="${detailTab === 'info' ? 'selected' : ''}"><span class="symbol" data-symbol="info.circle"></span><span>详情</span></button>
      <button data-action="tab-preview" class="${detailTab === 'preview' ? 'selected' : ''}"><span class="symbol" data-symbol="curlybraces"></span><span>预览</span></button>
    </div>
    ${module ? `<button class="button" data-action="edit"><span class="symbol" data-symbol="pencil"></span>编辑</button><button class="button destructive" data-action="delete"><span class="symbol" data-symbol="trash"></span>删除</button>` : ''}`;
  ui.desktopActions.innerHTML = controls;
  return `<div class="detail-toolbar mobile-detail-toolbar">${controls}</div>`;
}

function renderCombinedDetail(animate = true) {
  const combined = state.combined;
  if (detailTab === 'preview') {
    setDetailHTML(detailToolbar() + previewShell(combined.fileName, false), animate);
    loadPreview('/api/combined/preview', false);
    return;
  }
  const subscription = combined.subscriptionURL ? `<div class="form-section-view"><h3 class="section-heading">总模块订阅地址</h3><div class="group-box"><div class="detail-row action-row"><div class="detail-value monospaced">${escapeHTML(combined.subscriptionURL)}</div><div><button class="button" data-action="copy" data-value="${escapeAttribute(combined.subscriptionURL)}"><span class="symbol" data-symbol="copy"></span>拷贝地址</button></div></div></div></div>` : '';
  setDetailHTML(`${detailToolbar()}
    <section class="form-section-view"><h3 class="section-heading">汇总模块</h3><div class="group-box">
      ${detailRow('square.stack.3d.up.fill', '名称', combined.name)}
      ${detailRow('shippingbox', '包含来源', `${combined.enabledCount} / ${combined.sourceCount}`)}
      ${detailRow('clock', '最新更新', formatDate(combined.lastUpdatedAt, '尚未更新'))}
    </div></section>${subscription}`, animate);
}

function renderModuleDetail(module, animate = true) {
  if (detailTab === 'preview') {
    setDetailHTML(detailToolbar(module) + previewShell(module.outputFileName, true), animate);
    loadPreview(`/api/modules/${module.id}/preview`, true);
    return;
  }
  const advanced = module.advancedSummary ? `<section class="form-section-view"><h3 class="section-heading">高级设置</h3><div class="group-box"><div class="detail-row"><div class="detail-label"><span class="symbol" data-symbol="slider.horizontal.3"></span><span>已应用</span></div><div class="detail-value advanced-summary">${escapeHTML(module.advancedSummary)}</div></div></div></section>` : '';
  const publishedTitle = module.publishedURL?.includes('workers.dev') ? 'Cloudflare' : 'GitHub';
  const published = module.publishedURL ? `<section class="form-section-view"><h3 class="section-heading">${publishedTitle}</h3><div class="group-box"><div class="detail-row action-row"><div class="detail-value monospaced">${escapeHTML(module.publishedURL)}</div><div><button class="button" data-action="copy" data-value="${escapeAttribute(module.publishedURL)}"><span class="symbol" data-symbol="copy"></span>拷贝地址</button></div></div></div></section>` : '';
  const error = module.lastError ? `<section class="form-section-view"><h3 class="section-heading">最近一次更新失败</h3><div class="group-box"><div class="detail-row action-row error-box"><strong>更新失败</strong><div>${escapeHTML(module.lastError)}</div><small>如果该来源有缓存，总模块会继续沿用它上一次成功版本。</small></div></div></section>` : '';
  const conflict = module.hasOverrideConflict ? `<section class="form-section-view"><h3 class="section-heading">本地编辑冲突</h3><div class="group-box"><div class="detail-row action-row error-box"><strong>上游内容已经变化</strong><div>当前仍在使用本地编辑。可在预览中比较内容后保留或恢复。</div><div><button class="button" data-action="accept-override">保留本地编辑</button><button class="button" data-action="tab-preview">前往预览</button></div></div></div></section>` : '';
  const individualOutput = state.storageMode === 'local' ? `<section class="form-section-view"><h3 class="section-heading">iCloud 云盘</h3><div class="group-box">
    <label class="detail-row switch-row"><div class="detail-label"><span class="symbol" data-symbol="externaldrive"></span><span>输出独立模块至 iCloud 云盘</span></div><input type="checkbox" data-individual-icloud-export ${module.exportsIndividualModuleToICloud ? 'checked' : ''}><span class="toggle-track" aria-hidden="true"></span></label>
    <div class="arguments-footer"><small>关闭后自动删除独立文件，汇总模块不受影响。</small></div>
  </div></section>` : '';
  setDetailHTML(`${detailToolbar(module)}
    <section class="form-section-view"><h3 class="section-heading">模块信息</h3><div class="group-box">
      ${detailRow('link', '原始地址', `<a href="${escapeAttribute(module.sourceURL)}" target="_blank" rel="noreferrer">${escapeHTML(module.sourceURL)}</a>`, true)}
      ${detailRow('doc.text', '来源格式', module.sourceFormatTitle)}
      ${detailRow('square.stack.3d.up.fill', '汇总订阅', state.combined.subscriptionURL || '等待发布配置')}
      ${detailRow('clock', '上次更新', formatDate(module.lastUpdatedAt, '从未更新'))}
    </div></section>
    ${individualOutput}${advanced}<div id="arguments-section"></div>${conflict}${published}${error}`, animate);
  loadArguments(module);
}

function detailRow(icon, label, value, raw = false) {
  return `<div class="detail-row"><div class="detail-label"><span class="symbol" data-symbol="${icon}"></span><span>${escapeHTML(label)}</span></div><div class="detail-value">${raw ? value : escapeHTML(String(value ?? '—'))}</div></div>`;
}

function previewShell(label, editable) {
  return `<section class="preview-shell"><div class="preview-toolbar"><span class="preview-label">${escapeHTML(label)}</span><button class="button" data-action="copy-preview"><span class="symbol" data-symbol="doc.on.doc"></span>拷贝全部</button>${editable ? `<button class="button" data-action="restore-preview"><span class="symbol" data-symbol="arrow.uturn.backward"></span>恢复</button><button class="button primary" data-action="save-preview" disabled>写入</button>` : ''}</div>${editable ? '<textarea class="code-editor" id="code-editor" spellcheck="false" aria-label="模块内容">正在载入…</textarea>' : '<pre class="code-view" id="code-view">正在载入…</pre>'}</section>`;
}

async function loadPreview(path, editable) {
  try {
    const text = await api(path);
    if (editable) {
      const editor = document.querySelector('#code-editor');
      if (!editor) return;
      previewText = text; previewSavedText = text; editor.value = text;
      editor.addEventListener('input', () => { previewText = editor.value; const save = document.querySelector('[data-action="save-preview"]'); if (save) save.disabled = previewText === previewSavedText; });
    } else {
      const view = document.querySelector('#code-view');
      if (view) view.innerHTML = highlightCode(text);
      previewText = text; previewSavedText = text;
    }
  } catch (error) { showToast(error.message, true); }
}

async function loadArguments(module) {
  try {
    const payload = await api(`/api/modules/${module.id}/arguments`);
    if (selectedID !== module.id || detailTab !== 'info') return;
    const target = document.querySelector('#arguments-section');
    if (!target || !payload.arguments.length) return;
    target.innerHTML = `<section class="form-section-view page-enter"><h3 class="section-heading">模块参数</h3><div class="group-box">
      ${payload.arguments.map(argumentMarkup).join('')}
      <div class="arguments-footer"><small>修改会立即应用</small><button class="button" data-action="reset-arguments" ${payload.arguments.every(item => item.value === item.defaultValue) ? 'disabled' : ''}>恢复默认值</button></div>
      ${payload.help ? `<details class="parameter-help"><summary><span class="symbol" data-symbol="chevron.right"></span>参数说明</summary><p>${escapeHTML(payload.help)}</p></details>` : ''}
    </div></section>`;
  } catch (_) {}
}

function argumentMarkup(argument) {
  const isBoolean = ['true', 'false'].includes(String(argument.defaultValue).toLowerCase());
  const control = isBoolean
    ? `<label class="module-toggle argument-toggle"><input type="checkbox" data-argument-key="${escapeAttribute(argument.key)}" data-default="${escapeAttribute(argument.defaultValue)}" ${String(argument.value).toLowerCase() === 'true' ? 'checked' : ''}><span class="toggle-track" aria-hidden="true"></span></label>`
    : `<input class="argument-input" type="text" data-argument-key="${escapeAttribute(argument.key)}" data-default="${escapeAttribute(argument.defaultValue)}" value="${escapeAttribute(argument.value)}" placeholder="${escapeAttribute(argument.defaultValue)}">`;
  return `<div class="detail-row argument-row"><div class="argument-name">${escapeHTML(argument.key)}</div><div class="argument-control">${control}</div></div>`;
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
  const source = event.target.closest('[data-action]');
  const action = source?.dataset.action;
  if (!action) return;
  const module = state.modules.find(item => item.id === selectedID);
  switch (action) {
  case 'tab-info': detailTab = 'info'; renderDetail(false); break;
  case 'tab-preview': detailTab = 'preview'; renderDetail(false); break;
  case 'edit': if (module) openEditor(module); break;
  case 'delete': if (module) await deleteModule(module); break;
  case 'copy': await copyText(source.dataset.value, source); break;
  case 'copy-preview': await copyText(previewText, source); break;
  case 'save-preview': if (module) await savePreview(module); break;
  case 'restore-preview': if (module) await restorePreview(module); break;
  case 'reset-arguments': if (module) await resetArguments(module); break;
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
  const value = input.type === 'checkbox' ? String(input.checked) : input.value;
  try { await api(`/api/modules/${selectedID}/arguments`, { method: 'PUT', json: { key: input.dataset.argumentKey, value } }); showToast('模块参数已更新'); }
  catch (error) { showToast(error.message, true); }
}

function selectItem(id, pushHistory = true) {
  if (!state) return;
  if (id !== 'combined' && !state.modules.some(module => module.id === id)) id = 'combined';
  const cameFromList = mobileLayout.matches && !ui.body.classList.contains('has-selection');
  if (cameFromList) listScrollY = window.scrollY;
  selectedID = id; detailTab = 'info'; ui.body.classList.add('has-selection');
  if (pushHistory) {
    const url = new URL(location.href);
    url.searchParams.set('module', id);
    history.pushState({ surgeRelay: true, view: 'detail', module: id, cameFromList }, '', url);
  }
  renderSidebar(); renderDetail(false);
  if (mobileLayout.matches) window.scrollTo(0, 0);
}

function initializeHistoryState() {
  const module = new URL(location.href).searchParams.get('module');
  if (history.state?.surgeRelay) return;
  if (module) {
    const detailURL = new URL(location.href);
    const listURL = new URL(location.href);
    listURL.searchParams.delete('module');
    history.replaceState({ surgeRelay: true, view: 'list', module: null }, '', listURL);
    history.pushState({ surgeRelay: true, view: 'detail', module, cameFromList: true }, '', detailURL);
  } else {
    history.replaceState({ surgeRelay: true, view: 'list', module: null }, '', location.href);
  }
}

function showModuleList(replaceHistory = false) {
  selectedID = null;
  detailTab = 'info';
  ui.body.classList.remove('has-selection');
  const url = new URL(location.href);
  url.searchParams.delete('module');
  if (replaceHistory) history.replaceState({ surgeRelay: true, view: 'list', module: null }, '', url);
  renderSidebar();
  if (mobileLayout.matches) window.scrollTo(0, listScrollY);
}

function navigateBackToList() {
  if (!mobileLayout.matches) return;
  if (history.state?.surgeRelay && history.state?.cameFromList) history.back();
  else showModuleList(true);
}

function handleHistoryNavigation(event) {
  const module = new URL(location.href).searchParams.get('module');
  if (mobileLayout.matches && (!module || event.state?.view === 'list')) {
    showModuleList(false);
    return;
  }
  selectItem(module || 'combined', false);
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
  try { const text = await api(`/api/modules/${module.id}/preview`, { method: 'DELETE' }); const editor = document.querySelector('#code-editor'); if (editor) editor.value = text; previewText = text; previewSavedText = text; document.querySelector('[data-action="save-preview"]').disabled = true; showToast('已恢复转换结果'); }
  catch (error) { showToast(error.message, true); }
}

async function resetArguments(module) {
  try { const result = await api(`/api/modules/${module.id}/arguments`, { method: 'DELETE' }); showToast(result.message); renderModuleDetail(module, true); }
  catch (error) { showToast(error.message, true); }
}

function openDialog(dialog) { dialog.classList.remove('is-closing'); dialog.showModal(); }
function closeDialog(dialog) { return new Promise(resolve => { if (!dialog.open) return resolve(); dialog.classList.add('is-closing'); setTimeout(() => { dialog.close(); dialog.classList.remove('is-closing'); resolve(); }, 165); }); }
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
  button.innerHTML = '<span class="symbol" data-symbol="checkmark"></span>拷贝成功';
  button.classList.add('copy-success');
  const timer = setTimeout(() => {
    if (!button.isConnected) return;
    button.innerHTML = button.dataset.copyLabel;
    button.classList.remove('copy-success');
    delete button.dataset.copyLabel;
    delete button.dataset.copyTimer;
  }, 1600);
  button.dataset.copyTimer = String(timer);
}

function highlightCode(text) {
  return text.split('\n').map(line => {
    const trimmed = line.trim(); let value = escapeHTML(line);
    if (/^\[[^\]]+\]$/.test(trimmed)) return `<span class="code-line code-section">${value}</span>`;
    if (/^(#|\/\/|;)/.test(trimmed)) return `<span class="code-line code-comment">${value}</span>`;
    value = value.replace(/(https?:\/\/[^\s,&lt;&gt;]+)/g, '<span class="code-url">$1</span>');
    value = value.replace(/^([A-Za-z][A-Za-z0-9_-]*)(\s*=)/, '<span class="code-key">$1</span>$2');
    value = value.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="code-number">$1</span>');
    return `<span class="code-line">${value || ' '}</span>`;
  }).join('');
}

function showToast(message, isError = false) { clearTimeout(toastTimer); ui.toast.textContent = message; ui.toast.classList.toggle('error', isError); ui.toast.classList.add('visible'); toastTimer = setTimeout(() => ui.toast.classList.remove('visible'), 2600); }
function formatDate(value, fallback = '—') { if (!value) return fallback; const date = new Date(value); if (Number.isNaN(date.valueOf())) return fallback; return new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeStyle: 'medium' }).format(date); }
function escapeHTML(value) { return String(value ?? '').replace(/[&<>'"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character]); }
function escapeAttribute(value) { return escapeHTML(value); }
