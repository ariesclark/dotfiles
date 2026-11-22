use crate::request::Request;

const SUBJECT_LIMIT: usize = 60;
const LABEL_LIMIT: usize = 120;

fn last_segment(path: &str) -> &str {
	path.rsplit('/').next().unwrap_or(path)
}

fn shorten(text: &str, limit: usize) -> String {
	if text.chars().count() <= limit {
		return text.to_string();
	}
	let mut shortened: String = text.chars().take(limit - 1).collect();
	shortened.push('\u{2026}');
	shortened
}

fn file_name_safe(text: &str) -> String {
	text.chars()
		.map(|character| match character {
			'/' => '\u{2215}',
			':' => '\u{A789}',
			'<' | '>' | '"' | '\\' | '|' | '?' | '*' => '-',
			character if character.is_control() => '-',
			character => character,
		})
		.collect()
}

fn place(repository: &str, branch: Option<&str>, worktree: Option<&str>) -> String {
	let branch = branch.filter(|branch| !branch.is_empty());
	let mut place = repository.to_string();
	if let Some(branch) = branch {
		place.push(':');
		place.push_str(branch);
	}
	let redundant = [Some(last_segment(repository)), branch, branch.map(last_segment)];
	if let Some(worktree) = worktree.filter(|worktree| !worktree.is_empty() && !redundant.contains(&Some(*worktree))) {
		place.push_str(&format!(" ({worktree})"));
	}
	place
}

pub fn label(request: &Request, worktree: Option<&str>) -> String {
	let text = match request {
		Request::Push { repository, destination, commits } => {
			let place = place(repository, destination.as_deref(), worktree);
			match commits {
				Some(1) => format!("pushing 1 commit to {place}"),
				Some(count) if *count > 1 => format!("pushing {count} commits to {place}"),
				_ => format!("pushing to {place}"),
			}
		}
		Request::Fetch { repository } => format!("fetching from {}", place(repository, None, worktree)),
		Request::Archive { repository } => format!("fetching an archive from {}", place(repository, None, worktree)),
		Request::Lfs { repository, upload: true } => format!("uploading LFS objects to {}", place(repository, None, worktree)),
		Request::Lfs { repository, upload: false } => format!("downloading LFS objects from {}", place(repository, None, worktree)),
		Request::Sign { repository, branch, tag, subject } => {
			let quoted = subject.as_deref().map(|subject| format!(" \u{201C}{}\u{201D}", shorten(subject, SUBJECT_LIMIT))).unwrap_or_default();
			match tag {
				Some(tag) => format!("signing tag {tag}{quoted} in {}", place(repository, None, worktree)),
				None => format!("signing{quoted} in {}", place(repository, branch.as_deref(), worktree)),
			}
		}
	};
	shorten(&file_name_safe(&text), LABEL_LIMIT)
}

#[cfg(any(windows, test))]
pub fn with_application(application: Option<&str>, label: &str) -> String {
	let subject = application.unwrap_or("git");
	format!("{},", shorten(&file_name_safe(&format!("{subject}, {label}")), LABEL_LIMIT - 1))
}

#[cfg(test)]
mod tests {
	use super::*;

	fn push(destination: Option<&str>, commits: Option<u32>) -> Request {
		Request::Push { repository: "owner/repo".to_string(), destination: destination.map(str::to_string), commits }
	}

	fn sign(branch: Option<&str>, tag: Option<&str>, subject: Option<&str>) -> Request {
		Request::Sign { repository: "owner/repo".to_string(), branch: branch.map(str::to_string), tag: tag.map(str::to_string), subject: subject.map(str::to_string) }
	}

	#[test]
	fn names_a_push_for_its_repository_destination_and_worktree() {
		assert_eq!(label(&push(Some("claude/feature"), None), Some("elsewhere")), "pushing to owner∕repo꞉claude∕feature (elsewhere)");
		assert_eq!(label(&push(Some("main, dev"), None), Some("elsewhere")), "pushing to owner∕repo꞉main, dev (elsewhere)");
	}

	#[test]
	fn counts_the_commits_a_push_carries() {
		assert_eq!(label(&push(Some("main"), Some(3)), Some("elsewhere")), "pushing 3 commits to owner∕repo꞉main (elsewhere)");
		assert_eq!(label(&push(Some("main"), Some(1)), Some("elsewhere")), "pushing 1 commit to owner∕repo꞉main (elsewhere)");
		assert_eq!(label(&push(Some("main"), Some(0)), Some("elsewhere")), "pushing to owner∕repo꞉main (elsewhere)");
	}

