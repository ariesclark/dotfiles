#![cfg(windows)]

use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use std::{env, fs, thread};

use windows_sys::Win32::Foundation::{CloseHandle, FreeLibrary, FALSE, HMODULE};
use windows_sys::Win32::System::LibraryLoader::{FindResourceW, LoadLibraryExW, LoadResource, LockResource, SizeofResource, LOAD_LIBRARY_AS_DATAFILE, LOAD_LIBRARY_AS_IMAGE_RESOURCE};
use windows_sys::Win32::System::Threading::{GetExitCodeProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION};

const UNRESOLVABLE: &str = "ssh://git@nonexistent.invalid/owner/repo.git";
const SSH_KEYGEN: &str = "C:/Windows/System32/OpenSSH/ssh-keygen.exe";
const TEST_APP: &str = "Test App.exe";
const DESCRIBED_APP: &str = "Described App.exe";
const ICONIC_APP: &str = "Iconic App.exe";
const ICON_IMAGE: &[u8] = b"\x89PNG\r\n\x1a\n an icon only the iconic app carries";

struct Fixture {
	root: tempfile::TempDir,
}

impl Fixture {
	fn new() -> Self {
		let root = tempfile::tempdir().expect("a temporary directory");
		let built = env::current_exe().expect("the test's own path").parent().and_then(Path::parent).expect("the build directory").to_path_buf();
		fs::create_dir(root.path().join("programs")).unwrap();
		fs::create_dir(root.path().join("temp")).unwrap();
		for (built_as, named) in [("ssh.exe", "ssh.exe"), ("op-ssh-sign.exe", "op-ssh-sign.exe"), ("examples/lister.exe", "lister.exe")] {
			fs::copy(built.join(built_as), root.path().join("programs").join(named)).unwrap_or_else(|error| panic!("{built_as} should be built: {error}"));
		}
		for app in [TEST_APP, DESCRIBED_APP, ICONIC_APP] {
			fs::copy(built.join("examples/app.exe"), root.path().join("programs").join(app)).expect("examples/app.exe should be built");
		}
		let changer = root.path().join("programs").join(DESCRIBED_APP);
		let stripped = Command::new(&changer).arg("--strip-resources").arg(root.path().join("programs").join(TEST_APP)).status();
		assert!(stripped.expect("the app should run").success(), "{TEST_APP} should lose its version information and icon");
		fs::write(root.path().join("icon-image"), ICON_IMAGE).unwrap();
		let given = Command::new(&changer).arg("--give-icon").arg(root.path().join("programs").join(ICONIC_APP)).arg(root.path().join("icon-image")).status();
		assert!(given.expect("the app should run").success(), "{ICONIC_APP} should carry its own icon");
		Fixture { root }
	}

	fn path(&self, relative: &str) -> PathBuf {
		self.root.path().join(relative)
	}

	fn program(&self, name: &str) -> String {
		self.path("programs").join(name).to_string_lossy().replace('\\', "/")
	}

	fn command(&self, program: impl AsRef<OsStr>, directory: &Path) -> Command {
		let mut command = Command::new(program);
		command
			.current_dir(directory)
			.env("GIT_CONFIG_GLOBAL", "NUL")
			.env("GIT_CONFIG_NOSYSTEM", "1")
			.env("TEMP", self.path("temp"))
			.env("TMP", self.path("temp"))
			.env("CONTEXTUAL_LISTING", self.path("listing"))
			.stdin(Stdio::null())
			.stdout(Stdio::null())
			.stderr(Stdio::null());
		command
	}

	fn from_app(&self, app: &str, directory: &Path, arguments: &[&str], environment: &[(&str, &str)]) -> i32 {
		let status = self.path("status");
		let detached = self.command(self.path("programs").join(app), directory).envs(environment.iter().copied()).arg("--detach").arg(&status).args(arguments).status();
		assert!(detached.expect("the app should run").success());
		let code = wait_until(Duration::from_secs(60), || fs::read_to_string(&status).ok()).expect("the app should finish its command");
		fs::remove_file(&status).unwrap();
		code.trim().parse().expect("the app should record an exit code")
	}

