const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { run, deleteWithLease } = require('../.github/scripts/cleanup-branches.cjs');

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'branch-cleanup-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const remote = path.join(root, 'remote.git');
  const work = path.join(root, 'work');
  const env = { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' };
  const git = (args, cwd = root) => execFileSync('git', args, { cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git(['init', '--bare', remote]);
  git(['init', '-b', 'main', work]);
  git(['config', 'user.name', 'Cleanup Test'], work);
  git(['config', 'user.email', 'cleanup@example.invalid'], work);
  git(['commit', '--allow-empty', '-m', 'base'], work);
  git(['push', remote, 'main'], work);
  git(['checkout', '-b', 'feature/example'], work);
  git(['commit', '--allow-empty', '-m', 'merged work'], work);
  const sha = git(['rev-parse', 'HEAD'], work);
  git(['push', remote, 'feature/example'], work);
  const ref = () => {
    try { return git(['--git-dir', remote, 'rev-parse', '--verify', 'refs/heads/feature/example']); }
    catch { return null; }
  };
  const advance = () => {
    git(['commit', '--allow-empty', '-m', 'new work after merge'], work);
    git(['push', remote, 'feature/example'], work);
    return ref();
  };
  const pr = { number: 6, merged_at: '2026-10-27T21:14:15Z', closed_at: '2026-10-27T21:14:15Z', state: 'closed',
    head: { ref: 'feature/example', sha, repo: { id: 42 } }, base: { ref: 'main', repo: { id: 42 } } };
  const closed = [pr], open = [];
  const github = {
    rest: {
      repos: {
        get: async () => ({ data: { id: 42, default_branch: 'main', clone_url: remote } }),
        getBranch: async ({ branch }) => {
          if (branch === 'feature/example' && ref()) return { data: { name: branch, protected: false, commit: { sha: ref() } } };
          throw Object.assign(new Error('Missing branch'), { status: 404 });
        }
      },
      pulls: { list: async ({ head }) => ({ data: head
        ? [...closed].sort((a, b) => b.number - a.number).slice(0, 1)
        : closed }) }
    },
    paginate: async () => open
  };
  const context = { eventName: 'push', ref: 'refs/heads/main', repo: { owner: 'DerFlash', repo: 'epson-directscan' }, payload: {}, serverUrl: 'https://github.com' };
  const core = { info() {}, warning() {}, setSecret() {} };
  const invoke = extra => run({ github, context, core, token: '', ...extra });
  return { remote, work, git, sha, ref, advance, pr, closed, open, github, context, invoke };
}

test('a merged unchanged own branch is deleted from the real remote', async t => {
  const f = fixture(t);
  await f.invoke();
  assert.equal(f.ref(), null);
  assert.ok(f.git(['--git-dir', f.remote, 'rev-parse', '--verify', 'refs/heads/main']));
});

for (const reason of ['unmerged', 'fork', 'default', 'protected', 'advanced', 'open head', 'open base']) {
  test(`cleanup preserves a ${reason} branch`, async t => {
    const f = fixture(t);
    if (reason === 'unmerged') f.pr.merged_at = null;
    if (reason === 'fork') f.pr.head.repo.id = 999;
    if (reason === 'default') f.github.rest.repos.get = async () => ({ data: { id: 42, default_branch: 'feature/example', clone_url: f.remote } });
    if (reason === 'protected') f.github.rest.repos.getBranch = async () => ({ data: { protected: true, commit: { sha: f.sha } } });
    if (reason === 'advanced') f.advance();
    if (reason === 'open head') f.open.push({ head: { ref: 'feature/example', repo: { id: 42 } }, base: { ref: 'main', repo: { id: 42 } } });
    if (reason === 'open base') f.open.push({ head: { ref: 'other', repo: { id: 42 } }, base: { ref: 'feature/example', repo: { id: 42 } } });
    const before = f.ref();
    await f.invoke();
    assert.equal(f.ref(), before);
  });
}

test('a branch reused by a newer unmerged closed PR is preserved', async t => {
  const f = fixture(t);
  f.closed.unshift({ ...f.pr, number: 7, merged_at: null });
  await f.invoke();
  assert.equal(f.ref(), f.sha);
});

test('dry run keeps the remote branch intact', async t => {
  const f = fixture(t);
  await f.invoke({ dryRun: true });
  assert.equal(f.ref(), f.sha);
});

test('a later comment on an old merged PR cannot override a newer unmerged closure', async t => {
  const f = fixture(t);
  f.closed.push({ ...f.pr, number: 7, merged_at: null, closed_at: '2026-10-27T22:00:00Z' });
  await f.invoke();
  assert.equal(f.ref(), f.sha);
});

test('a non-default-branch push cannot trigger deletions', async t => {
  const f = fixture(t);
  f.context.ref = 'refs/heads/feature/example';
  await f.invoke();
  assert.equal(f.ref(), f.sha);
});

test('the closed merged PR event deletes only its own branch', async t => {
  const f = fixture(t);
  f.context.eventName = 'pull_request';
  f.context.payload = { action: 'closed', pull_request: { ...f.pr, merged: true } };
  const list = f.github.rest.pulls.list;
  f.github.rest.pulls.list = async options => {
    assert.ok(options.head, 'Event must not scan unrelated PRs');
    return list(options);
  };
  await f.invoke();
  assert.equal(f.ref(), null);
});

test('a closed unmerged PR event never deletes its head', async t => {
  const f = fixture(t);
  f.context.eventName = 'pull_request';
  f.context.payload = { action: 'closed', pull_request: { ...f.pr, merged: false, merged_at: null } };
  await f.invoke();
  assert.equal(f.ref(), f.sha);
});

test('atomic lease refuses deletion if the remote advances after inspection', async t => {
  const f = fixture(t);
  await f.invoke({ deleteBranch: options => { f.advance(); return deleteWithLease(options); } });
  assert.notEqual(f.ref(), null);
  assert.notEqual(f.ref(), f.sha);
});

test('permission errors are reported instead of treated as missing branches', async t => {
  const f = fixture(t);
  f.github.rest.repos.getBranch = async () => { throw Object.assign(new Error('Forbidden'), { status: 403 }); };
  await assert.rejects(f.invoke(), /Forbidden/);
  assert.equal(f.ref(), f.sha);
});

test('a delayed merge event preserves a branch reused by a later closed PR', async t => {
  const f = fixture(t);
  f.context.eventName = 'pull_request';
  f.context.payload = { action: 'closed', pull_request: { ...f.pr, merged: true } };
  f.closed.unshift({ ...f.pr, number: 7, merged_at: null, closed_at: '2026-10-27T22:00:00Z' });
  await f.invoke();
  assert.equal(f.ref(), f.sha);
});

test('a reuse PR outside the recovery page still prevents deletion', async t => {
  const f = fixture(t);
  f.github.rest.pulls.list = async ({ head }) => ({ data: head
    ? [{ ...f.pr, number: 7, merged_at: null }]
    : [f.pr] });
  await f.invoke();
  assert.equal(f.ref(), f.sha);
});
