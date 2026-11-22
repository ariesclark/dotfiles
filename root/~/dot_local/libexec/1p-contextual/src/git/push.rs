pub struct Push {
	pub configuration: Vec<String>,
	remote: Option<String>,
	refspecs: Vec<String>,
	all: bool,
	mirror: bool,
	tags: bool,
	delete: bool,
}

const GLOBAL_OPTIONS_WITH_VALUES: [&str; 5] = ["-C", "-c", "--git-dir", "--work-tree", "--namespace"];
const PUSH_OPTIONS_WITH_VALUES: [&str; 5] = ["-o", "--push-option", "--receive-pack", "--exec", "--repo"];

fn is_git(program: &str) -> bool {
	let file = program.rsplit(['/', '\\']).next().unwrap_or(program);
	file.strip_suffix(".exe").unwrap_or(file) == "git"
}

pub fn parse(arguments: &[String]) -> Option<Push> {
	let (program, rest) = arguments.split_first()?;
	if !is_git(program) {
		return None;
	}
	let mut rest = rest.iter();
	let mut configuration = Vec::new();
	loop {
		let token = rest.next()?;
		if token == "-c" {
			configuration.push(rest.next()?.clone());
		} else if GLOBAL_OPTIONS_WITH_VALUES.contains(&token.as_str()) {
			rest.next()?;
		} else if token == "push" {
			break;
		} else if !token.starts_with('-') {
			return None;
		}
	}
	let mut push = Push { configuration, remote: None, refspecs: Vec::new(), all: false, mirror: false, tags: false, delete: false };
	let mut positionals = Vec::new();
	while let Some(token) = rest.next() {
		match token.as_str() {
			"--all" | "--branches" => push.all = true,
			"--mirror" => push.mirror = true,
			"--tags" => push.tags = true,
			"--delete" | "-d" => push.delete = true,
			"--" => {
				positionals.extend(rest.by_ref().cloned());
				break;
			}
			option if PUSH_OPTIONS_WITH_VALUES.contains(&option) => {
				rest.next();
			}
			option if option.starts_with('-') => {}
			_ => positionals.push(token.clone()),
		}
	}
	push.remote = positionals.first().cloned();
	push.refspecs = positionals.into_iter().skip(1).collect();
	Some(push)
}

fn short_ref(reference: &str) -> String {
	if let Some(tag) = reference.strip_prefix("refs/tags/") {
		return format!("tag {tag}");
	}
	reference.strip_prefix("refs/heads/").unwrap_or(reference).to_string()
}

impl Push {
	fn destination(&self, refspec: &str, current_branch: Option<&str>) -> String {
		let refspec = refspec.strip_prefix('+').unwrap_or(refspec);
		if self.delete {
			return format!("delete {}", short_ref(refspec));
		}
		match refspec.split_once(':') {
			Some(("", deleted)) => format!("delete {}", short_ref(deleted)),
			Some((_, target)) => short_ref(target),
			None if refspec == "HEAD" => current_branch.unwrap_or("HEAD").to_string(),
			None => short_ref(refspec),
		}
	}

	pub fn destinations(&self, current_branch: Option<&str>) -> Vec<String> {
		let mut names = Vec::new();
		if self.all {
			names.push("all branches".to_string());
		}
		if self.mirror {
			names.push("everything".to_string());
		}
		if self.tags {
			names.push("all tags".to_string());
		}
		names.extend(self.refspecs.iter().map(|refspec| self.destination(refspec, current_branch)));
		names
	}

	pub fn sources(&self) -> Vec<String> {
		if self.all || self.mirror {
			return vec!["--branches".to_string()];
		}
		if self.delete {
			return Vec::new();
		}
		if self.refspecs.is_empty() {
			return if self.tags { Vec::new() } else { vec!["HEAD".to_string()] };
		}
		self.refspecs
			.iter()
			.filter_map(|refspec| {
				let refspec = refspec.strip_prefix('+').unwrap_or(refspec);
				let source = refspec.split_once(':').map_or(refspec, |(source, _)| source);
				(!source.is_empty()).then(|| source.to_string())
			})
			.collect()
	}

