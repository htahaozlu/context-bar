use std::borrow::Cow;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[cfg(target_arch = "wasm32")]
use zed_extension_api::{self as zed, process::Command};

#[derive(Clone, Debug, serde::Serialize)]
pub struct CommitSummary {
    pub sha: String,
    pub subject: String,
    /// Author commit time. Optional because old data on disk may omit it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub committed_at: Option<String>,
    #[serde(skip)]
    pub committed_at_system: Option<SystemTime>,
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct ChangeSummary {
    pub path: String,
    pub code: String,
    pub staged: bool,
    pub unstaged: bool,
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct GitSignals {
    pub branch: String,
    pub recent_commits: Vec<CommitSummary>,
    pub staged_changes: Vec<ChangeSummary>,
    pub unstaged_changes: Vec<ChangeSummary>,
    pub clean_worktree: bool,
}

#[cfg(target_arch = "wasm32")]
pub fn collect(worktree: &zed::Worktree) -> Result<GitSignals, String> {
    let branch = run_git(worktree, ["rev-parse", "--abbrev-ref", "HEAD"])?
        .trim()
        .to_string();

    let recent_commits = parse_commits(&run_git(
        worktree,
        ["log", "--since=7 days ago", "--max-count=40", "--format=%H%x09%ct%x09%s"],
    )?);

    let status = run_git(worktree, ["status", "--short"])?;
    let (staged_changes, unstaged_changes) = parse_status(&status);

    Ok(GitSignals {
        branch,
        recent_commits,
        clean_worktree: staged_changes.is_empty() && unstaged_changes.is_empty(),
        staged_changes,
        unstaged_changes,
    })
}

#[cfg(target_arch = "wasm32")]
fn run_git<'a>(
    worktree: &zed::Worktree,
    args: impl IntoIterator<Item = &'a str>,
) -> Result<String, String> {
    let git = worktree
        .which("git")
        .ok_or_else(|| "git binary was not found in the worktree environment".to_string())?;

    let mut command = Command::new(git);
    command = command.arg("-C").arg(worktree.root_path());
    command = command.args(args);
    command = command.envs(worktree.shell_env());

    let output = command.output()?;
    if output.status == Some(0) {
        String::from_utf8(output.stdout)
            .map_err(|error| format!("git output was not valid UTF-8: {error}"))
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!(
            "git command failed with status {:?}: {}",
            output.status,
            stderr.trim()
        ))
    }
}

pub fn parse_commits(raw: &str) -> Vec<CommitSummary> {
    raw.lines()
        .filter_map(|line| {
            let mut parts = line.splitn(3, '\t');
            let sha = parts.next()?;
            let second = parts.next()?;
            // Two formats supported: "%H\t%ct\t%s" (preferred) and "%H\t%s".
            let (committed_at_system, subject) = match parts.next() {
                Some(subject) => {
                    let epoch: u64 = second.trim().parse().ok()?;
                    (Some(UNIX_EPOCH + Duration::from_secs(epoch)), subject)
                }
                None => (None, second),
            };
            let committed_at = committed_at_system
                .and_then(|time| {
                    use time::{OffsetDateTime, format_description::well_known::Rfc3339};
                    OffsetDateTime::from(time).format(&Rfc3339).ok()
                });
            Some(CommitSummary {
                sha: sha.chars().take(7).collect(),
                subject: subject.trim().to_string(),
                committed_at,
                committed_at_system,
            })
        })
        .collect()
}

pub fn parse_status_public(raw: &str) -> (Vec<ChangeSummary>, Vec<ChangeSummary>) {
    parse_status(raw)
}

fn parse_status(raw: &str) -> (Vec<ChangeSummary>, Vec<ChangeSummary>) {
    let mut staged = Vec::new();
    let mut unstaged = Vec::new();

    for line in raw.lines() {
        if line.len() < 3 {
            continue;
        }

        let index_code = line.chars().next().unwrap_or(' ');
        let worktree_code = line.chars().nth(1).unwrap_or(' ');
        let path = line[3..].trim().to_string();

        if index_code != ' ' && index_code != '?' {
            staged.push(ChangeSummary {
                path: normalize_status_path(&path).into_owned(),
                code: index_code.to_string(),
                staged: true,
                unstaged: false,
            });
        }

        if worktree_code != ' ' || (index_code == '?' && worktree_code == '?') {
            unstaged.push(ChangeSummary {
                path: normalize_status_path(&path).into_owned(),
                code: if index_code == '?' && worktree_code == '?' {
                    "??".to_string()
                } else {
                    worktree_code.to_string()
                },
                staged: false,
                unstaged: true,
            });
        }
    }

    (staged, unstaged)
}

fn normalize_status_path(path: &str) -> Cow<'_, str> {
    if let Some((_, new_path)) = path.split_once(" -> ") {
        Cow::Owned(new_path.to_string())
    } else {
        Cow::Borrowed(path)
    }
}

#[cfg(test)]
mod tests {
    use super::parse_status;

    #[test]
    fn parses_git_status_into_staged_and_unstaged_views() {
        let raw = "M  src/lib.rs\n M README.md\nR  old.rs -> new.rs\n?? src/new.rs\n";
        let (staged, unstaged) = parse_status(raw);

        assert_eq!(staged.len(), 2);
        assert_eq!(staged[0].path, "src/lib.rs");
        assert_eq!(staged[1].path, "new.rs");

        assert_eq!(unstaged.len(), 2);
        assert_eq!(unstaged[0].path, "README.md");
        assert_eq!(unstaged[1].code, "??");
    }
}
