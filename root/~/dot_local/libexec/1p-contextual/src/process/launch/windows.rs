use std::env;
use std::ffi::{c_void, OsStr, OsString};
use std::fs;
use std::io::{self, Read, Write};
use std::mem;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::AsRawHandle;
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use std::ptr;
use std::thread;
use std::time::Duration;

use windows_sys::Win32::Foundation::{CloseHandle, DuplicateHandle, DUPLICATE_SAME_ACCESS, FALSE, HANDLE, INVALID_HANDLE_VALUE, TRUE};
use windows_sys::Win32::System::Console::{GetStdHandle, STD_ERROR_HANDLE, STD_INPUT_HANDLE, STD_OUTPUT_HANDLE};
use windows_sys::Win32::System::JobObjects::{
	AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation, SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
	JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows_sys::Win32::System::Threading::{
	CreateProcessW, DeleteProcThreadAttributeList, GetCurrentProcess, GetExitCodeProcess, InitializeProcThreadAttributeList, OpenProcess, ResumeThread,
	TerminateProcess, UpdateProcThreadAttribute, WaitForSingleObject, CREATE_NO_WINDOW, CREATE_SUSPENDED, EXTENDED_STARTUPINFO_PRESENT, INFINITE,
	LPPROC_THREAD_ATTRIBUTE_LIST, PROCESS_INFORMATION, PROCESS_QUERY_LIMITED_INFORMATION, PROC_THREAD_ATTRIBUTE_PARENT_PROCESS, STARTF_USESTDHANDLES,
	STARTUPINFOEXW, STARTUPINFOW,
};

use super::command_line;

pub const SIGNER: &str = "op-ssh-sign.exe";
const STILL_ACTIVE: u32 = 259;

enum Streams {
	Own,
	Relayed,
}

struct OwnedHandle(HANDLE);

impl Drop for OwnedHandle {
	fn drop(&mut self) {
		unsafe { CloseHandle(self.0) };
	}
}

struct StandIn {
	process: OwnedHandle,
	_thread: OwnedHandle,
}

impl Drop for StandIn {
	fn drop(&mut self) {
		unsafe { TerminateProcess(self.process.0, 0) };
	}
}

struct AttributeList {
	_buffer: Vec<u8>,
	list: LPPROC_THREAD_ATTRIBUTE_LIST,
}

impl Drop for AttributeList {
	fn drop(&mut self) {
		unsafe { DeleteProcThreadAttributeList(self.list) };
	}
}

struct Supervisor {
	process: OwnedHandle,
	_job: OwnedHandle,
}

fn on_path(program: &OsStr) -> PathBuf {
	let named = Path::new(program);
	if named.components().count() > 1 {
		return named.to_path_buf();
	}
	let mut with_extension = program.to_os_string();
	with_extension.push(".exe");
	let names = if named.extension().is_some() { vec![program.to_os_string()] } else { vec![program.to_os_string(), with_extension] };
	let directories = env::var_os("PATH").map(|path| env::split_paths(&path).collect::<Vec<_>>()).unwrap_or_default();
	directories.iter().flat_map(|directory| names.iter().map(move |name| directory.join(name))).find(|candidate| candidate.is_file()).unwrap_or_else(|| named.to_path_buf())
}

pub fn pass_through(program: &OsStr, arguments: &[OsString]) -> ! {
	match Command::new(on_path(program)).args(arguments).status() {
		Ok(status) => process::exit(status.code().unwrap_or(255)),
		Err(error) => {
			eprintln!("1p-contextual: could not start {}: {error}", program.to_string_lossy());
			process::exit(255);
		}
	}
}

pub fn signer_arguments(arguments: &[OsString]) -> Vec<OsString> {
	arguments.to_vec()
}

pub fn supervise(arguments: &[OsString]) -> ! {
	let Some((program, rest)) = arguments.split_first() else {
		process::exit(2);
	};
	pass_through(program, rest)
}

pub fn run_named(label: &str, program: &OsStr, arguments: &[OsString]) -> ! {
	run(label, program, arguments, Streams::Own)
}

pub fn run_named_from_wsl(arguments: &[OsString]) -> ! {
	let [label, program, rest @ ..] = arguments else {
		eprintln!("1p-contextual: a named run needs a label and a program");
		process::exit(2);
	};
	run(&label.to_string_lossy(), program, rest, Streams::Relayed)
}

fn run(label: &str, program: &OsStr, arguments: &[OsString], streams: Streams) -> ! {
	let application = crate::process::ancestry::application();
	let label = crate::label::with_application(application.as_ref().map(|application| application.name.as_str()), label);
	let icon_source = application.as_ref().map(|application| application.executable.as_path());
	match start_named(&label, icon_source, program, arguments, streams) {
		Ok(status) => process::exit(status),
		Err(error) => {
			eprintln!("1p-contextual: {error}; running {} without a name", program.to_string_lossy());
			pass_through(program, arguments)
		}
	}
}

fn last_error(action: &str) -> io::Error {
	let error = io::Error::last_os_error();
	io::Error::new(error.kind(), format!("{action}: {error}"))
}

fn wide(text: &OsStr) -> Vec<u16> {
	text.encode_wide().collect()
}

fn copies() -> PathBuf {
	env::temp_dir().join("1p-contextual")
}

fn is_running(process: u32) -> bool {
	let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process) };
	if handle.is_null() {
		return false;
	}
	let handle = OwnedHandle(handle);
	let mut status = 0u32;
	unsafe { GetExitCodeProcess(handle.0, &mut status) != 0 && status == STILL_ACTIVE }
}

