#![cfg(unix)]

use std::ffi::OsStr;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use std::{env, fs, thread};

const UNRESOLVABLE: &str = "ssh://git@nonexistent.invalid/owner/repo.git";
const TEST_APP: &str = "Test App.exe";

struct Fixture {
	linux: tempfile::TempDir,
	windows: tempfile::TempDir,
}

fn output(command: &mut Command) -> String {
	let output = command.stderr(Stdio::null()).output().expect("the command should run");
	assert!(output.status.success());
	String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn windows_path(path: &Path) -> String {
	output(Command::new("wslpath").arg("-w").arg(path))
}

fn windows_temp() -> PathBuf {
	let temp = output(Command::new("cmd.exe").args(["/d", "/c", "echo %TEMP%"]).current_dir("/mnt/c"));
	PathBuf::from(output(Command::new("wslpath").arg("-u").arg(temp)))
}

impl Fixture {
	fn new() -> Self {
		let target = env::current_exe().expect("the test's own path").ancestors().nth(3).expect("the target directory").to_path_buf();
		let windows_build = target.join("x86_64-pc-windows-gnu").join("debug");
		assert!(windows_build.join("ssh.exe").exists(), "build the Windows programs first: cargo test --target x86_64-pc-windows-gnu");
		let linux = tempfile::tempdir().expect("a Linux temporary directory");
		let windows = tempfile::tempdir_in(windows_temp()).expect("a Windows temporary directory");
		fs::create_dir(windows.path().join("temp")).unwrap();
		fs::copy(windows_build.join("ssh.exe"), windows.path().join("ssh.exe")).unwrap();
		fs::copy(windows_build.join("examples").join("lister.exe"), windows.path().join("lister.exe")).unwrap();
		for app in [TEST_APP, "Described App.exe"] {
			fs::copy(windows_build.join("examples").join("app.exe"), windows.path().join(app)).unwrap();
		}
		let stripped = Command::new(windows.path().join("Described App.exe")).arg("--strip-resources").arg(windows_path(&windows.path().join(TEST_APP))).current_dir(windows.path()).status();
		assert!(stripped.expect("the app should run").success(), "{TEST_APP} should lose its version information");
		fs::copy(env!("CARGO_BIN_EXE_ssh"), linux.path().join("ssh")).unwrap();
		fs::copy(env!("CARGO_BIN_EXE_op-ssh-sign"), linux.path().join("op-ssh-sign")).unwrap();
		symlink(windows.path().join("ssh.exe"), linux.path().join("1p-contextual.exe")).unwrap();
		Fixture { linux, windows }
	}

	fn lister(&self) -> String {
		windows_path(&self.windows.path().join("lister.exe")).replace('\\', "/")
	}

	fn wsl(&self, directory: &Path) -> Vec<String> {
		let distribution = env::var("WSL_DISTRO_NAME").expect("the tests should run in WSL");
		let windows = |name: &str| self.windows.path().join(name).display().to_string();
		let mut command = ["wsl.exe", "--distribution", &distribution, "--cd", &directory.display().to_string()].map(str::to_string).to_vec();
		command.extend(["--exec", "env", "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_NOSYSTEM=1"].map(str::to_string));
		command.extend([format!("TEMP={}", windows("temp")), format!("TMP={}", windows("temp"))]);
		command.extend([format!("CONTEXTUAL_LISTING={}", windows("listing")), format!("CONTEXTUAL_ARGUMENTS={}", windows("arguments"))]);
		command.extend(["WSLENV=TEMP/p:TMP/p:CONTEXTUAL_LISTING/p:CONTEXTUAL_ARGUMENTS/p".to_string(), format!("OP_SSH_SIGN_CONTEXTUAL_PROGRAM={}", self.lister())]);
		command
	}

	fn git_command(arguments: &[impl AsRef<OsStr>]) -> Vec<String> {
		let mut command = ["git", "-c", "init.defaultBranch=main", "-c", "user.name=Stub", "-c", "user.email=stub@example.com", "-c", "commit.gpgsign=false"].map(str::to_string).to_vec();
		command.extend(arguments.iter().map(|argument| argument.as_ref().to_string_lossy().into_owned()));
		command
	}

	fn from_app(&self, mode: &str, command: &[String], status: &Path) -> i32 {
		let started = Command::new(self.windows.path().join(TEST_APP))
			.current_dir(self.windows.path())
			.arg(mode)
			.args(command)
			.stdin(Stdio::null())
			.stdout(Stdio::null())
			.stderr(Stdio::null())
			.status();
		assert!(started.expect("the app should run").success());
		let started = Instant::now();
		let code = loop {
			if let Ok(code) = fs::read_to_string(status) {
				break code;
			}
			assert!(started.elapsed() < Duration::from_secs(60), "git should finish");
			thread::sleep(Duration::from_millis(100));
		};
		fs::remove_file(status).unwrap();
		code.trim().parse().expect("an exit code should be recorded")
	}

	fn git(&self, directory: &Path, arguments: &[impl AsRef<OsStr>]) -> i32 {
		let mut command = vec![windows_path(self.windows.path()) + "\\status"];
		command.extend(self.wsl(directory));
		command.extend(Self::git_command(arguments));
		self.from_app("--detach", &command, &self.windows.path().join("status"))
	}

	fn git_without_a_windows_application(&self, directory: &Path, arguments: &[impl AsRef<OsStr>]) -> i32 {
		let status = self.linux.path().join("status");
		let mut command = self.wsl(directory);
		command.extend(["sh", "-c", r#""$@"; echo $? > "$0.partial" && mv "$0.partial" "$0""#].map(str::to_string));
		command.push(status.display().to_string());
		command.extend(Self::git_command(arguments));
		self.from_app("--orphan", &command, &status)
	}

	fn checkout(&self) -> PathBuf {
		self.git(self.linux.path(), &["init", "--quiet", "wsl-check"]);
		let checkout = self.linux.path().join("wsl-check");
		self.git(&checkout, &["commit", "--quiet", "--allow-empty", "--message", "scratch"]);
		self.git(&checkout, &["remote", "add", "origin", "https://github.com/owner/repo.git"]);
		checkout
	}

	fn read(&self, name: &str) -> Vec<String> {
		let text = fs::read_to_string(self.windows.path().join(name)).unwrap_or_else(|error| panic!("the stand-in should have written {name}: {error}"));
		fs::remove_file(self.windows.path().join(name)).unwrap();
		text.lines().filter(|line| !line.is_empty()).map(str::to_string).collect()
	}
}

#[test]
fn names_a_push_from_wsl_through_the_windows_build() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout();
	let ssh_command = format!("core.sshCommand={} {}", fixture.linux.path().join("ssh").display(), fixture.lister());
	fixture.git(&checkout, &["-c", &ssh_command, "push", "--dry-run", UNRESOLVABLE, "HEAD:main"]);
	assert_eq!(fixture.read("listing"), ["Test App, pushing 1 commit to owner∕repo꞉main (wsl-check),.exe"]);
}

#[test]
fn names_git_not_wsl_when_no_windows_application_runs_wsl() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout();
	let ssh_command = format!("core.sshCommand={} {}", fixture.linux.path().join("ssh").display(), fixture.lister());
	fixture.git_without_a_windows_application(&checkout, &["-c", &ssh_command, "push", "--dry-run", UNRESOLVABLE, "HEAD:main"]);
	assert_eq!(fixture.read("listing"), ["git, pushing 1 commit to owner∕repo꞉main (wsl-check),.exe"]);
}

#[test]
fn names_a_signature_from_wsl_and_hands_the_signer_windows_paths() {
	let fixture = Fixture::new();
	let checkout = fixture.checkout();
	let key = fixture.linux.path().join("signing-key");
	assert!(Command::new("ssh-keygen").args(["-q", "-t", "ed25519", "-N", "", "-C", "", "-f"]).arg(&key).status().unwrap().success());
	let program = format!("gpg.ssh.program={}", fixture.linux.path().join("op-ssh-sign").display());
	let signing_key = format!("user.signingkey={}", key.display());
	fixture.git(&checkout, &["-c", "gpg.format=ssh", "-c", &program, "-c", &signing_key, "commit", "--quiet", "--gpg-sign", "--allow-empty", "--message", "feat(git): from WSL"]);
	assert_eq!(fixture.read("listing"), ["Test App, signing “feat(git)꞉ from WSL” in owner∕repo꞉main (wsl-check),.exe"]);
	let arguments = fixture.read("arguments");
	assert_eq!(arguments[..6], ["-Y", "sign", "-n", "git", "-f", &windows_path(&key)]);
	assert_eq!(arguments.len(), 7);
	assert!(arguments[6].starts_with(r"\\wsl.localhost\") || arguments[6].starts_with(r"\\wsl$\"), "the buffer should be a Windows path: {}", arguments[6]);
}
