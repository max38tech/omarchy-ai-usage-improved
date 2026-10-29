#!/usr/bin/python3
"""Antigravity tokens from SQLite protobufs and account quotas from Code Assist.

Field numbers are taken from the descriptors embedded in the installed agy:
CortexStepGeneratorMetadata.chat_model (1), ChatModelMetadata.usage (4),
ModelUsageStats.{input,output,cache_write,cache_read}_tokens (2,3,4,5).
No prompts, tool results, or credentials are included in the output/cache.
"""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HOME = Path.home()
ROOT = HOME / '.gemini/antigravity-cli'
STATE = Path(os.environ.get('XDG_STATE_HOME', str(HOME / '.local/state'))) / 'omarchy/agents'
USAGE = STATE / 'usage/antigravity.json'
CACHE = STATE / 'antigravity-stats.json'
TOKEN = ROOT / 'antigravity-oauth-token'
ENDPOINTS = {'daily-cloudcode-pa.googleapis.com', 'cloudcode-pa.googleapis.com',
             'autopush-cloudcode-pa.googleapis.com'}
TOKEN_KEYS = {2: 'inputTokens', 3: 'outputTokens', 4: 'cacheCreationInputTokens',
              5: 'cacheReadInputTokens'}


def varint(data, pos=0):
    value = shift = 0
    while pos < len(data) and shift < 70:
        byte = data[pos]
        pos += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, pos
        shift += 7
    raise ValueError('Invalid protobuf varint')


def fields(data):
    """Decode only wire values; length-delimited fields remain opaque bytes."""
    result = defaultdict(list)
    pos = 0
    while pos < len(data):
        tag, pos = varint(data, pos)
        number, wire = tag >> 3, tag & 7
        if not number:
            raise ValueError('Invalid protobuf field')
        if wire == 0:
            value, pos = varint(data, pos)
        elif wire == 2:
            size, pos = varint(data, pos)
            value = data[pos:pos + size]
            pos += size
            if len(value) != size:
                raise ValueError('Truncated protobuf field')
        elif wire in (1, 5):
            size = 8 if wire == 1 else 4
            value = data[pos:pos + size]
            pos += size
            if len(value) != size:
                raise ValueError('Truncated protobuf number')
        else:
            raise ValueError('Unsupported protobuf wire type')
        result[number].append(value)
    return result


def first(message, number, default=None):
    return message.get(number, [default])[0]


def nested(message, number):
    return fields(first(message, number, b''))


def text(message, number):
    value = first(message, number, b'')
    return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else ''


def indices(message):
    for buffer in message.get(2, []):
        if isinstance(buffer, int):
            yield buffer
        else:
            pos = 0
            while pos < len(buffer):
                value, pos = varint(buffer, pos)
                yield value


def day_from_metadata(metadata):
    seconds = first(nested(metadata, 1), 1)
    return datetime.fromtimestamp(seconds).strftime('%Y-%m-%d') if seconds else ''