	fn git_from(&self, app: &str, directory: &Path, arguments: &[&str]) -> i32 {
		let mut all = vec!["git", "-c", "init.defaultBranch=main", "-c", "user.name=Stub", "-c", "user.email=stub@example.com"];
		all.extend(["-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", "-c", "gpg.format=ssh"]);
		all.extend(arguments);
		self.from_app(app, directory, &all, &[])
	}

	fn git(&self, directory: &Path, arguments: &[&str]) -> i32 {
		self.git_from(TEST_APP, directory, arguments)
	}

	fn checkout(&self, name: &str, branch: Option<&str>) -> PathBuf {
		self.git(self.root.path(), &["init", "--quiet", name]);
		let checkout = self.path(name);
		self.git(&checkout, &["commit", "--quiet", "--allow-empty", "--message", "scratch"]);
		if let Some(branch) = branch {
			self.git(&checkout, &["switch", "--quiet", "--create", branch]);
		}
		self.git(&checkout, &["remote", "add", "origin", "https://github.com/owner/repo.git"]);
		checkout
	}

	fn ssh_command(&self) -> String {
		format!("core.sshCommand={} {}", self.program("ssh.exe"), self.program("lister.exe"))
	}

	fn push(&self, checkout: &Path, arguments: &[&str]) {
		let ssh_command = self.ssh_command();
		let mut all = vec!["-c", ssh_command.as_str(), "push", "--dry-run", UNRESOLVABLE];
		all.extend(arguments);
		self.git(checkout, &all);
	}

	fn signing_key(&self) -> String {
		let key = self.path("signing-key");
		if !key.exists() {
			let status = Command::new(SSH_KEYGEN).args(["-q", "-t", "ed25519", "-N", "", "-C", "", "-f"]).arg(&key).status().expect("ssh-keygen should run");
			assert!(status.success());
		}
		key.to_string_lossy().replace('\\', "/")
	}

	fn sign(&self, checkout: &Path, signer: &str, arguments: &[&str]) -> i32 {
		let program = format!("gpg.ssh.program={}", self.program("op-ssh-sign.exe"));
		let key = format!("user.signingkey={}", self.signing_key());
		let mut all = vec!["git", "-c", "user.name=Stub", "-c", "user.email=stub@example.com", "-c", "gpg.format=ssh", "-c", &program, "-c", &key];
		all.extend(arguments);
		self.from_app(TEST_APP, checkout, &all, &[("OP_SSH_SIGN_CONTEXTUAL_PROGRAM", signer)])
	}

	fn listing(&self) -> Vec<String> {
		let listing = fs::read_to_string(self.path("listing")).expect("the stand-in should have run and written its listing");
		fs::remove_file(self.path("listing")).unwrap();
		listing.lines().filter(|line| !line.is_empty()).map(str::to_string).collect()
	}

	fn left_behind(&self) -> Vec<PathBuf> {
		fn files(directory: &Path, found: &mut Vec<PathBuf>) {
			for entry in fs::read_dir(directory).into_iter().flatten().flatten() {
				if entry.path().is_dir() {
					files(&entry.path(), found);
				} else {
					found.push(entry.path());
				}
			}
		}
		let mut found = Vec::new();
		files(&self.path("temp"), &mut found);
		found
	}
}

fn wide(text: &str) -> Vec<u16> {
	OsStr::new(text).encode_wide().chain([0]).collect()
}

fn is_running(process: u32) -> bool {
	let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process) };
	if handle.is_null() {
		return false;
	}
	let mut status = 0u32;
	let running = unsafe { GetExitCodeProcess(handle, &mut status) } != 0 && status == 259;
	unsafe { CloseHandle(handle) };
	running
}

fn wait_until<T>(limit: Duration, mut check: impl FnMut() -> Option<T>) -> Option<T> {
	let started = Instant::now();
	while started.elapsed() < limit {
		if let Some(value) = check() {
			return Some(value);
		}
		thread::sleep(Duration::from_millis(100));
	}
	None
}

