#[derive(Debug, PartialEq)]
pub enum RemoteCommand {
	ReceivePack { repository: String },
	UploadPack { repository: String },
	UploadArchive { repository: String },
	LfsAuthenticate { repository: String, upload: bool },
}

fn repository_path(argument: &str) -> Option<String> {
	let path = argument.strip_prefix('\'').and_then(|path| path.strip_suffix('\'')).unwrap_or(argument);
	let path = path.trim_start_matches('/');
	let path = path.strip_suffix(".git").unwrap_or(path);
	(!path.is_empty()).then(|| path.to_string())
}

pub fn remote_command(command: &str) -> Option<RemoteCommand> {
	let (program, rest) = command.split_once(' ')?;
	match program {
		"git-receive-pack" => Some(RemoteCommand::ReceivePack { repository: repository_path(rest)? }),
		"git-upload-pack" => Some(RemoteCommand::UploadPack { repository: repository_path(rest)? }),
		"git-upload-archive" => Some(RemoteCommand::UploadArchive { repository: repository_path(rest)? }),
		"git-lfs-authenticate" => {
			let (path, operation) = rest.rsplit_once(' ')?;
			Some(RemoteCommand::LfsAuthenticate { repository: repository_path(path)?, upload: operation == "upload" })
		}
		_ => None,
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn repository() -> String {
		"owner/repo".to_string()
	}

	#[test]
	fn reads_the_repository_a_push_goes_to() {
		assert_eq!(remote_command("git-receive-pack 'owner/repo.git'"), Some(RemoteCommand::ReceivePack { repository: repository() }));
		assert_eq!(remote_command("git-receive-pack '/owner/repo'"), Some(RemoteCommand::ReceivePack { repository: repository() }));
	}

	#[test]
	fn reads_the_repository_a_fetch_or_archive_comes_from() {
		assert_eq!(remote_command("git-upload-pack 'owner/repo.git'"), Some(RemoteCommand::UploadPack { repository: repository() }));
		assert_eq!(remote_command("git-upload-archive 'owner/repo.git'"), Some(RemoteCommand::UploadArchive { repository: repository() }));
	}

	#[test]
	fn reads_an_lfs_request_and_its_direction() {
		assert_eq!(remote_command("git-lfs-authenticate 'owner/repo.git' upload"), Some(RemoteCommand::LfsAuthenticate { repository: repository(), upload: true }));
		assert_eq!(remote_command("git-lfs-authenticate owner/repo.git download"), Some(RemoteCommand::LfsAuthenticate { repository: repository(), upload: false }));
	}

	#[test]
	fn leaves_every_other_command_alone() {
		assert_eq!(remote_command("uptime"), None);
		assert_eq!(remote_command("ls -la"), None);
		assert_eq!(remote_command("-V"), None);
		assert_eq!(remote_command("git-receive-pack ''"), None);
	}
}