fn sweep_stopped_runs() {
	let Ok(entries) = fs::read_dir(copies()) else { return };
	for entry in entries.flatten() {
		let owner = entry.file_name().to_str().and_then(|name| name.parse::<u32>().ok());
		if let Some(owner) = owner.filter(|&owner| owner != process::id() && !is_running(owner)) {
			let _ = fs::remove_dir_all(copies().join(owner.to_string()));
		}
	}
}

fn remove_when_released(directory: &Path) {
	for _ in 0..20 {
		if fs::remove_dir_all(directory).is_ok() || !directory.exists() {
			return;
		}
		thread::sleep(Duration::from_millis(50));
	}
}

fn named_copy(copy: &Path, icon_source: Option<&Path>) -> io::Result<()> {
	fs::copy(env::current_exe()?, copy)?;
	if let Some(icon_source) = icon_source {
		let _keeps_its_own_icon = super::icon::borrow(icon_source, copy);
	}
	Ok(())
}

fn start_named(label: &str, icon_source: Option<&Path>, program: &OsStr, arguments: &[OsString], streams: Streams) -> io::Result<i32> {
	sweep_stopped_runs();
	let directory = copies().join(process::id().to_string());
	fs::create_dir_all(&directory)?;
	let copy = directory.join(format!("{label}.exe"));
	let result = named_copy(&copy, icon_source).and_then(|_| match streams {
		Streams::Own => run_with_own_streams(&copy, program, arguments),
		Streams::Relayed => run_with_relayed_streams(&copy, program, arguments),
	});
	remove_when_released(&directory);
	result
}

fn run_with_own_streams(copy: &Path, program: &OsStr, arguments: &[OsString]) -> io::Result<i32> {
	let streams = [STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE].map(|which| unsafe { GetStdHandle(which) });
	wait_for(&start_copy(copy, program, arguments, streams, 0)?)
}

fn relay(mut from: impl Read, mut to: impl Write) {
	let mut buffer = [0u8; 64 * 1024];
	while let Ok(read) = from.read(&mut buffer) {
		if read == 0 || to.write_all(&buffer[..read]).and_then(|_| to.flush()).is_err() {
			break;
		}
	}
}

fn run_with_relayed_streams(copy: &Path, program: &OsStr, arguments: &[OsString]) -> io::Result<i32> {
	let (input_reader, mut input_writer) = io::pipe()?;
	let (output_reader, output_writer) = io::pipe()?;
	let (error_reader, error_writer) = io::pipe()?;
	let streams = [input_reader.as_raw_handle(), output_writer.as_raw_handle(), error_writer.as_raw_handle()];
	let supervisor = start_copy(copy, program, arguments, streams, CREATE_NO_WINDOW)?;
	drop((input_reader, output_writer, error_writer));
	thread::spawn(move || relay(io::stdin(), &mut input_writer));
	let output = thread::spawn(move || relay(output_reader, io::stdout()));
	let error = thread::spawn(move || relay(error_reader, io::stderr()));
	let status = wait_for(&supervisor)?;
	let _ = output.join();
	let _ = error.join();
	Ok(status)
}

fn wait_for(supervisor: &Supervisor) -> io::Result<i32> {
	unsafe { WaitForSingleObject(supervisor.process.0, INFINITE) };
	let mut status = 0u32;
	if unsafe { GetExitCodeProcess(supervisor.process.0, &mut status) } == 0 {
		return Err(last_error("could not read the exit status"));
	}
	Ok(status as i32)
}

fn job_that_ends_with_us() -> io::Result<OwnedHandle> {
	let job = unsafe { CreateJobObjectW(ptr::null(), ptr::null()) };
	if job.is_null() {
		return Err(last_error("could not create a job"));
	}
	let job = OwnedHandle(job);
	let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { mem::zeroed() };
	limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
	let size = mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32;
	if unsafe { SetInformationJobObject(job.0, JobObjectExtendedLimitInformation, &limits as *const _ as *const c_void, size) } == 0 {
		return Err(last_error("could not limit the job"));
	}
	Ok(job)
}

