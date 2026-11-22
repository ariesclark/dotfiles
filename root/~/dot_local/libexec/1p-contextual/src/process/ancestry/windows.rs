use std::collections::HashMap;
use std::ffi::{c_void, OsStr, OsString};
use std::os::windows::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::{mem, process, ptr, slice};

use windows_sys::Wdk::System::Threading::{NtQueryInformationProcess, ProcessCommandLineInformation};
use windows_sys::Win32::Foundation::{CloseHandle, LocalFree, FALSE, FILETIME, HANDLE, INVALID_HANDLE_VALUE, UNICODE_STRING};
use windows_sys::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS};
use windows_sys::Win32::System::SystemInformation::GetSystemWindowsDirectoryW;
use windows_sys::Win32::System::Threading::{GetProcessTimes, OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
use windows_sys::Win32::UI::Shell::CommandLineToArgvW;

const APPLICATION_SEARCH_DEPTH: usize = 32;

struct OwnedHandle(HANDLE);

impl Drop for OwnedHandle {
	fn drop(&mut self) {
		unsafe { CloseHandle(self.0) };
	}
}

fn parents() -> HashMap<u32, u32> {
	let mut parents = HashMap::new();
	let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
	if snapshot == INVALID_HANDLE_VALUE {
		return parents;
	}
	let snapshot = OwnedHandle(snapshot);
	let mut entry: PROCESSENTRY32W = unsafe { mem::zeroed() };
	entry.dwSize = mem::size_of::<PROCESSENTRY32W>() as u32;
	let mut found = unsafe { Process32FirstW(snapshot.0, &mut entry) };
	while found != 0 {
		parents.insert(entry.th32ProcessID, entry.th32ParentProcessID);
		found = unsafe { Process32NextW(snapshot.0, &mut entry) };
	}
	parents
}

fn opened(process: u32) -> Option<OwnedHandle> {
	let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process) };
	(!handle.is_null()).then_some(OwnedHandle(handle))
}

fn started_at(process: u32) -> Option<u64> {
	let handle = opened(process)?;
	let [mut creation, mut exit, mut kernel, mut user]: [FILETIME; 4] = unsafe { mem::zeroed() };
	if unsafe { GetProcessTimes(handle.0, &mut creation, &mut exit, &mut kernel, &mut user) } == 0 {
		return None;
	}
	Some((u64::from(creation.dwHighDateTime) << 32) | u64::from(creation.dwLowDateTime))
}

pub fn ancestors(depth: usize) -> Vec<u32> {
	let parents = parents();
	let mut ancestors = Vec::new();
	let mut process = process::id();
	let Some(mut started) = started_at(process) else { return ancestors };
	while ancestors.len() < depth {
		let Some(&parent) = parents.get(&process).filter(|&&parent| parent != 0) else { break };
		let Some(parent_started) = started_at(parent).filter(|&parent_started| parent_started <= started) else { break };
		ancestors.push(parent);
		process = parent;
		started = parent_started;
	}
	ancestors
}

fn executable_of(process: u32) -> Option<PathBuf> {
	let handle = opened(process)?;
	let mut buffer = vec![0u16; 32_768];
	let mut length = buffer.len() as u32;
	if unsafe { QueryFullProcessImageNameW(handle.0, PROCESS_NAME_WIN32, buffer.as_mut_ptr(), &mut length) } == 0 {
		return None;
	}
	Some(PathBuf::from(OsString::from_wide(&buffer[..length as usize])))
}

fn windows_folder() -> Option<PathBuf> {
	let mut buffer = vec![0u16; 32_768];
	let length = unsafe { GetSystemWindowsDirectoryW(buffer.as_mut_ptr(), buffer.len() as u32) } as usize;
	(length > 0 && length < buffer.len()).then(|| PathBuf::from(OsString::from_wide(&buffer[..length])))
}

fn is_inside(path: &Path, folder: &Path) -> bool {
	Path::new(&path.to_string_lossy().to_lowercase()).starts_with(folder.to_string_lossy().to_lowercase())
}

fn topmost_outside<'chain>(executables: &'chain [PathBuf], folder: &Path) -> Option<&'chain PathBuf> {
	executables.iter().rev().find(|executable| !is_inside(executable, folder))
}

fn wide(text: &OsStr) -> Vec<u16> {
	text.encode_wide().chain([0]).collect()
}

fn version_value(data: &[u8], key: &str) -> Option<(*const c_void, usize)> {
	let mut value: *mut c_void = ptr::null_mut();
	let mut length = 0u32;
	let found = unsafe { VerQueryValueW(data.as_ptr() as *const c_void, wide(OsStr::new(key)).as_ptr(), &mut value, &mut length) };
	(found != 0 && !value.is_null() && length > 0).then_some((value as *const c_void, length as usize))
}

fn version_text(data: &[u8], key: &str) -> Option<String> {
	let (value, characters) = version_value(data, key)?;
	let text = String::from_utf16_lossy(unsafe { slice::from_raw_parts(value as *const u16, characters) });
	let text = text.trim_end_matches('\0').trim();
	(!text.is_empty()).then(|| text.to_string())
}

