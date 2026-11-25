use std::sync::LazyLock;

use serde::Deserialize;

use crate::request::{Deletion, Request, Update};

const SUBJECT_LIMIT: usize = 60;
#[cfg(any(windows, test))]
const LABEL_LIMIT: usize = 120;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Plural {
	one: String,
	other: String,
}

impl Plural {
	fn of(&self, count: usize) -> &str {
		if count == 1 { &self.one } else { &self.other }
	}
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct List {
	separator: String,
	last_separator: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Push {
	uncounted: String,
	counted: Plural,
	also_deleting: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Updates {
	tag: String,
	all_branches: String,
	everything: String,
	all_tags: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Deleted {
	branches: Plural,
	tags: Plural,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Lfs {
	upload: String,
	download: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Sign {
	commit: String,
	commit_with_subject: String,
	tag: String,
	tag_with_subject: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Phrases {
	#[cfg_attr(not(any(windows, test)), allow(dead_code))]
	prompt: String,
	#[cfg_attr(not(any(windows, test)), allow(dead_code))]
	unknown_application: String,
	#[cfg_attr(not(any(windows, test)), allow(dead_code))]
	with_worktree: String,
	list: List,
	place: String,
	push: Push,
	update: Updates,
	delete: String,
	deleted: Deleted,
	fetch: String,
	archive: String,
	lfs: Lfs,
	sign: Sign,
}

static PHRASES: LazyLock<Phrases> = LazyLock::new(|| serde_json::from_str(include_str!("../translations/en-US.json")).expect("translations/en-US.json should hold every phrase"));

fn fill(template: &str, values: &[(&str, &str)]) -> String {
	let mut filled = String::with_capacity(template.len());
	let mut rest = template;
	while let Some(start) = rest.find('{') {
		filled.push_str(&rest[..start]);
		let after = &rest[start + 1..];
		let value = after.find('}').and_then(|end| values.iter().find(|(name, _)| *name == &after[..end]).map(|(_, value)| (end, value)));
		match value {
			Some((end, value)) => {
				filled.push_str(value);
				rest = &after[end + 1..];
			}
			None => {
				filled.push('{');
				rest = after;
			}
		}
	}
	filled.push_str(rest);
	filled
}

fn listed(items: &[String]) -> String {
	let list = &PHRASES.list;
	match items {
		[] => String::new(),
		[only] => only.clone(),
		[first @ .., last] => format!("{}{}{last}", first.join(&list.separator), list.last_separator),
	}
}

fn last_segment(path: &str) -> &str {
	path.rsplit('/').next().unwrap_or(path)
}

fn shorten(text: &str, limit: usize) -> String {
	if text.chars().count() <= limit {
		return text.to_string();
	}
	let mut shortened: String = text.chars().take(limit.saturating_sub(1)).collect();
	shortened.push('\u{2026}');
	shortened
}

#[cfg(any(windows, test))]
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

fn update_name(update: &Update) -> String {
	let phrases = &PHRASES.update;
	match update {
		Update::Branch(branch) => branch.clone(),
		Update::Tag(tag) => fill(&phrases.tag, &[("name", tag)]),
		Update::AllBranches => phrases.all_branches.clone(),
		Update::Everything => phrases.everything.clone(),
		Update::AllTags => phrases.all_tags.clone(),
	}
}

fn place(repository: &str, destination: &str) -> String {
	if destination.is_empty() {
		return repository.to_string();
	}
	fill(&PHRASES.place, &[("repository", repository), ("destination", destination)])
}

fn deletions_named(deletions: &[Deletion]) -> String {
	let branches: Vec<String> = deletions.iter().filter_map(|deletion| if let Deletion::Branch(name) = deletion { Some(name.clone()) } else { None }).collect();
	let tags: Vec<String> = deletions.iter().filter_map(|deletion| if let Deletion::Tag(name) = deletion { Some(name.clone()) } else { None }).collect();
	let groups: Vec<String> = [(&PHRASES.deleted.branches, branches), (&PHRASES.deleted.tags, tags)]
		.into_iter()
		.filter(|(_, names)| !names.is_empty())
		.map(|(phrase, names)| fill(phrase.of(names.len()), &[("names", &listed(&names))]))
		.collect();
	listed(&groups)
}

fn push_text(repository: &str, updates: &[Update], commits: Option<u32>, deletions: &[Deletion]) -> String {
	if updates.is_empty() && !deletions.is_empty() {
		return fill(&PHRASES.delete, &[("deletions", &deletions_named(deletions)), ("repository", repository)]);
	}
	let destination = listed(&updates.iter().map(update_name).collect::<Vec<_>>());
	let place = place(repository, &destination);
	let pushing = match commits.filter(|&count| count > 0) {
		Some(count) => fill(PHRASES.push.counted.of(count as usize), &[("count", &count.to_string()), ("place", &place)]),
		None => fill(&PHRASES.push.uncounted, &[("place", &place)]),
	};
	if deletions.is_empty() {
		return pushing;
	}
	fill(&PHRASES.push.also_deleting, &[("push", &pushing), ("deletions", &deletions_named(deletions))])
}

fn request_text(request: &Request) -> String {
	match request {
		Request::Push { repository, updates, commits, deletions } => push_text(repository, updates, *commits, deletions),
		Request::Fetch { repository } => fill(&PHRASES.fetch, &[("repository", repository)]),
		Request::Archive { repository } => fill(&PHRASES.archive, &[("repository", repository)]),
		Request::Lfs { repository, upload: true } => fill(&PHRASES.lfs.upload, &[("repository", repository)]),
		Request::Lfs { repository, upload: false } => fill(&PHRASES.lfs.download, &[("repository", repository)]),
		Request::Sign { repository, branch, tag, subject } => {
			let subject = subject.as_deref().map(|subject| shorten(subject, SUBJECT_LIMIT));
			let phrases = &PHRASES.sign;
			match (tag, subject) {
				(Some(tag), Some(subject)) => fill(&phrases.tag_with_subject, &[("tag", tag), ("subject", &subject), ("repository", repository)]),
				(Some(tag), None) => fill(&phrases.tag, &[("tag", tag), ("repository", repository)]),
				(None, subject) => {
					let place = place(repository, branch.as_deref().unwrap_or_default());
					match subject {
						Some(subject) => fill(&phrases.commit_with_subject, &[("subject", &subject), ("place", &place)]),
						None => fill(&phrases.commit, &[("place", &place)]),
					}
				}
			}
		}
	}
}

fn names_of_branches(request: &Request) -> Vec<&str> {
	match request {
		Request::Push { updates, .. } => updates.iter().filter_map(|update| if let Update::Branch(branch) = update { Some(branch.as_str()) } else { None }).collect(),
		Request::Sign { branch: Some(branch), tag: None, .. } => vec![branch.as_str()],
		_ => Vec::new(),
	}
}

fn repository_of(request: &Request) -> &str {
	match request {
		Request::Push { repository, .. }
		| Request::Fetch { repository }
		| Request::Archive { repository }
		| Request::Lfs { repository, .. }
		| Request::Sign { repository, .. } => repository,
	}
}

pub struct Label {
	pub request: String,
	pub worktree: Option<String>,
}

pub fn label(request: &Request, worktree: Option<&str>) -> Label {
	let branches = names_of_branches(request);
	let names_it = |worktree: &str| worktree == last_segment(repository_of(request)) || branches.iter().any(|branch| *branch == worktree || last_segment(branch) == worktree);
	let worktree = worktree.filter(|worktree| !worktree.is_empty() && !names_it(worktree)).map(str::to_string);
	Label { request: request_text(request), worktree }
}

#[cfg(any(windows, test))]
pub fn rendered(application: Option<&str>, label: &Label) -> String {
	let application = application.unwrap_or(&PHRASES.unknown_application);
	let prompt = |request: &str| file_name_safe(&fill(&PHRASES.prompt, &[("application", application), ("request", request)]));
	if let Some(worktree) = &label.worktree {
		let with_worktree = prompt(&fill(&PHRASES.with_worktree, &[("request", &label.request), ("worktree", worktree)]));
		if with_worktree.chars().count() <= LABEL_LIMIT {
			return with_worktree;
		}
	}
	let room = LABEL_LIMIT.saturating_sub(prompt("").chars().count());
	shorten(&prompt(&shorten(&label.request, room)), LABEL_LIMIT)
}

#[cfg(test)]
mod tests {
	use super::*;

	fn push(updates: Vec<Update>, commits: Option<u32>, deletions: Vec<Deletion>) -> Request {
		Request::Push { repository: "owner/repo".to_string(), updates, commits, deletions }
	}

	fn branch(name: &str) -> Update {
		Update::Branch(name.to_string())
	}

	fn sign(branch: Option<&str>, tag: Option<&str>, subject: Option<&str>) -> Request {
		Request::Sign { repository: "owner/repo".to_string(), branch: branch.map(str::to_string), tag: tag.map(str::to_string), subject: subject.map(str::to_string) }
	}

	fn shown(request: &Request, worktree: Option<&str>) -> String {
		rendered(Some("App"), &label(request, worktree))
	}

	#[test]
	fn reads_every_phrase_from_the_translations() {
		LazyLock::force(&PHRASES);
	}

	#[test]
	fn fills_each_placeholder_once_without_reading_placeholders_in_values() {
		assert_eq!(fill("{a} and {b}", &[("a", "{b}"), ("b", "two")]), "{b} and two");
		assert_eq!(fill("{unknown} {a", &[("a", "one")]), "{unknown} {a");
	}

	#[test]
	fn lists_items_with_a_final_and() {
		let items = |names: &[&str]| names.iter().map(|name| name.to_string()).collect::<Vec<_>>();
		assert_eq!(listed(&items(&[])), "");
		assert_eq!(listed(&items(&["a"])), "a");
		assert_eq!(listed(&items(&["a", "b"])), "a and b");
		assert_eq!(listed(&items(&["a", "b", "c"])), "a, b and c");
	}

	#[test]
	fn names_a_push_for_its_repository_destination_and_worktree() {
		assert_eq!(shown(&push(vec![branch("claude/feature")], None, vec![]), Some("elsewhere")), "App, pushing to owner∕repo꞉claude∕feature (elsewhere),");
		assert_eq!(shown(&push(vec![branch("main"), branch("dev")], None, vec![]), Some("elsewhere")), "App, pushing to owner∕repo꞉main and dev (elsewhere),");
		assert_eq!(shown(&push(vec![Update::Tag("v1".to_string()), Update::AllTags], None, vec![]), None), "App, pushing to owner∕repo꞉tag v1 and all tags,");
	}

	#[test]
	fn counts_the_commits_a_push_carries() {
		assert_eq!(shown(&push(vec![branch("main")], Some(3), vec![]), Some("elsewhere")), "App, pushing 3 commits to owner∕repo꞉main (elsewhere),");
		assert_eq!(shown(&push(vec![branch("main")], Some(1), vec![]), Some("elsewhere")), "App, pushing 1 commit to owner∕repo꞉main (elsewhere),");
		assert_eq!(shown(&push(vec![branch("main")], Some(0), vec![]), Some("elsewhere")), "App, pushing to owner∕repo꞉main (elsewhere),");
	}

	#[test]
	fn names_a_deletion_for_what_it_deletes() {
		let old = || Deletion::Branch("old".to_string());
		assert_eq!(shown(&push(vec![], None, vec![old()]), Some("elsewhere")), "App, deleting branch old from owner∕repo (elsewhere),");
		assert_eq!(shown(&push(vec![], None, vec![Deletion::Tag("v1".to_string())]), None), "App, deleting tag v1 from owner∕repo,");
		let several = vec![old(), Deletion::Tag("v1".to_string()), Deletion::Branch("older".to_string())];
		assert_eq!(shown(&push(vec![], None, several), None), "App, deleting branches old and older and tag v1 from owner∕repo,");
	}

	#[test]
	fn names_a_push_that_also_deletes() {
		let request = push(vec![branch("main")], Some(2), vec![Deletion::Branch("old".to_string())]);
		assert_eq!(shown(&request, Some("elsewhere")), "App, pushing 2 commits to owner∕repo꞉main and deleting branch old (elsewhere),");
	}

	#[test]
	fn leaves_the_worktree_out_when_the_branch_or_its_last_part_names_it() {
		assert_eq!(shown(&push(vec![branch("claude/feature-x")], None, vec![]), Some("feature-x")), "App, pushing to owner∕repo꞉claude∕feature-x,");
		assert_eq!(shown(&push(vec![branch("feature-x")], None, vec![]), Some("feature-x")), "App, pushing to owner∕repo꞉feature-x,");
	}

	#[test]
	fn leaves_the_worktree_out_when_it_is_named_for_the_repository() {
		assert_eq!(shown(&push(vec![branch("main")], None, vec![]), Some("repo")), "App, pushing to owner∕repo꞉main,");
	}

	#[test]
	fn names_a_push_without_a_known_destination_by_its_repository() {
		assert_eq!(shown(&push(vec![], None, vec![]), Some("elsewhere")), "App, pushing to owner∕repo (elsewhere),");
	}

	#[test]
	fn names_fetches_archives_and_lfs_by_their_repository() {
		let repository = || "owner/repo".to_string();
		assert_eq!(shown(&Request::Fetch { repository: repository() }, Some("elsewhere")), "App, fetching from owner∕repo (elsewhere),");
		assert_eq!(shown(&Request::Archive { repository: repository() }, Some("repo")), "App, fetching an archive from owner∕repo,");
		assert_eq!(shown(&Request::Lfs { repository: repository(), upload: true }, Some("elsewhere")), "App, uploading LFS objects to owner∕repo (elsewhere),");
		assert_eq!(shown(&Request::Lfs { repository: repository(), upload: false }, Some("elsewhere")), "App, downloading LFS objects from owner∕repo (elsewhere),");
	}

	#[test]
	fn names_a_commit_signature_for_its_subject_and_branch() {
		assert_eq!(shown(&sign(Some("claude/feature"), None, Some("feat(git): sign it")), Some("elsewhere")), "App, signing “feat(git)꞉ sign it” in owner∕repo꞉claude∕feature (elsewhere),");
	}

	#[test]
	fn names_a_tag_signature_without_a_branch() {
		assert_eq!(shown(&sign(Some("claude/feature-x"), Some("v1"), Some("release it")), Some("feature-x")), "App, signing tag v1 “release it” in owner∕repo (feature-x),");
		assert_eq!(shown(&sign(None, Some("v1"), None), None), "App, signing tag v1 in owner∕repo,");
	}

	#[test]
	fn names_a_signature_without_a_subject_by_its_place() {
		assert_eq!(shown(&sign(Some("main"), None, None), Some("repo")), "App, signing in owner∕repo꞉main,");
		assert_eq!(shown(&sign(None, None, None), None), "App, signing in owner∕repo,");
	}

	#[test]
	fn cuts_a_long_subject_at_sixty_characters() {
		let subject = "a".repeat(70);
		assert_eq!(shown(&sign(Some("main"), None, Some(&subject)), Some("repo")), format!("App, signing “{}…” in owner∕repo꞉main,", "a".repeat(59)));
	}

	#[test]
	fn replaces_characters_a_file_name_cannot_hold() {
		assert_eq!(shown(&sign(Some("main"), None, Some("fix: \"quote\" <a|b> what? * c\\d")), Some("repo")), "App, signing “fix꞉ -quote- -a-b- what- - c-d” in owner∕repo꞉main,");
		assert_eq!(rendered(Some("Tools/Git: <Shell>"), &label(&Request::Fetch { repository: "owner/repo".to_string() }, None)), "Tools∕Git꞉ -Shell-, fetching from owner∕repo,");
	}

	#[test]
	fn names_git_without_an_application() {
		assert_eq!(rendered(None, &label(&push(vec![branch("main")], None, vec![]), None)), "git, pushing to owner∕repo꞉main,");
	}

	#[test]
	fn leaves_out_a_worktree_that_would_not_fit_rather_than_cut_it() {
		let request = push(vec![branch("main")], Some(3), vec![]);
		let labeled = rendered(Some("Claude"), &label(&request, Some(&"w".repeat(90))));
		assert_eq!(labeled, "Claude, pushing 3 commits to owner∕repo꞉main,");
	}

	#[test]
	fn keeps_the_closing_comma_when_it_cuts_a_label_at_a_hundred_and_twenty_characters() {
		let labeled = rendered(Some("Claude"), &label(&push(vec![branch(&"b".repeat(110))], None, vec![]), Some("elsewhere")));
		assert_eq!(labeled, format!("Claude, pushing to owner∕repo꞉{}…,", "b".repeat(88)));
		assert_eq!(labeled.chars().count(), 120);
	}
}
