use std::env;
use std::ffi::{OsStr, OsString};
use std::os::unix::process::CommandExt;
use std::process::{self, Command, Stdio};

pub const SIGNER: &str = "op-ssh-sign-wsl.exe";

pub fn pass_through(program: &OsStr, arguments: &[OsString]) -> ! {
	let error = Command::new(program).args(arguments).exec();
	eprintln!("1p-contextual: could not start {}: {error}", program.to_string_lossy());
	process::exit(255);
}

fn windows_path(path: &OsStr) -> OsString {
	match Command::new("wslpath").arg("-w").arg(path).stderr(Stdio::null()).output() {
		Ok(output) if output.status.success() => OsString::from(String::from_utf8_lossy(&output.stdout).trim_end()),
		_ => path.to_os_string(),
	}
}

pub fn signer_arguments(arguments: &[OsString]) -> Vec<OsString> {
	let last = arguments.len().saturating_sub(1);
	arguments
		.iter()
		.enumerate()
		.map(|(index, argument)| {
			let follows_key_flag = index > 0 && arguments[index - 1] == "-f";
			if follows_key_flag || index == last { windows_path(argument) } else { argument.clone() }
		})
		.collect()
}

pub fn run_named(label: &str, program: &OsStr, arguments: &[OsString]) -> ! {
	let windows_build = env::current_exe().ok().and_then(|path| path.parent().map(|directory| directory.join("1p-contextual.exe")));
	if let Some(windows_build) = windows_build {
		let error = Command::new(&windows_build).arg(super::RUN_NAMED).arg(label).arg(program).args(arguments).exec();
		eprintln!("1p-contextual: could not start {}: {error}; running {} without a name", windows_build.display(), program.to_string_lossy());
	}
	pass_through(program, arguments)
}

pub fn supervise(_arguments: &[OsString]) -> ! {
	eprintln!("1p-contextual: only the Windows build supervises");
	process::exit(2);
}

pub fn run_named_from_wsl(_arguments: &[OsString]) -> ! {
	eprintln!("1p-contextual: only the Windows build runs a named copy");
	process::exit(2);
}