fn start_stand_in() -> io::Result<StandIn> {
	let own = env::current_exe()?;
	let mut path = wide(own.as_os_str());
	let mut command = command_line::join(&[&path, &wide(OsStr::new(super::STAND_IN))]);
	path.push(0);
	let mut startup: STARTUPINFOW = unsafe { mem::zeroed() };
	startup.cb = mem::size_of::<STARTUPINFOW>() as u32;
	let mut information: PROCESS_INFORMATION = unsafe { mem::zeroed() };
	let created = unsafe {
		CreateProcessW(path.as_ptr(), command.as_mut_ptr(), ptr::null(), ptr::null(), FALSE, CREATE_SUSPENDED, ptr::null(), ptr::null(), &startup, &mut information)
	};
	if created == 0 {
		return Err(last_error("could not start the stand-in parent"));
	}
	Ok(StandIn { process: OwnedHandle(information.hProcess), _thread: OwnedHandle(information.hThread) })
}

fn parent_attribute(parent: &HANDLE) -> io::Result<AttributeList> {
	let mut size = 0;
	unsafe { InitializeProcThreadAttributeList(ptr::null_mut(), 1, 0, &mut size) };
	let mut buffer = vec![0u8; size];
	let list = buffer.as_mut_ptr() as LPPROC_THREAD_ATTRIBUTE_LIST;
	if unsafe { InitializeProcThreadAttributeList(list, 1, 0, &mut size) } == 0 {
		return Err(last_error("could not prepare the parent attribute"));
	}
	let attributes = AttributeList { _buffer: buffer, list };
	let value = parent as *const HANDLE as *const c_void;
	if unsafe { UpdateProcThreadAttribute(list, 0, PROC_THREAD_ATTRIBUTE_PARENT_PROCESS as usize, value, mem::size_of::<HANDLE>(), ptr::null_mut(), ptr::null()) } == 0 {
		return Err(last_error("could not set the parent attribute"));
	}
	Ok(attributes)
}

fn hand_over(stand_in: HANDLE, handle: HANDLE) -> io::Result<HANDLE> {
	if handle.is_null() || handle == INVALID_HANDLE_VALUE {
		return Ok(ptr::null_mut());
	}
	let mut duplicate: HANDLE = ptr::null_mut();
	if unsafe { DuplicateHandle(GetCurrentProcess(), handle, stand_in, &mut duplicate, 0, TRUE, DUPLICATE_SAME_ACCESS) } == 0 {
		return Err(last_error("could not hand the standard streams over"));
	}
	Ok(duplicate)
}

fn start_copy(copy: &Path, program: &OsStr, arguments: &[OsString], streams: [HANDLE; 3], console: u32) -> io::Result<Supervisor> {
	let job = job_that_ends_with_us()?;
	let stand_in = start_stand_in()?;
	let parent = stand_in.process.0;
	let attributes = parent_attribute(&parent)?;

	let mut startup: STARTUPINFOEXW = unsafe { mem::zeroed() };
	startup.StartupInfo.cb = mem::size_of::<STARTUPINFOEXW>() as u32;
	startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
	startup.StartupInfo.hStdInput = hand_over(parent, streams[0])?;
	startup.StartupInfo.hStdOutput = hand_over(parent, streams[1])?;
	startup.StartupInfo.hStdError = hand_over(parent, streams[2])?;
	startup.lpAttributeList = attributes.list;

	let mut path = wide(copy.as_os_str());
	let supervise = wide(OsStr::new(super::SUPERVISE));
	let program = wide(program);
	let arguments: Vec<Vec<u16>> = arguments.iter().map(|argument| wide(argument)).collect();
	let mut parts: Vec<&[u16]> = vec![&path, &supervise, &program];
	parts.extend(arguments.iter().map(Vec::as_slice));
	let mut command = command_line::join(&parts);
	path.push(0);

	let mut information: PROCESS_INFORMATION = unsafe { mem::zeroed() };
	let created = unsafe {
		CreateProcessW(
			path.as_ptr(),
			command.as_mut_ptr(),
			ptr::null(),
			ptr::null(),
			TRUE,
			EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | console,
			ptr::null(),
			ptr::null(),
			&startup as *const STARTUPINFOEXW as *const STARTUPINFOW,
			&mut information,
		)
	};
	let created = (created != 0).then_some(()).ok_or_else(|| last_error("could not start the named copy"));
	drop(attributes);
	drop(stand_in);
	created?;

	let process = OwnedHandle(information.hProcess);
	let thread = OwnedHandle(information.hThread);
	if unsafe { AssignProcessToJobObject(job.0, process.0) } == 0 {
		let error = last_error("could not tie the named copy to this process");
		unsafe { TerminateProcess(process.0, 1) };
		return Err(error);
	}
	unsafe { ResumeThread(thread.0) };
	Ok(Supervisor { process, _job: job })
}