#[test]
fn names_a_push_for_its_commits_repository_branch_and_worktree_then_deletes_the_copy() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	fixture.push(&checkout, &["HEAD"]);
	assert_eq!(fixture.listing(), ["Test App, pushing 1 commit to owner∕repo꞉claude∕feature (elsewhere),.exe"]);
	assert_eq!(fixture.left_behind(), Vec::<PathBuf>::new());
}

#[test]
fn names_the_branch_a_push_goes_to_not_the_checked_out_one() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	fixture.push(&checkout, &["HEAD:main"]);
	assert_eq!(fixture.listing(), ["Test App, pushing 1 commit to owner∕repo꞉main (elsewhere),.exe"]);
}

#[test]
fn names_the_branch_a_bare_push_goes_to_as_git_resolves_it() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("tracking", Some("claude/tracking"));
	fixture.git(&checkout, &["remote", "add", "unresolvable", UNRESOLVABLE]);
	fixture.git(&checkout, &["update-ref", "refs/remotes/unresolvable/main", "HEAD"]);
	fixture.git(&checkout, &["branch", "--quiet", "--set-upstream-to=unresolvable/main"]);
	let ssh_command = fixture.ssh_command();
	fixture.git(&checkout, &["-c", "push.default=upstream", "-c", &ssh_command, "push", "--dry-run"]);
	assert_eq!(fixture.listing(), ["Test App, pushing to owner∕repo꞉main (tracking),.exe"]);
}

#[test]
fn leaves_the_worktree_out_when_the_branch_names_it() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("feature-x", Some("claude/feature-x"));
	fixture.push(&checkout, &["HEAD"]);
	assert_eq!(fixture.listing(), ["Test App, pushing 1 commit to owner∕repo꞉claude∕feature-x,.exe"]);
}

#[test]
fn leaves_the_worktree_out_when_it_is_named_for_the_repository() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("repo", None);
	fixture.push(&checkout, &["HEAD"]);
	assert_eq!(fixture.listing(), ["Test App, pushing 1 commit to owner∕repo꞉main,.exe"]);
}

#[test]
fn names_a_fetch_for_its_repository_and_worktree() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	let ssh_command = fixture.ssh_command();
	fixture.git(&checkout, &["-c", &ssh_command, "ls-remote", UNRESOLVABLE]);
	assert_eq!(fixture.listing(), ["Test App, fetching from owner∕repo (elsewhere),.exe"]);
}

#[test]
fn names_the_application_by_its_description() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("repo", None);
	let ssh_command = fixture.ssh_command();
	fixture.git_from(DESCRIBED_APP, &checkout, &["-c", &ssh_command, "push", "--dry-run", UNRESOLVABLE, "HEAD"]);
	assert_eq!(fixture.listing(), ["op-contextual, pushing 1 commit to owner∕repo꞉main,.exe"]);
}

fn icon_images(executable: &Path) -> Vec<Vec<u8>> {
	fn resource(module: HMODULE, name: u16, kind: u16) -> Vec<u8> {
		let found = unsafe { FindResourceW(module, name as usize as *const u16, kind as usize as *const u16) };
		assert!(!found.is_null(), "resource {name} of type {kind} should exist");
		let size = unsafe { SizeofResource(module, found) } as usize;
		let data = unsafe { LockResource(LoadResource(module, found)) } as *const u8;
		unsafe { std::slice::from_raw_parts(data, size) }.to_vec()
	}
	let path = wide(&executable.to_string_lossy());
	let module = unsafe { LoadLibraryExW(path.as_ptr(), std::ptr::null_mut(), LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE) };
	assert!(!module.is_null(), "{} should load as a resource file", executable.display());
	let group = resource(module, 1, 14);
	let count = u16::from_le_bytes([group[4], group[5]]) as usize;
	let images = (0..count).map(|entry| resource(module, u16::from_le_bytes([group[6 + 14 * entry + 12], group[6 + 14 * entry + 13]]), 3)).collect();
	unsafe { FreeLibrary(module) };
	images
}

