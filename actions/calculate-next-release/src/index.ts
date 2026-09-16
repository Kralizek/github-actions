import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';

type Period = 'year' | 'month' | 'week' | 'day';

type CompiledFormat = {
  format: string;
  dateFormat: string;
  digits: number;
  regex: RegExp;
};

type ParsedRelease = {
  tag: string;
  key: number[];
  sequence: number;
};

function input(name: string, fallback = ''): string {
  const key = `INPUT_${name.replace(/-/g, '_').toUpperCase()}`;
  const value = process.env[key];
  return value == null || value === '' ? fallback : value;
}

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function isoWeek(date: Date): { year: number; week: number } {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const year = d.getUTCFullYear();
  const start = new Date(Date.UTC(year, 0, 1));
  const week = Math.ceil((((d.getTime() - start.getTime()) / 86400000) + 1) / 7);
  return { year, week };
}

function tokenValues(date: Date): Record<string, string> {
  const iso = isoWeek(date);
  return {
    '%Y': String(date.getUTCFullYear()).padStart(4, '0'),
    '%m': String(date.getUTCMonth() + 1).padStart(2, '0'),
    '%d': String(date.getUTCDate()).padStart(2, '0'),
    '%G': String(iso.year).padStart(4, '0'),
    '%V': String(iso.week).padStart(2, '0'),
  };
}

const tokenPatterns: Record<string, string> = {
  '%Y': '(?<year>[0-9]{4})',
  '%m': '(?<month>0[1-9]|1[0-2])',
  '%d': '(?<day>0[1-9]|[12][0-9]|3[01])',
  '%G': '(?<isoYear>[0-9]{4})',
  '%V': '(?<isoWeek>0[1-9]|[1-4][0-9]|5[0-3])',
};

const requiredTokens: Record<Period, string[]> = {
  year: ['%Y'],
  month: ['%Y', '%m'],
  week: ['%G', '%V'],
  day: ['%Y', '%m', '%d'],
};

const defaultFormats: Record<Period, string> = {
  year: 'r{date:%Y}-{sequence:4}',
  month: 'r{date:%Y%m}-{sequence:4}',
  week: 'r{date:%G%V}-{sequence:4}',
  day: 'r{date:%Y%m%d}-{sequence:4}',
};

function compileDateFormat(format: string, period: Period): string {
  const allowed = new Set(requiredTokens[period]);
  const seen = new Set<string>();
  let regex = '';

  for (let i = 0; i < format.length;) {
    if (format[i] === '%') {
      const token = format.slice(i, i + 2);
      if (!tokenPatterns[token]) fail(`Unsupported date token in format: ${token}`);
      if (!allowed.has(token)) fail(`Date token ${token} is not valid for period ${period}.`);
      if (seen.has(token)) fail(`Date token ${token} may appear only once.`);
      seen.add(token);
      regex += tokenPatterns[token];
      i += 2;
    } else {
      regex += escapeRegex(format[i]);
      i += 1;
    }
  }

  for (const token of allowed) {
    if (!seen.has(token)) fail(`Format for period ${period} must contain ${token}.`);
  }

  return regex;
}

function renderDateFormat(format: string, date: Date): string {
  const values = tokenValues(date);
  return format.replace(/%[YmdGV]/g, token => values[token]);
}

function parseFormat(format: string, period: Period): CompiledFormat {
  const residual = format.replace(/\{date:[^{}]+\}/g, '').replace(/\{sequence:[1-9]\}/g, '');
  if (/[{}]/.test(residual)) fail(`Malformed release format: ${format}`);

  const dateMatches = [...format.matchAll(/\{date:([^{}]+)\}/g)];
  const sequenceMatches = [...format.matchAll(/\{sequence:([1-9])\}/g)];
  if (dateMatches.length !== 1) fail('Release format must contain exactly one {date:...} token.');
  if (sequenceMatches.length !== 1) fail('Release format must contain exactly one {sequence:N} token with N from 1 to 9.');

  const dateFormat = dateMatches[0][1];
  const digits = Number(sequenceMatches[0][1]);
  const dateRegex = compileDateFormat(dateFormat, period);
  const datePlaceholder = '__DATE_TOKEN__';
  const sequencePlaceholder = '__SEQUENCE_TOKEN__';
  const skeleton = format
    .replace(dateMatches[0][0], datePlaceholder)
    .replace(sequenceMatches[0][0], sequencePlaceholder);
  const regex = escapeRegex(skeleton)
    .replace(escapeRegex(datePlaceholder), dateRegex)
    .replace(escapeRegex(sequencePlaceholder), `(?<sequence>[0-9]{${digits}})`);

  return { format, dateFormat, digits, regex: new RegExp(`^${regex}$`) };
}

