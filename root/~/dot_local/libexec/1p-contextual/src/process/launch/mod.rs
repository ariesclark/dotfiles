#[cfg(any(windows, test))]
mod command_line;
#[cfg(any(windows, test))]
mod icon;
#[cfg(windows)]
mod windows;
#[cfg(unix)]
mod wsl;

#[cfg(windows)]
use windows as platform;
#[cfg(unix)]
use wsl as platform;

use std::env;
use std::ffi::OsString;

pub use platform::{pass_through, run_named, signer_arguments, SIGNER};

const SUPERVISE: &str = "--1p-contextual-supervise";
const RUN_NAMED: &str = "--1p-contextual-run-named";
const STAND_IN: &str = "--1p-contextual-stand-in";

pub fn arguments() -> Vec<OsString> {
	let arguments: Vec<OsString> = env::args_os().skip(1).collect();
	match arguments.first().and_then(|argument| argument.to_str()) {
		Some(SUPERVISE) => platform::supervise(&arguments[1..]),
		Some(RUN_NAMED) => platform::run_named_from_wsl(&arguments[1..]),
		Some(STAND_IN) => std::process::exit(0),
		_ => arguments,
	}
}