fn named_copy_from(fixture: &Fixture, app: &str) -> PathBuf {
	let checkout = fixture.checkout("repo", None);
	let ssh_command = fixture.ssh_command();
	let kept = fixture.path("kept");
	let kept_text = kept.to_string_lossy().into_owned();
	fixture.from_app(app, &checkout, &["git", "-c", &ssh_command, "push", "--dry-run", UNRESOLVABLE, "HEAD"], &[("CONTEXTUAL_KEEP", &kept_text)]);
	let copies: Vec<PathBuf> = fs::read_dir(&kept).expect("the stand-in should have kept the named copy").map(|entry| entry.unwrap().path()).collect();
	assert_eq!(copies.len(), 1, "one named copy should run: {copies:?}");
	copies.into_iter().next().unwrap()
}

#[test]
fn gives_the_named_copy_the_icon_of_the_application() {
	let fixture = Fixture::new();
	let images = icon_images(&named_copy_from(&fixture, ICONIC_APP));
	assert!(images == [ICON_IMAGE.to_vec()], "the copy should carry only the app's image; it carries images of {:?} bytes", images.iter().map(Vec::len).collect::<Vec<_>>());
}

#[test]
fn keeps_its_own_icon_when_the_application_has_none() {
	let fixture = Fixture::new();
	let images = icon_images(&named_copy_from(&fixture, TEST_APP));
	let own = icon_images(&fixture.path("programs").join("ssh.exe"));
	assert!(images == own, "the copy should carry its own {:?}-byte images; it carries {:?}", own.iter().map(Vec::len).collect::<Vec<_>>(), images.iter().map(Vec::len).collect::<Vec<_>>());
}

#[test]
fn gives_git_the_exit_status_of_the_program() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	let status = fixture.command(fixture.program("ssh.exe"), &checkout).args([&fixture.program("lister.exe"), "git@nonexistent.invalid", "git-receive-pack 'owner/repo.git'"]).status().unwrap();
	assert_eq!(status.code(), Some(3));
}

#[test]
fn runs_any_other_ssh_command_unnamed() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	let status = fixture.command(fixture.program("ssh.exe"), &checkout).args([&fixture.program("lister.exe"), "git@nonexistent.invalid", "uptime"]).status().unwrap();
	assert_eq!(status.code(), Some(3));
	assert_eq!(fixture.listing(), Vec::<String>::new());
}

#[test]
fn names_a_commit_signature_for_its_subject_repository_branch_and_worktree() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	fixture.sign(&checkout, &fixture.program("lister.exe"), &["commit", "--quiet", "--gpg-sign", "--allow-empty", "--message", "feat(git): sign it"]);
	assert_eq!(fixture.listing(), ["Test App, signing “feat(git)꞉ sign it” in owner∕repo꞉claude∕feature (elsewhere),.exe"]);
	assert_eq!(fixture.left_behind(), Vec::<PathBuf>::new());
}

#[test]
fn names_a_tag_signature_without_a_branch() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("feature-x", Some("claude/feature-x"));
	fixture.sign(&checkout, &fixture.program("lister.exe"), &["tag", "--sign", "--message", "release it", "v1"]);
	assert_eq!(fixture.listing(), ["Test App, signing tag v1 “release it” in owner∕repo (feature-x),.exe"]);
}

#[test]
fn names_a_signature_without_origin_by_the_repository_folder() {
	let fixture = Fixture::new();
	fixture.git(fixture.root.path(), &["init", "--quiet", "local-only"]);
	fixture.sign(&fixture.path("local-only"), &fixture.program("lister.exe"), &["commit", "--quiet", "--gpg-sign", "--allow-empty", "--message", "feat(git): sign it"]);
	assert_eq!(fixture.listing(), ["Test App, signing “feat(git)꞉ sign it” in local-only꞉main,.exe"]);
}

