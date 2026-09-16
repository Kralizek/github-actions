const { execFileSync } = require('node:child_process');
const { appendFileSync } = require('node:fs');

function input(name, fallback = '') {
  const key = `INPUT_${name.replace(/-/g, '_').toUpperCase()}`;
  const value = process.env[key];
  return value == null || value === '' ? fallback : value;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function isoWeek(date) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const year = d.getUTCFullYear();
  const start = new Date(Date.UTC(year, 0, 1));
  const week = Math.ceil((((d - start) / 86400000) + 1) / 7);
  return { year, week };
}

function tokenValues(date) {
  const iso = isoWeek(date);
  return {
    '%Y': String(date.getUTCFullYear()).padStart(4, '0'),
    '%m': String(date.getUTCMonth() + 1).padStart(2, '0'),
    '%d': String(date.getUTCDate()).padStart(2, '0'),
    '%G': String(iso.year).padStart(4, '0'),
    '%V': String(iso.week).padStart(2, '0'),
  };
}

const tokenPatterns = {
  '%Y': '(?<year>[0-9]{4})',
  '%m': '(?<month>0[1-9]|1[0-2])',
  '%d': '(?<day>0[1-9]|[12][0-9]|3[01])',
  '%G': '(?<isoYear>[0-9]{4})',
  '%V': '(?<isoWeek>0[1-9]|[1-4][0-9]|5[0-3])',
};

const requiredTokens = {
  year: ['%Y'],
  month: ['%Y', '%m'],
  week: ['%G', '%V'],
  day: ['%Y', '%m', '%d'],
};

const defaultFormats = {
  year: 'r{date:%Y}-{sequence:4}',
  month: 'r{date:%Y%m}-{sequence:4}',
  week: 'r{date:%G%V}-{sequence:4}',
  day: 'r{date:%Y%m%d}-{sequence:4}',
};

function compileDateFormat(format, period) {
  const allowed = new Set(requiredTokens[period]);
  const seen = new Set();
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

function renderDateFormat(format, date) {
  const values = tokenValues(date);
  return format.replace(/%[YmdGV]/g, token => values[token]);
}

function parseFormat(format, period) {
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

function periodKey(groups, period) {
  switch (period) {
    case 'year': return [Number(groups.year)];
    case 'month': return [Number(groups.year), Number(groups.month)];
    case 'week': return [Number(groups.isoYear), Number(groups.isoWeek)];
    case 'day': return [Number(groups.year), Number(groups.month), Number(groups.day)];
  }
}

function compareKeys(a, b) {
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
    const diff = (a[i] ?? 0) - (b[i] ?? 0);
    if (diff !== 0) return Math.sign(diff);
  }
  return 0;
}

function parseTag(tag, compiled, period) {
  const match = compiled.regex.exec(tag);
  if (!match?.groups) return null;
  const sequence = Number(match.groups.sequence);
  if (sequence <= 0) return null;
  return { tag, key: periodKey(match.groups, period), sequence };
}

function render(compiled, date, sequence) {
  const dateText = renderDateFormat(compiled.dateFormat, date);
  const sequenceText = String(sequence).padStart(compiled.digits, '0');
  return compiled.format
    .replace(`{date:${compiled.dateFormat}}`, dateText)
    .replace(`{sequence:${compiled.digits}}`, sequenceText);
}

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

function main() {
  const scheme = input('scheme', 'periodic');
  if (scheme !== 'periodic') fail(`Unsupported release scheme: ${scheme}`);
  const period = input('period', 'month');
  if (!requiredTokens[period]) fail(`Unsupported period: ${period}`);
  const format = input('format', defaultFormats[period]);
  const compiled = parseFormat(format, period);
  const now = process.env.RELEASE_DATE ? new Date(`${process.env.RELEASE_DATE}T00:00:00Z`) : new Date();
  if (Number.isNaN(now.getTime())) fail(`Invalid RELEASE_DATE: ${process.env.RELEASE_DATE}`);
  const renderedPeriod = renderDateFormat(compiled.dateFormat, now);
  const currentProbe = compiled.regex.exec(render(compiled, now, 1));
  if (!currentProbe?.groups) fail('Internal error while evaluating release format.');
  const currentKey = periodKey(currentProbe.groups, period);
  const tagList = git('tag', '-l').split('\n').filter(Boolean);
  const parsed = tagList.map(tag => parseTag(tag, compiled, period)).filter(Boolean);
  parsed.sort((a, b) => compareKeys(a.key, b.key) || a.sequence - b.sequence);
  const latest = parsed.at(-1) ?? null;
  const head = git('rev-parse', 'HEAD');
  const tagsOnHead = new Set(git('tag', '--points-at', 'HEAD').split('\n').filter(Boolean));
  const currentOnHead = parsed.filter(item => tagsOnHead.has(item.tag) && compareKeys(item.key, currentKey) === 0);
  if (currentOnHead.length > 1) fail(`Multiple periodic release tags for current period point to HEAD: ${currentOnHead.map(x => x.tag).join(' ')}`);
  let tag;
  let sequence;
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
  })) appendFileSync(output, `${key}=${value}\n`);
}

main();