	pub fn tracking_remote(&self) -> Option<&str> {
		let remote = self.remote.as_deref()?;
		let is_location = remote.contains([':', '\\']) || remote.starts_with(['.', '/']);
		(!is_location).then_some(remote)
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn arguments(line: &str) -> Vec<String> {
		line.split(' ').map(str::to_string).collect()
	}

	fn push(line: &str) -> Push {
		parse(&arguments(line)).expect("a push command")
	}

	#[test]
	fn finds_no_push_in_other_commands() {
		assert!(parse(&arguments("git fetch origin")).is_none());
		assert!(parse(&arguments("git ls-remote origin")).is_none());
		assert!(parse(&arguments("ssh git@github.com git-receive-pack")).is_none());
	}

	#[test]
	fn takes_the_destination_after_the_colon() {
		assert_eq!(push("git push origin HEAD:main").destinations(Some("claude/feature")), ["main"]);
		assert_eq!(push("git push origin +HEAD:refs/heads/main").destinations(Some("claude/feature")), ["main"]);
		assert_eq!(push("git push origin feature:release/1").destinations(Some("main")), ["release/1"]);
	}

	#[test]
	fn pushes_a_lone_ref_to_its_own_name() {
		assert_eq!(push("git push origin main").destinations(Some("claude/feature")), ["main"]);
		assert_eq!(push("git push origin refs/heads/dev").destinations(Some("main")), ["dev"]);
	}

	#[test]
	fn pushes_head_to_the_current_branch() {
		assert_eq!(push("git push origin HEAD").destinations(Some("claude/feature")), ["claude/feature"]);
	}

	#[test]
	fn names_tags_and_deletions() {
		assert_eq!(push("git push origin refs/tags/v1").destinations(Some("main")), ["tag v1"]);
		assert_eq!(push("git push origin :old").destinations(Some("main")), ["delete old"]);
		assert_eq!(push("git push --delete origin old").destinations(Some("main")), ["delete old"]);
		assert_eq!(push("git push --tags origin").destinations(Some("main")), ["all tags"]);
	}

	#[test]
	fn names_every_destination_of_a_push() {
		assert_eq!(push("git push origin main dev").destinations(Some("main")), ["main", "dev"]);
		assert_eq!(push("git push --all origin").destinations(Some("main")), ["all branches"]);
		assert_eq!(push("git push --mirror origin").destinations(Some("main")), ["everything"]);
	}

	#[test]
	fn skips_global_options_and_option_values() {
		assert_eq!(push("git -C /repo -c push.default=current push --dry-run -o ci.skip origin HEAD:main").destinations(Some("x")), ["main"]);
		assert_eq!(push("git push --force-with-lease=main --push-option ci.skip origin HEAD:main").destinations(Some("x")), ["main"]);
		let windows_git = ["C:\\Program Files\\Git\\mingw64\\bin\\git.exe", "push", "origin", "HEAD:main"].map(str::to_string);
		assert_eq!(parse(&windows_git).expect("a push command").destinations(Some("x")), ["main"]);
	}

	#[test]
	fn leaves_a_bare_push_to_the_push_target() {
		assert!(push("git push").destinations(Some("main")).is_empty());
		assert!(push("git push origin").destinations(Some("main")).is_empty());
	}

	#[test]
	fn keeps_the_configuration_given_on_the_command_line() {
		assert_eq!(push("git -C /repo -c push.default=upstream -c core.sshCommand=ssh push").configuration, ["push.default=upstream", "core.sshCommand=ssh"]);
	}

	#[test]
	fn takes_what_each_refspec_pushes() {
		assert_eq!(push("git push origin HEAD:main").sources(), ["HEAD"]);
		assert_eq!(push("git push origin +feature:release").sources(), ["feature"]);
		assert_eq!(push("git push origin main dev").sources(), ["main", "dev"]);
		assert_eq!(push("git push origin refs/tags/v1").sources(), ["refs/tags/v1"]);
	}

	#[test]
	fn pushes_the_current_branch_without_a_refspec() {
		assert_eq!(push("git push").sources(), ["HEAD"]);
		assert_eq!(push("git push origin").sources(), ["HEAD"]);
	}

	#[test]
	fn pushes_every_branch_for_all_and_mirror() {
		assert_eq!(push("git push --all origin").sources(), ["--branches"]);
		assert_eq!(push("git push --mirror origin").sources(), ["--branches"]);
	}

	#[test]
	fn pushes_no_commits_for_deletions_and_tags_alone() {
		assert!(push("git push origin :old").sources().is_empty());
		assert!(push("git push --delete origin old").sources().is_empty());
		assert!(push("git push --tags origin").sources().is_empty());
	}

	#[test]
	fn tracks_a_named_remote_but_not_a_url_or_path() {
		assert_eq!(push("git push origin HEAD:main").tracking_remote(), Some("origin"));
		assert_eq!(push("git push git@github.com:owner/repo.git HEAD").tracking_remote(), None);
		assert_eq!(push("git push ssh://git@github.com/owner/repo.git HEAD").tracking_remote(), None);
		assert_eq!(push("git push ../other HEAD").tracking_remote(), None);
		assert_eq!(push("git push").tracking_remote(), None);
	}
}
