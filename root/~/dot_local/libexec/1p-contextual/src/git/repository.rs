use std::path::Path;
use std::process::{Command, Stdio};

fn git(configuration: &[String], arguments: &[&str]) -> Option<String> {
	let mut command = Command::new("git");
	for setting in configuration {
		command.arg("-c").arg(setting);
	}
	let output = command.args(arguments).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
	if !output.status.success() {
		return None;
	}
	let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
	(!text.is_empty()).then_some(text)
}

fn file_name(path: &Path) -> Option<String> {
	path.file_name().map(|name| name.to_string_lossy().into_owned())
}

pub fn worktree() -> Option<String> {
	file_name(Path::new(&git(&[], &["rev-parse", "--show-toplevel"])?))
}

pub fn current_branch() -> Option<String> {
	git(&[], &["branch", "--show-current"])
}

pub fn origin_url() -> Option<String> {
	git(&[], &["remote", "get-url", "origin"])
}

pub fn folder() -> Option<String> {
	let common = git(&[], &["rev-parse", "--path-format=absolute", "--git-common-dir"])?;
	let common = Path::new(&common);
	let repository = if common.file_name()? == ".git" { common.parent()? } else { common };
	file_name(repository)
}

pub fn has_tag(name: &str) -> bool {
	git(&[], &["rev-parse", "--verify", "--quiet", &format!("refs/tags/{name}")]).is_some()
}

fn branch_of_remote_ref(remote_ref: &str) -> Option<String> {
	let (_remote, branch) = remote_ref.strip_prefix("refs/remotes/")?.split_once('/')?;
	Some(branch.to_string())
}

pub fn push_target(configuration: &[String]) -> Option<String> {
	branch_of_remote_ref(&git(configuration, &["rev-parse", "--symbolic-full-name", "@{push}"])?)
}

pub fn commits_not_on_remote(configuration: &[String], sources: &[String], remote: Option<&str>) -> Option<u32> {
	if sources.is_empty() {
		return None;
	}
	let not_on_remote = remote.map_or_else(|| "--remotes".to_string(), |remote| format!("--remotes={remote}"));
	let mut arguments = vec!["rev-list", "--count"];
	arguments.extend(sources.iter().map(String::as_str));
	arguments.extend(["--not", not_on_remote.as_str()]);
	git(configuration, &arguments)?.parse().ok()
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn reads_the_branch_of_a_remote_ref() {
		assert_eq!(branch_of_remote_ref("refs/remotes/origin/main"), Some("main".to_string()));
		assert_eq!(branch_of_remote_ref("refs/remotes/origin/claude/feature"), Some("claude/feature".to_string()));
		assert_eq!(branch_of_remote_ref("refs/heads/main"), None);
	}
}
