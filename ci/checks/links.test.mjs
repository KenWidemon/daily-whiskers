import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { check, inspect } from './links.mjs';

test('parses references, images, duplicate/formatted headings, and excludes code', () => {
  const result = inspect('# A *heading*\n# A heading\n[ref][r]\n![pic](pic.png)\n\n[r]: b.md#a\n\n```md\n[ignored](missing)\n```\n');
  assert.deepEqual([...result.anchors], ['a-heading', 'a-heading-1']);
  assert.deepEqual(result.links, ['b.md#a', 'pic.png']);
});

test('checks local targets and anchors without fetching remote or escaping root', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'dw-links-'));
  try {
    fs.writeFileSync(path.join(root, 'a.md'), '[ok](b%20space.md#heading) [bad](b%20space.md#absent) [missing](missing.md) [external](https://example.invalid) [outside](../private.md)');
    fs.writeFileSync(path.join(root, 'b space.md'), '# Heading\n');
    const errors = check(root, ['a.md', 'b space.md']);
    assert.equal(errors.length, 3);
    assert.ok(errors.some(e => e.includes('anchor does not exist')));
    assert.ok(errors.some(e => e.includes('target does not exist')));
    assert.ok(errors.some(e => e.includes('leaves repository')));
    fs.unlinkSync(path.join(root, 'b space.md'));
    assert.equal(check(root, ['a.md']).length, 4);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