function periodKey(groups: Record<string, string>, period: Period): number[] {
  switch (period) {
    case 'year': return [Number(groups.year)];
    case 'month': return [Number(groups.year), Number(groups.month)];
    case 'week': return [Number(groups.isoYear), Number(groups.isoWeek)];
    case 'day': return [Number(groups.year), Number(groups.month), Number(groups.day)];
  }
}

function compareKeys(a: number[], b: number[]): number {
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
    const diff = (a[i] ?? 0) - (b[i] ?? 0);
    if (diff !== 0) return Math.sign(diff);
  }
  return 0;
}

function parseTag(tag: string, compiled: CompiledFormat, period: Period): ParsedRelease | null {
  const match = compiled.regex.exec(tag);
  if (!match?.groups) return null;
  const sequence = Number(match.groups.sequence);
  if (sequence <= 0) return null;
  return { tag, key: periodKey(match.groups, period), sequence };
}

function render(compiled: CompiledFormat, date: Date, sequence: number): string {
  const dateText = renderDateFormat(compiled.dateFormat, date);
  const sequenceText = String(sequence).padStart(compiled.digits, '0');
  return compiled.format
    .replace(`{date:${compiled.dateFormat}}`, dateText)
    .replace(`{sequence:${compiled.digits}}`, sequenceText);
}

function git(...args: string[]): string {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

function main(): void {
  const scheme = input('scheme', 'periodic');
  if (scheme !== 'periodic') fail(`Unsupported release scheme: ${scheme}`);

  const periodInput = input('period', 'month');
  if (!(periodInput in requiredTokens)) fail(`Unsupported period: ${periodInput}`);
  const period = periodInput as Period;
  const format = input('format', defaultFormats[period]);
  const compiled = parseFormat(format, period);

  const now = process.env.RELEASE_DATE ? new Date(`${process.env.RELEASE_DATE}T00:00:00Z`) : new Date();
  if (Number.isNaN(now.getTime())) fail(`Invalid RELEASE_DATE: ${process.env.RELEASE_DATE}`);

  const renderedPeriod = renderDateFormat(compiled.dateFormat, now);
  const currentProbe = compiled.regex.exec(render(compiled, now, 1));
  if (!currentProbe?.groups) fail('Internal error while evaluating release format.');
  const currentKey = periodKey(currentProbe.groups, period);

  const tagList = git('tag', '-l').split('\n').filter(Boolean);
  const parsed = tagList.map(tag => parseTag(tag, compiled, period)).filter((x): x is ParsedRelease => x !== null);
  parsed.sort((a, b) => compareKeys(a.key, b.key) || a.sequence - b.sequence);
  const latest = parsed.at(-1) ?? null;

  const head = git('rev-parse', 'HEAD');
  const tagsOnHead = new Set(git('tag', '--points-at', 'HEAD').split('\n').filter(Boolean));
  const currentOnHead = parsed.filter(item => tagsOnHead.has(item.tag) && compareKeys(item.key, currentKey) === 0);
  if (currentOnHead.length > 1) fail(`Multiple periodic release tags for current period point to HEAD: ${currentOnHead.map(x => x.tag).join(' ')}`);

  let tag: string;
  let sequence: number;
  let previousTag = latest?.tag ?? '';
  let reused = false;

  if (currentOnHead.length === 1) {
    const candidate = currentOnHead[0];
    if (!latest || candidate.tag !== latest.tag) fail(`Cannot reuse ${candidate.tag} because latest periodic release is ${latest?.tag ?? 'none'}.`);
    tag = candidate.tag;
    sequence = candidate.sequence;
    reused = true;
    previousTag = parsed.filter(item => item.tag !== candidate.tag && git('rev-list', '-n', '1', item.tag) !== head).at(-1)?.tag ?? '';
  } else {
    if (latest && compareKeys(latest.key, currentKey) > 0) fail(`Cannot move periodic release period backwards from ${latest.tag} to ${renderedPeriod}.`);
    sequence = latest && compareKeys(latest.key, currentKey) === 0 ? latest.sequence + 1 : 1;
    const max = 10 ** compiled.digits - 1;
    if (sequence > max) fail(`Periodic release sequence exhausted for ${renderedPeriod} with ${compiled.digits} digits.`);
    tag = render(compiled, now, sequence);
    if (tagList.includes(tag)) fail(`Tag ${tag} already exists unexpectedly.`);
  }

  const sequenceText = String(sequence).padStart(compiled.digits, '0');
  console.log(reused ? `Reusing release tag on HEAD: ${tag}` : `Next release: ${tag}`);

  const output = process.env.GITHUB_OUTPUT;
  if (!output) fail('GITHUB_OUTPUT must be set.');
  for (const [key, value] of Object.entries({
    release: tag,
    tag,
    'previous-tag': previousTag,
    scheme,
    period: renderedPeriod,
    sequence: sequenceText,
  })) {
    appendFileSync(output, `${key}=${value}\n`);
  }
}

main();