#[test]
fn hands_git_the_signature_of_a_signer_that_exits_at_once() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("repo", None);
	for attempt in 1..=5 {
		let message = format!("feat(git): sign it {attempt}");
		let status = fixture.sign(&checkout, SSH_KEYGEN, &["commit", "--quiet", "--gpg-sign", "--allow-empty", "--message", &message]);
		assert_eq!(status, 0, "attempt {attempt} should sign");
	}
	for commit in 0..5 {
		let object = Command::new("git").current_dir(&checkout).args(["cat-file", "commit", &format!("HEAD~{commit}")]).output().unwrap();
		let text = String::from_utf8_lossy(&object.stdout);
		assert!(text.lines().any(|line| line == "gpgsig -----BEGIN SSH SIGNATURE-----"), "commit HEAD~{commit} should carry a signature");
	}
	assert_eq!(fixture.left_behind(), Vec::<PathBuf>::new());
}

#[test]
fn passes_other_signer_commands_to_the_signer_on_path_not_to_itself() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("repo", None);
	fs::create_dir(fixture.path("on-path")).unwrap();
	fs::copy(fixture.path("programs").join("lister.exe"), fixture.path("on-path").join("op-ssh-sign.exe")).unwrap();
	let path = env::join_paths([fixture.path("on-path")].into_iter().chain(env::split_paths(&env::var_os("PATH").unwrap()))).unwrap();
	let mut signer = fixture.command(fixture.program("op-ssh-sign.exe"), &checkout).env("PATH", path).args(["-Y", "check-novalidate", "-n", "git", "-s", "signature"]).spawn().unwrap();
	let status = wait_until(Duration::from_secs(20), || signer.try_wait().unwrap());
	if status.is_none() {
		fs::rename(fixture.path("programs").join("op-ssh-sign.exe"), fixture.path("programs").join("op-ssh-sign.stopped")).unwrap();
		signer.wait().unwrap();
	}
	assert_eq!(status.and_then(|status| status.code()), Some(3), "op-ssh-sign.exe should run the signer on PATH once, not itself over and over");
	assert_eq!(fixture.listing(), Vec::<String>::new());
}

#[test]
fn stops_the_named_program_when_it_is_stopped_itself() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	let started = fixture.path("started");
	let mut launcher = fixture
		.command(fixture.program("ssh.exe"), &checkout)
		.args([&fixture.program("lister.exe"), "git@nonexistent.invalid", "git-receive-pack 'owner/repo.git'"])
		.env("CONTEXTUAL_LINGER", "60")
		.env("CONTEXTUAL_STARTED", &started)
		.spawn()
		.unwrap();
	let program = wait_until(Duration::from_secs(15), || fs::read_to_string(&started).ok().and_then(|text| text.trim().parse::<u32>().ok())).expect("the named program should start");
	launcher.kill().unwrap();
	launcher.wait().unwrap();
	assert!(wait_until(Duration::from_secs(5), || (!is_running(program)).then_some(())).is_some(), "the named program should stop with the launcher");
}

#[test]
fn clears_copies_left_by_a_stopped_run() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout("elsewhere", Some("claude/feature"));
	let mut stopped = Command::new("cmd").args(["/d", "/c", "exit"]).spawn().unwrap();
	let stopped_id = stopped.id();
	stopped.wait().unwrap();
	let stale = fixture.path("temp").join("1p-contextual").join(stopped_id.to_string());
	fs::create_dir_all(&stale).unwrap();
	fs::write(stale.join("a stale copy.exe"), "").unwrap();
	fixture.push(&checkout, &["HEAD"]);
	fixture.listing();
	assert!(!stale.exists(), "the copy from the stopped run should be gone");
}

#[test]
fn carries_an_icon() {
	let fixture = Fixture::new();
	for program in ["ssh.exe", "op-ssh-sign.exe"] {
		let path = wide(&fixture.program(program));
		let module = unsafe { LoadLibraryExW(path.as_ptr(), std::ptr::null_mut(), LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE) };
		assert!(!module.is_null(), "{program} should load as a resource file");
		let icon = unsafe { FindResourceW(module, 1 as *const u16, 14 as *const u16) };
		unsafe { FreeLibrary(module) };
		assert!(!icon.is_null(), "{program} should carry an icon");
	}
}
