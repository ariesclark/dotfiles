use std::env;
use std::fs;
use std::process::{self, Command};

#[cfg(windows)]
fn replace_resources(executable: &str, icon: Option<&str>) {
	use std::os::windows::ffi::OsStrExt;
	use windows_sys::Win32::Foundation::FALSE;
	use windows_sys::Win32::System::LibraryLoader::{BeginUpdateResourceW, EndUpdateResourceW, UpdateResourceW};
	let path: Vec<u16> = std::ffi::OsStr::new(executable).encode_wide().chain([0]).collect();
	let update = unsafe { BeginUpdateResourceW(path.as_ptr(), 1) };
	assert!(!update.is_null(), "{executable} should open for a resource update");
	if let Some(icon) = icon {
		let image = fs::read(icon).expect("the icon image should be readable");
		let mut group = vec![0u8, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 32, 0];
		group.extend((image.len() as u32).to_le_bytes());
		group.extend(1u16.to_le_bytes());
		for (kind, data) in [(3usize, &image), (14, &group)] {
			let written = unsafe { UpdateResourceW(update, kind as *const u16, 1 as *const u16, 0, data.as_ptr() as *const _, data.len() as u32) };
			assert!(written != 0, "{executable} should take the icon");
		}
	}
	assert!(unsafe { EndUpdateResourceW(update, FALSE) } != 0, "{executable} should keep its new resources");
}

#[cfg(not(windows))]
fn replace_resources(_executable: &str, _icon: Option<&str>) {
	unimplemented!("only the Windows build changes resources");
}

fn main() {
	let arguments: Vec<String> = env::args().skip(1).collect();
	match arguments.split_first() {
		Some((mode, [executable])) if mode == "--strip-resources" => replace_resources(executable, None),
		Some((mode, [executable, icon])) if mode == "--give-icon" => replace_resources(executable, Some(icon)),
		Some((mode, rest)) if mode == "--detach" => {
			Command::new(env::current_exe().expect("its own path")).arg("--run").args(rest).spawn().expect("the detached run should start");
		}
		Some((mode, [status, program, command @ ..])) if mode == "--run" => {
			let code = Command::new(program).args(command).status().map_or(255, |status| status.code().unwrap_or(255));
			let partial = format!("{status}.partial");
			fs::write(&partial, code.to_string()).expect("the status should be writable");
			fs::rename(partial, status).expect("the status should move into place");
		}
		_ => process::exit(2),
	}
}