	#[test]
	fn leaves_the_worktree_out_when_the_branch_or_its_last_part_names_it() {
		assert_eq!(label(&push(Some("claude/feature-x"), None), Some("feature-x")), "pushing to owner∕repo꞉claude∕feature-x");
		assert_eq!(label(&push(Some("feature-x"), None), Some("feature-x")), "pushing to owner∕repo꞉feature-x");
	}

	#[test]
	fn leaves_the_worktree_out_when_it_is_named_for_the_repository() {
		assert_eq!(label(&push(Some("main"), None), Some("repo")), "pushing to owner∕repo꞉main");
	}

	#[test]
	fn names_a_push_without_a_known_destination_by_its_repository() {
		assert_eq!(label(&push(None, None), Some("elsewhere")), "pushing to owner∕repo (elsewhere)");
	}

	#[test]
	fn names_fetches_archives_and_lfs_by_their_repository() {
		let repository = || "owner/repo".to_string();
		assert_eq!(label(&Request::Fetch { repository: repository() }, Some("elsewhere")), "fetching from owner∕repo (elsewhere)");
		assert_eq!(label(&Request::Archive { repository: repository() }, Some("repo")), "fetching an archive from owner∕repo");
		assert_eq!(label(&Request::Lfs { repository: repository(), upload: true }, Some("elsewhere")), "uploading LFS objects to owner∕repo (elsewhere)");
		assert_eq!(label(&Request::Lfs { repository: repository(), upload: false }, Some("elsewhere")), "downloading LFS objects from owner∕repo (elsewhere)");
	}

	#[test]
	fn names_a_commit_signature_for_its_subject_and_branch() {
		assert_eq!(label(&sign(Some("claude/feature"), None, Some("feat(git): sign it")), Some("elsewhere")), "signing “feat(git)꞉ sign it” in owner∕repo꞉claude∕feature (elsewhere)");
	}

	#[test]
	fn names_a_tag_signature_without_a_branch() {
		assert_eq!(label(&sign(Some("claude/feature-x"), Some("v1"), Some("release it")), Some("feature-x")), "signing tag v1 “release it” in owner∕repo (feature-x)");
	}

	#[test]
	fn names_a_signature_without_a_subject_by_its_place() {
		assert_eq!(label(&sign(Some("main"), None, None), Some("repo")), "signing in owner∕repo꞉main");
	}

	#[test]
	fn cuts_a_long_subject_at_sixty_characters() {
		let subject = "a".repeat(70);
		assert_eq!(label(&sign(Some("main"), None, Some(&subject)), Some("repo")), format!("signing “{}…” in owner∕repo꞉main", "a".repeat(59)));
	}

	#[test]
	fn replaces_characters_a_file_name_cannot_hold() {
		assert_eq!(label(&sign(Some("main"), None, Some("fix: \"quote\" <a|b> what? * c\\d")), Some("repo")), "signing “fix꞉ -quote- -a-b- what- - c-d” in owner∕repo꞉main");
	}

	#[test]
	fn sets_the_request_between_commas_after_the_application() {
		assert_eq!(with_application(Some("Claude"), "pushing to owner∕repo꞉main"), "Claude, pushing to owner∕repo꞉main,");
	}

	#[test]
	fn names_git_without_an_application() {
		assert_eq!(with_application(None, "pushing to owner∕repo꞉main"), "git, pushing to owner∕repo꞉main,");
	}

	#[test]
	fn replaces_characters_a_file_name_cannot_hold_in_the_application() {
		assert_eq!(with_application(Some("Tools/Git: <Shell>"), "fetching from owner∕repo"), "Tools∕Git꞉ -Shell-, fetching from owner∕repo,");
	}

	#[test]
	fn keeps_the_closing_comma_when_it_cuts_a_label_at_a_hundred_and_twenty_characters() {
		let labeled = with_application(Some("Claude"), &format!("pushing to owner∕repo꞉{}", "b".repeat(110)));
		assert_eq!(labeled, format!("Claude, pushing to owner∕repo꞉{}…,", "b".repeat(88)));
		assert_eq!(labeled.chars().count(), 120);
	}

	#[test]
	fn keeps_the_whole_label_within_a_hundred_and_twenty_characters() {
		let branch = "b".repeat(200);
		let labeled = label(&push(Some(&branch), None), Some("repo"));
		assert_eq!(labeled.chars().count(), 120);
		assert_eq!(labeled, format!("pushing to owner∕repo꞉{}…", "b".repeat(97)));
	}
}
