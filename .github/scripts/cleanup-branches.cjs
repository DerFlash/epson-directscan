const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');

// Delete only the exact commit accepted by the merged PR, even if the ref moves
// between the API inspection and the push. No checkout or stored credentials.
function deleteWithLease({ remote, branch, expectedSha, token = '', serverUrl = 'https://github.com' }) {
  if (!/^[0-9a-f]{40}$/.test(expectedSha)) throw new Error('Invalid expected branch commit');
  const temporary = mkdtempSync(path.join(tmpdir(), 'merged-branch-cleanup-'));
  const env = { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' };
  if (token) {
    env.GIT_CONFIG_COUNT = '1';
    env.GIT_CONFIG_KEY_0 = `http.${serverUrl}/.extraheader`;
    env.GIT_CONFIG_VALUE_0 = `AUTHORIZATION: basic ${Buffer.from(`x-access-token:${token}`).toString('base64')}`;
  }
  const options = { cwd: temporary, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 };
  try {
    execFileSync('git', ['init', '--bare', '.'], options);
    execFileSync('git', ['check-ref-format', `refs/heads/${branch}`], options);
    execFileSync('git', ['push', '--porcelain', `--force-with-lease=refs/heads/${branch}:${expectedSha}`, remote, `:refs/heads/${branch}`], options);
  } catch {
    throw new Error(`Deletion refused for ${branch}: the branch changed, is protected, or access failed.`);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

async function run({ github, context, core, token, dryRun = false, deleteBranch = deleteWithLease }) {
  const { owner, repo } = context.repo;
  const { data: repository } = await github.rest.repos.get({ owner, repo });
  const defaultBranch = repository.default_branch;
  if (context.eventName === 'push' && context.ref !== `refs/heads/${defaultBranch}`) return [];
  if (!['push', 'pull_request', 'workflow_dispatch'].includes(context.eventName)) return [];

  let candidates;
  if (context.eventName === 'pull_request') {
    const pr = context.payload.pull_request;
    if (context.payload.action !== 'closed' || !pr?.merged) return [];
    candidates = [pr];
  } else {
    // The latest closed PR for a reused branch wins, including unmerged PRs.
    const { data } = await github.rest.pulls.list({ owner, repo, state: 'closed', base: defaultBranch,
      sort: 'updated', direction: 'desc', per_page: 100 });
    candidates = [...data].sort((a, b) =>
      Date.parse(b.closed_at || b.merged_at) - Date.parse(a.closed_at || a.merged_at) || b.number - a.number);
  }
  const open = await github.paginate(github.rest.pulls.list, { owner, repo, state: 'open', per_page: 100 });
  const active = new Set(open.flatMap(pr => [pr.head, pr.base]
    .filter(ref => ref?.repo?.id === repository.id).map(ref => ref.ref)));
  const seen = new Set(), results = [];
  const record = (branch, status) => { core.info(`${branch}: ${status}`); results.push({ branch, status }); };
  const getBranch = async branch => {
    try { return (await github.rest.repos.getBranch({ owner, repo, branch })).data; }
    catch (error) { if (error.status === 404) return null; throw error; }
  };
  if (token) core.setSecret(Buffer.from(`x-access-token:${token}`).toString('base64'));

  for (const pr of candidates) {
    const branch = pr.head?.ref;
    if (!branch || pr.head?.repo?.id !== repository.id || seen.has(branch)) continue;
    seen.add(branch);
    if (!pr.merged_at || pr.base?.ref !== defaultBranch) { record(branch, 'kept: PR not merged into default branch'); continue; }
    if (branch === defaultBranch || active.has(branch)) { record(branch, 'kept: default branch or open PR'); continue; }
    const current = await getBranch(branch);
    if (!current) { record(branch, 'already absent'); continue; }
    if (current.protected) { record(branch, 'kept: protected branch'); continue; }
    if (current.commit.sha !== pr.head.sha) { record(branch, 'kept: new commits since merge'); continue; }
    // A recovery page or a delayed merge event must not delete a reused branch.
    const { data: latest } = await github.rest.pulls.list({ owner, repo, state: 'all',
      head: `${owner}:${branch}`, sort: 'created', direction: 'desc', per_page: 1 });
    const newest = latest[0];
    if (newest?.number !== pr.number || !newest.merged_at || newest.head?.repo?.id !== repository.id ||
        newest.head?.ref !== branch || newest.head?.sha !== pr.head.sha) {
      record(branch, 'kept: branch reused by another PR'); continue;
    }
    if (dryRun) { record(branch, 'would delete (dry run)'); continue; }
    try {
      await deleteBranch({ remote: repository.clone_url, branch, expectedSha: pr.head.sha, token, serverUrl: context.serverUrl });
      record(branch, 'deleted');
    } catch (error) {
      const after = await getBranch(branch);
      if (!after) record(branch, 'already absent');
      else if (after.commit.sha !== pr.head.sha) record(branch, 'kept: branch moved during cleanup');
      else throw error;
    }
  }
  return results;
}

module.exports = { run, deleteWithLease };
