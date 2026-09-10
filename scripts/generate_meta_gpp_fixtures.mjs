// Run with a compiled official IAB encoder's GppModel.js path as argv[2].
// Reference: https://github.com/IABTechLab/iabgpp-es (Apache-2.0).
// This is an offline test-fixture generator, never an app dependency.
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
const { GppModel } = await import(pathToFileURL(process.argv[2]));
const names = ['usnat', 'usca', 'usva', 'usco', 'usut', 'usct', 'usfl',
  'usmt', 'usor', 'ustx', 'usde', 'usia', 'usne', 'usnh', 'usnj', 'ustn',
  'usmn', 'usmd', 'usin', 'usky', 'usri'];
const noGpc = new Set([9, 11, 13, 25, 26, 27]);
const fixtures = [];
function fixture(ids, change, label, allowed) {
  const model = new GppModel();
  for (const id of ids) {
    const name = names[id - 7];
    model.setFieldValue(name, 'SaleOptOut', 2);
    if (id === 7 || id === 8) model.setFieldValue(name, 'SharingOptOut', 2);
    if (id !== 8) model.setFieldValue(name, 'TargetedAdvertisingOptOut', 2);
  }
  change(model);
  fixtures.push({ label, sid: ids.join('_'), gpp: model.encode(), allowed });
}
for (let id = 7; id <= 27; id++) {
  const name = names[id - 7];
  fixture([id], () => {}, `${name}: allowed`, true);
  const fields = ['SaleOptOut'];
  if (id === 7 || id === 8) fields.push('SharingOptOut');
  if (id !== 8) fields.push('TargetedAdvertisingOptOut');
  for (const field of fields) {
    fixture([id], m => m.setFieldValue(name, field, 1), `${name}: ${field}`, false);
  }
  if (!noGpc.has(id)) {
    fixture([id], m => m.setFieldValue(name, 'Gpc', true), `${name}: GPC`, false);
    fixture([id], m => m.setFieldValue(name, 'GpcSegmentIncluded', false), `${name}: absent optional GPC`, true);
  }
}
fixture([7], m => m.setFieldValue('usnat', 'Version', 1), 'US national v1', true);
fixture([7], m => { m.setFieldValue('usnat', 'Version', 1); m.setFieldValue('usnat', 'SharingOptOut', 1); }, 'US national v1 opt-out', false);
fixture([7, 8, 9], () => {}, 'contiguous header range', true);
fixture([7, 8, 9], m => m.setFieldValue('usca', 'SharingOptOut', 1), 'one section denies', false);
fixture([7, 12, 24], () => {}, 'noncontiguous header offsets', true);
fs.writeFileSync(new URL('../scripts/fixtures/meta_gpp.json', import.meta.url), JSON.stringify(fixtures, null, 2) + '\n');
