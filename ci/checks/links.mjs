import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import MarkdownIt from 'markdown-it';
import GithubSlugger from 'github-slugger';

const markdown = new MarkdownIt({ html: true });

export function inspect(text) {
  const tokens = markdown.parse(text, {});
  const slugger = new GithubSlugger();
  const anchors = new Set();
  const links = [];
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.type === 'heading_open') {
      const content = tokens[i + 1].children ?? [];
      const label = content.filter(t => ['text', 'code_inline', 'emoji', 'image'].includes(t.type)).map(t => t.content).join('');
      anchors.add(slugger.slug(label));
    }
    for (const child of token.children ?? []) {
      if (child.type === 'link_open') links.push(child.attrGet('href'));
      if (child.type === 'image') links.push(child.attrGet('src'));
    }
  }
  // Explicit HTML anchors are supported; HTML is never executed.
  for (const token of tokens.flatMap(t => [t, ...(t.children ?? [])])) {
    if (['html_block', 'html_inline'].includes(token.type)) {
      for (const match of token.content.matchAll(/\b(?:id|name)=["']([^"']+)["']/g)) anchors.add(match[1]);
    }
  }
  return { anchors, links };
}

export function check(root, files) {
  root = fs.realpathSync(root);
  const errors = [];
  const parsed = new Map();
  const read = file => {
    if (!parsed.has(file)) parsed.set(file, inspect(fs.readFileSync(file, 'utf8')));
    return parsed.get(file);
  };
  const inside = file => file === root || file.startsWith(root + path.sep);
  for (const file of files) {
    const absolute = path.resolve(root, file);
    if (!inside(fs.realpathSync(absolute))) { errors.push(`${file}: symlink leaves repository`); continue; }
    for (const href of read(absolute).links) {
      if (/^[a-z][a-z\d+.-]*:/i.test(href) || href.startsWith('//')) continue;
      try {
        const [location, fragment] = href.split('#', 2);
        const pathname = decodeURIComponent(location.split('?', 1)[0]);
        const target = pathname ? path.resolve(path.dirname(absolute), pathname) : absolute;
        if (!inside(target)) throw new Error('link leaves repository');
        if (!fs.existsSync(target)) throw new Error('target does not exist');
        if (!inside(fs.realpathSync(target))) throw new Error('symlink leaves repository');
        if (fragment && target.endsWith('.md') && !read(target).anchors.has(decodeURIComponent(fragment))) {
          throw new Error('heading/anchor does not exist');
        }
      } catch (error) { errors.push(`${file}: ${href}: ${error.message}`); }
    }
  }
  return errors;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  const files = execFileSync('git', ['ls-files', '-z', '--', '*.md'], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean);
  const errors = check(root, files);
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log(`Checked local links and anchors in ${files.length} Markdown files (offline).`);
}
