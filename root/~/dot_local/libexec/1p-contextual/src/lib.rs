mod git;
mod label;
mod process;
mod request;

use std::env;
use std::ffi::{OsStr, OsString};
use std::fs;

use git::repository;
use git::transport::RemoteCommand;
use request::Request;

pub fn ssh() -> ! {
	let arguments = process::launch::arguments();
	let Some((program, rest)) = arguments.split_first() else {
		eprintln!("1p-contextual: ssh needs the real ssh as its first argument");
		std::process::exit(2);
	};
	let remote_command = rest.last().and_then(|argument| argument.to_str()).and_then(git::transport::remote_command);
	let Some(remote_command) = remote_command else {
		process::launch::pass_through(program, rest);
	};
	let request = match remote_command {
		RemoteCommand::ReceivePack { repository } => push(repository),
		RemoteCommand::UploadPack { repository } => Request::Fetch { repository },
		RemoteCommand::UploadArchive { repository } => Request::Archive { repository },
		RemoteCommand::LfsAuthenticate { repository, upload } => Request::Lfs { repository, upload },
	};
	let label = label::label(&request, repository::worktree().as_deref());
	process::launch::run_named(&label, program, rest)
}

fn push(repository: String) -> Request {
	let push = process::ancestry::find(git::push::parse);
	let current_branch = repository::current_branch();
	let configuration = push.as_ref().map_or(&[][..], |push| push.configuration.as_slice());
	let destinations = push.as_ref().map(|push| push.destinations(current_branch.as_deref())).unwrap_or_default();
	let destination = if destinations.is_empty() {
		repository::push_target(configuration).or(current_branch)
	} else {
		Some(destinations.join(", "))
	};
	let commits = push.as_ref().and_then(|push| repository::commits_not_on_remote(configuration, &push.sources(), push.tracking_remote()));
	Request::Push { repository, destination, commits }
}

pub fn sign() -> ! {
	let arguments = process::launch::arguments();
	if arguments.len() < 2 || arguments[0] != "-Y" || arguments[1] != "sign" {
		process::launch::pass_through(OsStr::new(process::launch::SIGNER), &arguments);
	}
	let buffer = arguments.last().and_then(|path| fs::read(path).ok()).map(|bytes| String::from_utf8_lossy(&bytes).into_owned()).unwrap_or_default();
	let object = git::object::read(&buffer);
	let request = Request::Sign {
		repository: repository::origin_url().as_deref().and_then(git::remote_url::repository).or_else(repository::folder).unwrap_or_default(),
		branch: if object.tag.is_some() { None } else { repository::current_branch() },
		tag: object.tag.map(str::to_string),
		subject: object.subject.map(str::to_string),
	};
	let label = label::label(&request, repository::worktree().as_deref());
	let signer = env::var_os("OP_SSH_SIGN_CONTEXTUAL_PROGRAM").unwrap_or_else(|| OsString::from("op-ssh-sign.exe"));
	process::launch::run_named(&label, &signer, &process::launch::signer_arguments(&arguments))
}
