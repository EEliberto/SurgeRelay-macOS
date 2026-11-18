// Run with: node --test tools/test_airport_name_cleanup.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'SurgeRelay/WebResources/app.js'), 'utf8');
const context = vm.createContext({});
vm.runInContext(source.slice(source.indexOf('const nodeRegionAliases ='), source.indexOf('function updateAirportNameExample()')), context);
const clean = context.intelligentlyCleanedNodeName;

test('removes repeated regions while preserving rates and node numbers', () => {
  const examples = [
    ['香港 01 | 1x HK', '香港 01 | 1x'],
    ['香港家宽 02｜2x HK', '香港家宽 02｜2x'],
    ['台湾 03 | 3x TW', '台湾 03 | 3x'],
    ['美国-纽约 01 ｜ 5x US', '美国-纽约 01 ｜ 5x'],
    ['日本 01 | 0.5x JP', '日本 01 | 0.5x'],
    ['新加坡 02 | 2× SG', '新加坡 02 | 2×'],
    ['香港 01｜1x/2x/3x/5x', '香港 01｜1x/2x/3x/5x'],
    ['香港 01 | HK | 2x', '香港 01 | HK | 2x'],
    ['Hong Kong 01 | 1X hk', 'Hong Kong 01 | 1X'],
    ['HK 01 | 1x HK', 'HK 01 | 1x'],
    ['印度尼西亚 01 | 2倍 ID', '印度尼西亚 01 | 2倍'],
    ['日本 01 | JP', '日本 01']
  ];
  for (const [input, expected] of examples) assert.equal(clean(input), expected, input);
});

test('preserves useful details, unknown regions, and conflicting regions', () => {
  for (const input of [
    '香港家宽 01 IPLC 10Gbps', '香港 1x 专线 01', '香港 01 | US',
    '印度尼西亚 01 | IN', '香港日本 01 | JP', '节点 01 | HK',
    '1x', 'HK', 'LINK 01 | IN', '香港 X1 Pro 01'
  ]) assert.equal(clean(input), input);
});

test('native and Web region aliases stay aligned and cover each supported region', () => {
  const swift = fs.readFileSync(path.join(root, 'SurgeRelay/Services/AirportSubscriptionParser.swift'), 'utf8');
  const literal = swift.match(/private static let nodeRegionAliases: \[String: \[String\]\] = \[([\s\S]*?)\n    \]/)[1];
  const nativeAliases = JSON.parse(`{${literal}}`);
  const webAliases = JSON.parse(vm.runInContext('JSON.stringify(nodeRegionAliases)', context));
  assert.deepEqual(webAliases, nativeAliases);
  for (const [code, aliases] of Object.entries(webAliases)) {
    assert.equal(clean(`${aliases[0]} 01 | 1x ${code}`), `${aliases[0]} 01 | 1x`);
  }
});

test('Web preview follows both toggles and save payload persists the smart switch', async () => {
  const output = {};
  const form = Object.fromEntries([
    'name', 'sourceURL', 'policyRegexFilter', 'nodeNameTemplate', 'nodeNameRemovalTerms',
    'includeKeywords', 'excludeKeywords', 'sortPriorityKeywords', 'nodeSortOrder',
    'udpRelay', 'tcpFastOpen', 'skipCertificateVerification', 'iconURL'
  ].map(name => [name, { value: '' }]));
  Object.assign(form, {
    optimizeNodeNames: { checked: true }, smartNodeNameCleanup: { checked: true },
    removeNodeNameEmoji: { checked: true }, filtersMetadataNodes: { checked: true },
    isEnabled: { checked: true }
  });
  form.nodeNameRemovalTerms.value = 'IEPL, IPEL, 专线';
  let payload;
  Object.assign(context, {
    ui: { airportForm: { elements: form, querySelector: () => output }, saveAirport: {}, airportDialogMessage: {} },
    splitAirportKeywords: value => value.split(/[,，\n]/).map(s => s.trim()).filter(Boolean),
    editingAirportID: 'example',
    api: async (url, options) => { payload = options.json; return {}; },
    closeDialog: async () => {}, showToast: () => {}, loadState: async () => {}
  });
  vm.runInContext(source.slice(source.indexOf('function updateAirportNameExample()'), source.indexOf('function openConfigurationEditor(')), context);
  context.updateAirportNameExample();
  assert.equal(output.textContent, '香港 01 | 2x');
  await context.saveAirport({ preventDefault() {} });
  assert.equal(payload.nodeNameOptimization.smartCleanup, true);
  form.smartNodeNameCleanup.checked = false;
  context.updateAirportNameExample();
  assert.equal(output.textContent, '香港 01 | 2x HK');
  await context.saveAirport({ preventDefault() {} });
  assert.equal(payload.nodeNameOptimization.smartCleanup, false);
  form.optimizeNodeNames.checked = false;
  context.updateAirportNameExample();
  assert.equal(output.textContent, '🇭🇰 香港 IEPL 01 | 2x HK');
});