fn version_name(executable: &Path) -> Option<String> {
	let path = wide(executable.as_os_str());
	let size = unsafe { GetFileVersionInfoSizeW(path.as_ptr(), ptr::null_mut()) };
	if size == 0 {
		return None;
	}
	let mut data = vec![0u8; size as usize];
	if unsafe { GetFileVersionInfoW(path.as_ptr(), 0, size, data.as_mut_ptr() as *mut c_void) } == 0 {
		return None;
	}
	let (translation, _) = version_value(&data, r"\VarFileInfo\Translation").filter(|&(_, bytes)| bytes >= 4)?;
	let [language, code_page] = unsafe { ptr::read_unaligned(translation as *const [u16; 2]) };
	["FileDescription", "ProductName"].into_iter().find_map(|field| version_text(&data, &format!(r"\StringFileInfo\{language:04x}{code_page:04x}\{field}")))
}

fn name_of(executable: &Path) -> String {
	version_name(executable).unwrap_or_else(|| executable.file_stem().unwrap_or(executable.as_os_str()).to_string_lossy().into_owned())
}

pub struct Application {
	pub name: String,
	pub executable: PathBuf,
}

pub fn application() -> Option<Application> {
	let folder = windows_folder()?;
	let executables: Vec<PathBuf> = ancestors(APPLICATION_SEARCH_DEPTH).into_iter().map_while(executable_of).collect();
	topmost_outside(&executables, &folder).map(|executable| Application { name: name_of(executable), executable: executable.clone() })
}

pub fn arguments_of(process: u32) -> Option<Vec<String>> {
	let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process) };
	if handle.is_null() {
		return None;
	}
	let handle = OwnedHandle(handle);
	let mut size = 0u32;
	unsafe { NtQueryInformationProcess(handle.0, ProcessCommandLineInformation, ptr::null_mut(), 0, &mut size) };
	if size == 0 {
		return None;
	}
	let mut buffer = vec![0u64; (size as usize).div_ceil(8)];
	let status = unsafe { NtQueryInformationProcess(handle.0, ProcessCommandLineInformation, buffer.as_mut_ptr() as *mut c_void, size, &mut size) };
	if status < 0 {
		return None;
	}
	let command_line = unsafe { &*(buffer.as_ptr() as *const UNICODE_STRING) };
	if command_line.Buffer.is_null() {
		return None;
	}
	let mut units = unsafe { slice::from_raw_parts(command_line.Buffer, command_line.Length as usize / 2) }.to_vec();
	units.push(0);
	let mut count = 0;
	let arguments = unsafe { CommandLineToArgvW(units.as_ptr(), &mut count) };
	if arguments.is_null() {
		return None;
	}
	let parsed = (0..count as usize)
		.map(|index| {
			let argument = unsafe { *arguments.add(index) };
			let length = (0..).take_while(|&offset| unsafe { *argument.add(offset) } != 0).count();
			String::from_utf16_lossy(unsafe { slice::from_raw_parts(argument, length) })
		})
		.collect();
	unsafe { LocalFree(arguments as *mut c_void) };
	Some(parsed)
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::env;
	use std::fs;

	#[test]
	fn picks_the_topmost_executable_outside_the_windows_folder() {
		let chain: Vec<PathBuf> = [
			r"C:\Users\aries\.local\libexec\1p-contextual\ssh.exe",
			r"C:\Program Files\Git\mingw64\bin\git.exe",
			r"C:\WINDOWS\System32\cmd.exe",
			r"C:\Program Files\WindowsApps\Claude_6.28899.6.0_x64__pzs8sxrjxfjjc\app\claude.exe",
			r"C:\Windows\system32\sihost.exe",
		]
		.map(PathBuf::from)
		.to_vec();
		assert_eq!(topmost_outside(&chain, Path::new(r"C:\Windows")), Some(&chain[3]));
	}

	#[test]
	fn picks_nothing_when_every_executable_is_in_the_windows_folder() {
		let chain: Vec<PathBuf> = [r"C:\Windows\System32\cmd.exe", r"C:\WINDOWS\explorer.exe"].map(PathBuf::from).to_vec();
		assert_eq!(topmost_outside(&chain, Path::new(r"C:\Windows")), None);
		assert_eq!(topmost_outside(&[], Path::new(r"C:\Windows")), None);
	}

	#[test]
	fn treats_a_folder_that_only_starts_like_the_windows_folder_as_outside_it() {
		let chain = vec![PathBuf::from(r"C:\Windows.old\app.exe")];
		assert_eq!(topmost_outside(&chain, Path::new(r"C:\Windows")), Some(&chain[0]));
	}

	#[test]
	fn names_an_executable_by_its_description() {
		assert_eq!(name_of(&env::current_exe().unwrap()), "op-contextual");
	}

	#[test]
	fn names_an_executable_without_version_information_by_its_file_name() {
		let directory = tempfile::tempdir().unwrap();
		let executable = directory.path().join("Some App.exe");
		fs::write(&executable, "not a program").unwrap();
		assert_eq!(name_of(&executable), "Some App");
	}
}