def read_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.' + path.name,
                                         delete=False) as out:
            temporary = out.name
            json.dump(value, out)
            out.write('\n')
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def collect_local(force=False):
    now = datetime.now()
    today = now.strftime('%Y-%m-%d')
    day_tokens = Counter()
    day_sessions = defaultdict(set)
    model_usage = defaultdict(Counter)
    day_models = defaultdict(lambda: defaultdict(Counter))
    seen = set()
    warnings = []
    prompts = Counter()
    try:
        with (ROOT / 'history.jsonl').open() as history:
            for line in history:
                try:
                    row = json.loads(line)
                    prompts[datetime.fromtimestamp(float(row['timestamp']) / 1000).strftime('%Y-%m-%d')] += 1
                except (ValueError, KeyError, TypeError, OverflowError, OSError):
                    continue
    except FileNotFoundError:
        pass
    databases = sorted((ROOT / 'conversations').glob('*.db'))
    cached = read_json(CACHE, {}) if not force else {}
    new_cache = {}
    calls = 0
    for database in databases:
        # Include SQLite WAL changes: active conversations need no checkpoint.
        signature = []
        for file in (database, Path(str(database) + '-wal')):
            try:
                stat = file.stat()
                signature.append([stat.st_mtime_ns, stat.st_size])
            except FileNotFoundError:
                signature.append(None)
        previous = cached.get(database.name, {})
        records = previous.get('records') if previous.get('signature') == signature else None
        if records is None:
            records = []
            try:
                with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True, timeout=3) as connection:
                    connection.execute('PRAGMA query_only=ON')
                    metadata = {idx: fields(blob) for idx, blob in connection.execute(
                        'SELECT idx,metadata FROM steps WHERE metadata IS NOT NULL')}
                    executions = {}
                    for step in metadata.values():
                        date = day_from_metadata(step)
                        if date:
                            executions.setdefault(text(step, 12), date)
                    has_generations = connection.execute(
                        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='gen_metadata'").fetchone()
                    if has_generations:
                        for idx, blob in connection.execute('SELECT idx,data FROM gen_metadata ORDER BY idx'):
                            generation = fields(blob)
                            chat = nested(generation, 1)
                            usage = nested(chat, 4)
                            if not usage:
                                continue
                            date = next((day_from_metadata(metadata[i]) for i in indices(generation)
                                         if i in metadata and day_from_metadata(metadata[i])), '')
                            date = date or executions.get(text(generation, 4), '')
                            if not date:
                                warnings.append('A generation has no recorded date')
                                continue
                            model = text(chat, 21) or text(chat, 22) or text(chat, 19)
                            model = model or ('Model ' + str(first(usage, 1, first(chat, 3, 0))))
                            record = {'date': date, 'model': model,
                                      'request': text(usage, 7) or text(usage, 11) or f'{database.stem}:{idx}',
                                      'tokens': {key: int(first(usage, field, 0))
                                                 for field, key in TOKEN_KEYS.items()}}
                            records.append(record)
                    else:
                        # Older CLI databases can carry the usage directly on steps.
                        for idx, step in metadata.items():
                            usage = nested(step, 9)
                            if not usage:
                                continue
                            date = day_from_metadata(step)
                            info = nested(step, 24)
                            model = text(info, 20) or text(info, 8) or text(info, 12)
                            model = model or ('Model ' + str(first(usage, 1, 0)))
                            if date:
                                records.append({'date': date, 'model': model,
                                                'request': text(usage, 7) or text(usage, 11) or f'{database.stem}:{idx}',
                                                'tokens': {key: int(first(usage, field, 0))
                                                           for field, key in TOKEN_KEYS.items()}})
                new_cache[database.name] = {'signature': signature, 'records': records}
            except (sqlite3.Error, ValueError, TypeError, OverflowError, OSError):
                warnings.append('Could not read ' + database.name)
                records = previous.get('records', [])
        else:
            new_cache[database.name] = previous
        for record in records:
            request = record['request']
            if request in seen:
                continue
            seen.add(request)
            calls += 1
            date, model, tokens = record['date'], record['model'], record['tokens']
            day_tokens[date] += sum(tokens.values())
            day_sessions[date].add(database.stem)
            model_usage[model].update(tokens)
            day_models[date][model].update(tokens)
    atomic_json(CACHE, new_cache)
    recent = [(now - timedelta(days=n)).strftime('%Y-%m-%d') for n in range(6, -1, -1)]
    return {'id': 'antigravity', 'name': 'Antigravity CLI', 'ready': bool(calls),
            'activityOnly': False, 'hasLocalStats': bool(calls), 'hasPromptStats': True,
            'totalPrompts': sum(prompts.values()), 'totalSessions': len(databases),
            'activeDays': len(set(day_tokens) | set(prompts)), 'todayPrompts': prompts[today],
            'todaySessions': len(day_sessions[today]), 'todayTotalTokens': day_tokens[today],
            'todayTokensByModel': {model: sum(tokens.values()) for model, tokens in day_models[today].items()},
            'recentDays': [{'date': day, 'messageCount': day_tokens[day]} for day in recent],
            'modelUsage': {model: dict(tokens) for model, tokens in model_usage.items() if sum(tokens.values())},
            'localStatsWarning': '; '.join(sorted(set(warnings))), 'recordedModelCalls': calls}


class AccountError(Exception):
    pass


def account_request(host, method, token, body):
    request = urllib.request.Request('https://' + host + '/v1internal:' + method,
        data=json.dumps(body).encode(), headers={'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json', 'User-Agent': 'antigravity-cli/omarchy-usage'})
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Never echo request headers, tokens, or account response bodies.
        raise AccountError(f'{method}: HTTP {error.code}') from None
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        raise AccountError(f'{method}: connection failed') from None


def account_host():
    # Honor the actual CLI environment (daily/prod) instead of guessing a tier.
    logs = sorted((ROOT / 'log').glob('cli-*.log'), reverse=True)
    for log in logs[:3]:
        try:
            content = log.read_text(errors='replace')
            hosts = re.findall(r'https://([a-z-]+\.googleapis\.com)/v1internal:(?:loadCodeAssist|fetchAvailableModels)', content)
            for host in reversed(hosts):
                if host in ENDPOINTS:
                    return host
        except OSError:
            continue
    return 'cloudcode-pa.googleapis.com'


def token_valid(token):
    try:
        expiry = datetime.fromisoformat(token.get('expiry', '').replace('Z', '+00:00'))
        return expiry.timestamp() > time.time() + 30
    except (ValueError, TypeError, AttributeError):
        return False


def read_stored_token():
    candidates = []
    secret_tool = shutil.which('secret-tool') or '/usr/bin/secret-tool'
    try:
        proc = subprocess.run(
            [secret_tool, 'lookup', 'service', 'gemini', 'username', 'antigravity'],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5, check=False)
        if proc.returncode == 0 and proc.stdout.strip():
            keyring_data = json.loads(proc.stdout)
            if isinstance(keyring_data.get('token'), dict):
                candidates.append(keyring_data['token'])
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    stored = read_json(TOKEN, {})
    if isinstance(stored.get('token'), dict):
        candidates.append(stored['token'])
    for candidate in candidates:
        if token_valid(candidate) and candidate.get('access_token'):
            return candidate
    return candidates[0] if candidates else {}


def refresh_agy_token():
    # Let agy use its own OAuth client and keyring to refresh its credentials.
    # `models` is a read-only account command; it does not start an LLM turn.
    agy = shutil.which('agy') or str(HOME / '.local/bin/agy')
    try:
        subprocess.run([agy, 'models'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=25, check=False)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return read_stored_token()


def access_token(force_refresh=False):
    token = refresh_agy_token() if force_refresh else read_stored_token()
    if not force_refresh and not token_valid(token):
        token = refresh_agy_token()
    value = token.get('access_token', '')
    if not value:
        raise AccountError('Sign in to Antigravity CLI to load account limits.')
    if not token_valid(token):
        raise AccountError('Stored Antigravity token is expired and could not be refreshed. Run `agy` to sign in.')
    return value


def normalize_limits(summary, models):
    limits = []
    seen = set()
    groups = summary.get('groups') or []
    buckets = [(None, b) for b in summary.get('buckets', [])]
    for group in groups:
        buckets.extend((group.get('displayName'), bucket) for bucket in group.get('buckets', []))
    for group, bucket in buckets:
        if bucket.get('disabled') or 'remainingFraction' not in bucket:
            continue
        fraction = float(bucket['remainingFraction'])
        if not math.isfinite(fraction):
            continue
        window = str(bucket.get('window') or '')
        label = str(bucket.get('displayName') or window or bucket.get('bucketId') or 'Limit')
        # The panel meters show USED allowance; server labels say Remaining.
        title = re.sub(r'\s+(?:Limit\s+)?Remaining$', '', label, flags=re.I)
        title = re.sub(r'\s+Limit$', '', title, flags=re.I)
        if 'five hour' in title.lower() or window.lower() == '5h':
            title = 'Session (5-hour)'
        elif 'week' in title.lower() or 'week' in window.lower():
            title = 'Weekly'
        elif window and window.lower() not in title.lower():
            title += ' · ' + window
        if group and group.lower() not in title.lower():
            title = group + ' · ' + title
        key = (bucket.get('bucketId', title), window)
        if key in seen:
            continue
        seen.add(key)
        limits.append({'label': title, 'title': title, 'percent': max(0, min(1, 1 - fraction)),
                       'resetsAt': bucket.get('resetTime', '')})
    if not limits:
        # Older servers expose model-scoped quota meters rather than a summary.
        for model_id, model in (models.get('models') or {}).items():
            quota = model.get('quotaInfo') or {}
            if model.get('disabled') or 'remainingFraction' not in quota:
                continue
            fraction = float(quota['remainingFraction'])
            if math.isfinite(fraction):
                name = model.get('displayName') or model_id
                limits.append({'label': name, 'title': name,
                               'percent': max(0, min(1, 1 - fraction)),
                               'resetsAt': quota.get('resetTime', '')})
    limits.sort(key=lambda entry: ('weekly' in entry['title'].lower(), entry['title']))
    return limits


def collect_account():
    token = access_token()
    host = account_host()
    try:
        load = account_request(host, 'loadCodeAssist', token,
                               {'metadata': {'ideType': 'ANTIGRAVITY', 'platform': 'LINUX_AMD64'}})
    except AccountError as error:
        if 'HTTP 401' not in str(error):
            raise
        token = access_token(force_refresh=True)
        load = account_request(host, 'loadCodeAssist', token,
                               {'metadata': {'ideType': 'ANTIGRAVITY', 'platform': 'LINUX_AMD64'}})
    project = load.get('cloudaicompanionProject') or ''
    if isinstance(project, dict):
        project = project.get('id', '')
    if not project:
        try:
            project = (ROOT / 'cache/default_project_id.txt').read_text().strip()
        except OSError:
            pass
    body = {'project': project} if project else {}
    tier = load.get('paidTier') or load.get('currentTier') or {}
    model_body = dict(body)
    if tier.get('id'):
        model_body['entitlement'] = {'userTier': tier['id']}
    errors = []
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(account_request, host, 'retrieveUserQuotaSummary', token, body),
                   pool.submit(account_request, host, 'fetchAvailableModels', token, model_body)]
        responses = []
        for future in futures:
            try:
                responses.append(future.result())
            except AccountError as error:
                responses.append({})
                errors.append(str(error))
    summary, models = responses
    limits = normalize_limits(summary, models)
    if not limits:
        raise AccountError('; '.join(errors) or 'The account returned no quota meters.')
    return {'limits': limits, 'tierLabel': tier.get('name') or tier.get('id') or load.get('g1Tier', ''),
            'usageStatusText': '', 'authHelpText': '', 'retryAdvised': False,
            'limitsUpdatedAt': datetime.now(timezone.utc).isoformat()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--limits-only', action='store_true')
    parser.add_argument('--local-only', action='store_true', help='Rebuild token statistics without account requests')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'antigravity.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = read_json(USAGE, {})
        record = collect_local(force=args.force)
        # Carry the previous live limits through local-only updates and outages.
        for key in ('limits', 'tierLabel', 'limitsUpdatedAt'):
            record[key] = old.get(key, [] if key == 'limits' else '')
        if not args.local_only:
            try:
                record.update(collect_account())
            except (AccountError, ValueError, TypeError, KeyError) as error:
                record['usageStatusText'] = 'Account limits could not be refreshed'
                record['authHelpText'] = str(error) if isinstance(error, AccountError) else 'Unexpected account response format.'
                record['retryAdvised'] = 'connection failed' in record['authHelpText']
                if record.get('limitsUpdatedAt'):
                    record['authHelpText'] += ' Showing limits last fetched at ' + record['limitsUpdatedAt'] + '.'
        record['ready'] = bool(record['recordedModelCalls'] or record['limits'])
        atomic_json(USAGE, record)
        print(json.dumps(record))


if __name__ == '__main__':
    main()
