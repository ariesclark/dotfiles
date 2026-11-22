use std::collections::HashMap;
use std::ffi::c_void;
use std::{mem, process, ptr, slice};

use windows_sys::Wdk::System::Threading::{NtQueryInformationProcess, ProcessCommandLineInformation};
use windows_sys::Win32::Foundation::{CloseHandle, LocalFree, FALSE, HANDLE, INVALID_HANDLE_VALUE, UNICODE_STRING};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS};
use windows_sys::Win32::System::Threading::{OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION};
use windows_sys::Win32::UI::Shell::CommandLineToArgvW;

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

pub fn ancestors(depth: usize) -> Vec<u32> {
	let parents = parents();
	let mut ancestors = Vec::new();
	let mut process = process::id();
	while ancestors.len() < depth {
		match parents.get(&process) {
			Some(&parent) if parent != 0 => {
				ancestors.push(parent);
				process = parent;
			}
			_ => break,
		}
	}
	ancestors
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
